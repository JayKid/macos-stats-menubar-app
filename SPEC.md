# MacBarStats — Spec

A lightweight macOS menu bar app that monitors temperatures, fan speeds, CPU/GPU
usage, and battery on Apple Silicon MacBooks. Designed for personal use and
easy sharing via GitHub Releases (no paid Developer ID).

---

## 1. Goals

- Always-visible **menu bar item** showing one or more configurable live stats
  (default: CPU temperature).
- **Popup details window** with current readings for every available sensor,
  rolling **historical sparklines/charts**, CPU%, GPU%, and battery info.
- **Visual-only thresholds**: menu bar icon/text changes color (e.g. yellow
  / red) when configured per-stat thresholds are exceeded. No notifications.
- Low background overhead — default 5 s sampling interval, user-configurable.
- Graceful behavior on machines without fans (MacBook Air): show "No fans"
  rather than zeros or errors.

## 2. Non-goals (v1)

- No notification center alerts.
- No iCloud sync, telemetry, or analytics.
- No persistence of historical data across launches (in-memory only).
- No App Store distribution.
- No Intel Mac support.

## 3. Target environment

- **Hardware:** Apple Silicon (M1 and later).
- **OS:** macOS 15 (Sequoia) or later.
- **Language / UI:** Swift 5.10+ / SwiftUI, with AppKit (`NSStatusItem`) for
  the menu bar item and `MenuBarExtra` where it cleanly fits.
- **Tooling:** Xcode 16+, no third-party Swift package dependencies in v1
  unless required for charts (see §6.2).

## 4. Architecture overview

```
+--------------------+        +----------------------+
|   SensorSources    | -----> |   SampleAggregator   |
|  (IOHID, SMC,      |        |  (rolling buffer,    |
|   IOReport, IOPS)  |        |   threshold eval)    |
+--------------------+        +----------+-----------+
                                         |
                            publishes    v
                              @MainActor ObservableObject
                                         |
              +--------------------------+---------------------------+
              v                                                      v
   +---------------------+                              +---------------------+
   |  MenuBarItemView    |                              |  DetailsPopupView   |
   |  (NSStatusItem)     |                              |  (popover / window) |
   +---------------------+                              +---------------------+
```

- A single **Sampler** actor polls all sensor sources on a timer and emits a
  `Snapshot` value to an `@MainActor` `AppState` (an `ObservableObject`).
- `AppState` holds a **rolling in-memory buffer** of recent snapshots (capacity
  derived from sampling interval × max history window).
- Both the menu bar view and the popup view observe `AppState`.
- Settings live in a separate `Settings` `ObservableObject`, persisted to
  `UserDefaults`.

## 5. Sensor data sources

All sensor access is wrapped behind a `SensorSource` protocol so each can be
mocked for previews/tests and gracefully degrade when unavailable.

### 5.1 Temperatures — `IOHIDEventSystemClient`

On Apple Silicon, thermals are exposed through `IOHIDEventSystemClient` with
matching dictionaries on `kHIDPage_AppleVendor` (page `0xff00`) and the
temperature usage. We will enumerate matching services and read their
`kIOHIDEventFieldTemperatureLevel` events.

Sensors we will surface (best-effort, names normalized):

- CPU performance cluster (P-cores) avg
- CPU efficiency cluster (E-cores) avg
- GPU
- SoC / die
- Battery
- Ambient (if present)

If a sensor isn't found on the current Mac, it is simply omitted from the UI.

### 5.2 Fans — AppleSMC via IOKit

Fan data on Apple Silicon MacBook Pros is still available via SMC keys read
through a user-client connection to `AppleSMC`:

- `FNum` — fan count (UInt8). If `0`, hide the fan section entirely.
- Per fan `i`:
  - `F{i}Ac` — actual RPM
  - `F{i}Mn` — minimum RPM
  - `F{i}Mx` — maximum RPM
  - `F{i}Tg` — target RPM

### 5.3 CPU usage — `host_processor_info`

Sample `PROCESSOR_CPU_LOAD_INFO` on each tick and compute per-core and
aggregate utilization from the delta between samples (user + system + nice) /
total ticks.

### 5.4 GPU usage — `IOReport.framework`

