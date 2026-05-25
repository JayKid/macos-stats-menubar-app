# Phase-0 sensor spikes

Three throwaway Swift Package executables that validate the three highest-risk
sensor APIs called out in [`../SPEC.md`](../SPEC.md) §13:

| Spike        | API                              | What it proves                                |
| ------------ | -------------------------------- | --------------------------------------------- |
| `SpikeTemps` | `IOHIDEventSystemClient`         | Named per-sensor temperatures on Apple Silicon |
| `SpikeFans`  | `AppleSMC` user-client (IOKit)   | Fan count + per-fan RPMs, or `no_fans=true`    |
| `SpikeGPU`   | `IOReport.framework`             | GPU busy % without root, plus channel enumeration |

## Requirements

- Apple Silicon Mac, macOS 15+
- Command Line Tools (Xcode not required): `xcode-select --install`

No third-party dependencies.

## Build

```sh
cd spikes
make            # builds all three into bin/
```

> Note: we deliberately use a tiny Makefile with direct `swiftc` invocations
> rather than Swift Package Manager. The CLT-bundled
> `libPackageDescription.dylib` ships with an ABI mismatch on the
> `SwiftVersion` → `SwiftLanguageMode` typealias rename, so `swift build`
> fails at link time on the Package init symbol. Plain `swiftc` is
> unaffected. Once full Xcode is installed (for the real app), the SPM
> path becomes available again.

## Run

```sh
make temps    # 10 samples × 1 s, prints one line per sensor per tick
make fans     # 10 samples × 1 s, prints fan readings; "no_fans=true" on Air
make gpu      # dumps IOReport channels once, then 10 busy% samples

# or the binaries directly:
./bin/spike-temps
./bin/spike-fans
./bin/spike-gpu
```

Stderr carries info/error messages. Stdout carries the per-sample readings —
pipe through `tee` or redirect for capture.

## What "passing" looks like

- **`SpikeTemps`** — at least 3 named sensors with plausible °C values
  (e.g., 25–95 °C). Names look like `pACC MTR Temp Sensor 0`, `gpu thermistor`,
  `NAND CH0`, etc., depending on SoC.
- **`SpikeFans`** — on a MacBook Pro, two fans with `actual` close to
  `target` and within `min/max`. On a MacBook Air, a single line:
  `no_fans=true`.
- **`SpikeGPU`** — the startup dump lists every channel in the "GPU Stats"
  group (state, simple, and histogram formats). Busy % is computed from the
  `PWRCTRL` channel ("GPU Power Controller States") as
  `1 - IDLE_OFF_residency / total_residency`. Note this measures **GPU
  active-power-state residency**, not compute load — even an idle UI keeps
  the GPU in the `PERF` state much of the time, so expect baseline values
  around 60–70 % when the desktop is just sitting there. The number does
  respond to real load (drops further toward 0 when display sleeps; pegs
  near 100 % under sustained `Metal` workloads).

## Cross-checks

```sh
# Temps & fans — requires sudo
sudo powermetrics --samplers smc,thermal -i 1000 -n 1

# GPU activity — requires sudo
sudo powermetrics --samplers gpu_power -i 1000 -n 1
```

These should agree (within rounding) with what the spikes report.

## Caveats

- `IOHIDEventSystemClient` is a private IOKit API. Symbols are resolved via
  `dlsym` so the spike fails loudly rather than at link time if Apple ever
  removes them. This rules out Mac App Store distribution but matches the
  spec's chosen distribution model (zipped `.app` via GitHub Releases).
- `IOReport.framework` GPU channel names vary across SoC generations (M1 vs
  M2 vs M3 vs M4). `SpikeGPU` dumps every channel at startup precisely so we
  can pick stable names for the real implementation.
- These spikes deliberately do not abstract or share more code than the bare
  minimum. The real app reimplements the sensor layer cleanly — these exist
  only to capture API shape and real-Mac output.

## After the spikes pass

We re-plan: install Xcode, scaffold the menu bar app, and port the validated
approach into proper `SensorSource` implementations as described in the spec.
