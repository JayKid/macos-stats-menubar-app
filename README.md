# MacBarStats

A lightweight macOS menu bar app that shows live temperatures, fan speeds,
CPU/GPU usage, and battery info on Apple Silicon Macs. See
[SPEC.md](SPEC.md) for the full design.

## Build & run

Prereqs: an Apple Silicon Mac running macOS 15+, Xcode 16+, and
[XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
brew install xcodegen          # one-time
xcodegen generate              # produces MacBarStats.xcodeproj
open MacBarStats.xcodeproj     # then hit ⌘R
```

The first time the app starts it will try to register itself as a login
item via `SMAppService`. macOS will show a one-time approval prompt — accept
or decline; you can flip it later from **Settings → General**.

The app uses unsandboxed IOKit / IOReport calls and is built with ad-hoc
signing only. That's deliberate — see [SPEC.md §11–§12](SPEC.md) for the
reasoning. Distribution / Developer ID / notarization tooling will come in
a later pass.

## Layout

- [SPEC.md](SPEC.md) — design doc, kept up-to-date.
- [project.yml](project.yml) — XcodeGen input. Edit this, not the
  generated `.xcodeproj`.
- [MacBarStats/](MacBarStats/) — app source.
- [spikes/](spikes/) — Phase-0 sensor spikes (reference only, see
  [spikes/README.md](spikes/README.md)).