Use Apple's public `IOReport` framework to subscribe to GPU performance state
residency channels and derive a busy percentage. **Risk:** the exact channel
names vary slightly across Apple Silicon generations. A Phase-0 spike (§13)
will confirm a stable approach; if not viable without root, GPU% degrades
gracefully to "n/a" with a note in the UI.

### 5.5 Battery — `IOPowerSources` + IORegistry

- `IOPSCopyPowerSourcesInfo` / `IOPSCopyPowerSourcesList` for: charge %,
  charging state, time-to-full / time-to-empty, source.
- `AppleSmartBattery` IORegistry entry for: cycle count, design capacity,
  max capacity (health %), instantaneous wattage (`InstantAmperage` ×
  `Voltage`).

## 6. UI

### 6.1 Menu bar item (`NSStatusItem`)

- **Default contents:** a small thermometer SF Symbol + CPU temperature in °C
  (e.g. `🌡 62°`). Uses monospaced digits to avoid width jitter.
- **Configurable layout:** users can add additional stats from a fixed list:
  - CPU temp, GPU temp, SoC temp
  - Fan 1 / Fan 2 RPM
  - CPU %, GPU %
  - Battery %
- Multiple stats render inline, separated by a thin vertical bar, in the order
  the user arranged them.
- **Color thresholds:** when a displayed stat exceeds its user-defined warn /
  critical thresholds, that stat (and only that stat) renders in
  `systemYellow` / `systemRed`. Icon background / shape does not change.
- Click → toggles the details popover anchored to the status item.
- Right-click (or `⌥`-click) → context menu with: Preferences…, Pause Updates,
  Quit.

### 6.2 Details popup

Implemented as an `NSPopover` containing a SwiftUI view. Sections, top to
bottom:

1. **Temperatures** — list of all detected temp sensors with current value
   and a small inline sparkline of the rolling window.
2. **Fans** — per fan: actual / target / min–max RPM with a sparkline.
   Section hidden entirely if `FNum == 0`.
3. **CPU & GPU usage** — current % plus per-core CPU bars; sparkline for
   aggregate CPU% and GPU%.
4. **Battery** — % charge, charging state, time remaining, cycle count,
   health %, instantaneous wattage.
5. **Footer** — last update timestamp, "Preferences…" button, "Quit" button.

Charts use Apple's built-in **Swift Charts** (available since macOS 13) — no
third-party dependency needed.

The popover is sized to roughly 360 × 520 pt; it does not need to be resizable
in v1.

### 6.3 Preferences window

A standalone `Settings` scene with tabs:

- **General** — sampling interval (slider, 1–30 s), history window (slider,
  1–60 min), launch at login toggle.
- **Menu bar** — drag-to-reorder list of stats to display in the bar, with
  show/hide toggles. Live preview row at the top.
- **Thresholds** — per-stat warn/critical values (temps in °C, fans in RPM,
  CPU/GPU in %, battery low % only). Reset-to-defaults button.
- **About** — version, build, links to repo + license.

## 7. Sampling & data model

```swift
struct Snapshot {
    let timestamp: Date
    let temperatures: [SensorReading]   // id, displayName, °C
    let fans: [FanReading]              // index, rpm, target, min, max
    let cpuPercent: Double              // 0...100
    let perCoreCPU: [Double]
    let gpuPercent: Double?             // nil if unavailable
    let battery: BatteryReading?
}
```

- Sampling interval: **default 5 s**, user range **1–30 s**.
- History window: **default 15 min**, user range **1–60 min**.
- Buffer is a ring buffer sized to `ceil(historyWindow / samplingInterval)`,
  rebuilt when either setting changes (old samples are kept where the new
  buffer overlaps).
- "Pause Updates" stops the timer but leaves the existing buffer intact.

## 8. Thresholds & visual alerts

- Each displayable stat has an optional `(warn, critical)` threshold pair.
- Default suggestions (overridable):
  - CPU/GPU/SoC temp: warn 85 °C, critical 95 °C
  - Battery low: warn 20 %, critical 10 %
  - CPU/GPU %: no defaults (off)
  - Fans: no defaults (off)
- Evaluation runs each tick. The menu bar text recolors per-stat; the popup
  shows a small colored dot next to any tripped row.
- Strictly visual — no notifications, no sounds.

## 9. Login item

- Toggleable in **Preferences → General**, default **on** on first launch
  (one-shot prompt the first time the app is launched, so the user opts in
  explicitly rather than being surprised).
- Implemented with `SMAppService.mainApp` (macOS 13+ API).

## 10. Project structure

```
macos-bar-stats/
├── SPEC.md                       # this file
├── README.md                     # install + Gatekeeper workaround
├── LICENSE
├── MacBarStats.xcodeproj/
├── MacBarStats/
│   ├── MacBarStatsApp.swift      # @main, MenuBarExtra wiring
│   ├── AppState.swift
│   ├── Settings/
│   │   ├── Settings.swift        # ObservableObject backed by UserDefaults
│   │   └── SettingsView.swift
│   ├── Sensors/
│   │   ├── SensorSource.swift    # protocol
│   │   ├── IOHIDTemperatureSource.swift
│   │   ├── SMCFanSource.swift
│   │   ├── CPUUsageSource.swift
│   │   ├── GPUUsageSource.swift  # IOReport-based
│   │   ├── BatterySource.swift
│   │   └── SMC/                  # low-level SMC user-client wrapper
│   ├── Sampling/
│   │   ├── Sampler.swift         # actor
│   │   └── RingBuffer.swift
│   ├── UI/
│   │   ├── MenuBarItemView.swift
│   │   ├── DetailsPopupView.swift
│   │   ├── Sections/
│   │   │   ├── TemperaturesSection.swift
│   │   │   ├── FansSection.swift
│   │   │   ├── UsageSection.swift
│   │   │   └── BatterySection.swift
│   │   └── Components/
│   │       ├── Sparkline.swift
│   │       └── StatRow.swift
│   └── Resources/
│       └── Assets.xcassets
└── MacBarStatsTests/
    └── …
```

- **Bundle identifier:** `dev.joselopez.MacBarStats` (placeholder — confirm
  before first release).
- **App category:** `public.app-category.utilities`.
- **`LSUIElement = YES`** so the app has no Dock icon or main menu.

## 11. Permissions & entitlements

- **No sandbox** (deliberate — required for raw SMC / IOReport access).
- **No special entitlements** beyond default; SMC access via IOKit user
  clients does not require an entitlement when unsandboxed.
- **No microphone, camera, network, or AppleEvents usage.**

If a future change adds outbound networking (e.g. update checks), that will
be called out separately.

## 12. Distribution & sharing

- Built locally with Xcode, archived as a `.app`, zipped, and attached to a
  GitHub Release.
- App is **not** signed with a Developer ID (ad-hoc signed only). The README
  will document the first-launch workaround:

  > On first launch, macOS will block the app with "MacBarStats can't be
  > opened because Apple cannot check it for malicious software." To allow
  > it, either:
  > - Right-click the app in Finder, choose **Open**, then click **Open** in
  >   the dialog; or
  > - Run `xattr -dr com.apple.quarantine /Applications/MacBarStats.app`
  >   in Terminal.

- Versioning follows `MAJOR.MINOR.PATCH`. Releases use Git tags `vX.Y.Z`.

## 13. Phase-0 spikes (do before locking the spec)

These are the items most likely to invalidate assumptions above. Each should
be a tiny standalone scratch target before the real implementation begins.

1. **IOHID temperature enumeration** on the target Mac — confirm we get
   meaningful, named sensors and that the polling rate is cheap.
2. **GPU usage via IOReport** without `sudo` — confirm a stable channel /
   group name and acceptable cost. If this fails, decide: drop GPU% from v1
   or invoke `powermetrics` (which would require root and is therefore
   rejected by default).
3. **AppleSMC fan keys** on an M-series MacBook Pro — verify `F0Ac` etc. read
   correctly via the user-client path.

## 14. Open questions / future work

- Should temperature units be user-selectable (°C / °F)? — currently °C only.
- Multi-monitor / which-display behavior for the popup. SwiftUI handles this
  reasonably by default; flag if it doesn't.
- Sleep / wake handling — pause sampling while the system is asleep (probably
  via `NSWorkspace` sleep/wake notifications). v1 keeps it simple and just
  lets the timer resume; revisit if it causes spurious gaps in charts.
- Optional dark/light icon variants if the default SF Symbol doesn't read
  well in both menu bar themes.
