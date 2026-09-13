# Changelog

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Real NGX backend. The runtime is resolved from `nvngx.dll` at load time
  through `GetProcAddress`, so the build needs no vendor SDK and a missing
  export is a clear error rather than a link failure. Initialisation, capability
  query, parameter allocation, scratch sizing, feature creation and evaluation
  are implemented for both D3D12 and D3D11.
- GPU timestamp queries, so the autotuner drives on measured stage cost rather
  than the seeded estimate.
- DirectX 11 support through a private D3D12 device. Costs roughly 10 percent on
  top of the stage, matching what the same mechanism costs elsewhere.
- Optical flow as a motion vector source for titles with no upscaler, behind
  `AllowOpticalFlow`, off by default.
- `tools/nf_verify.ps1`, which runs every check CI runs in one command.
- Automatic tagging. Pushing a new version heading to `CHANGELOG.md` on `main`
  creates the tag and publishes the release, with notes composed from that
  version's section and conditional banners for breaking changes, pre-releases
  and known limitations.

### Changed

- DirectX 11 titles are no longer reported as unsupported. That was wrong: NGX
  exposes a full `NVSDK_NGX_D3D11_*` family, and a bridge covers the rest.
- A game without an upscaler is now `No motion vectors` rather than a hard
  refusal, since optical flow gives a degraded path where there was none.
- `runtimes/README.md` and the default config lost the parts that duplicated
  `docs/`. The installer sets everything with sliders.

### Fixed

- The scanner listed driver packages, text editors and Electron applications as
  games. Real games are now identified by executable size, install size, engine
  runtimes and packed assets, with Chromium and known applications excluded.
- Steam library deduplication was case-sensitive, so every game in a library was
  scanned twice.
- Blocking on an unreadable graphics API would have excluded every title with a
  packed executable.

## [0.1.0] - 2026-09-12

First public cut. The scheduling, residual mathematics, detection, safety and
installer layers are complete and tested. The vendor and portable inference
backends are interfaces awaiting integration, so the neural rendering stage does
not run yet.

### Added

- Deferred residual injection. The network runs at render resolution, but its
  output never reaches the upscaler. Only the residual it produced is
  composited, at output resolution, so super resolution keeps the temporal
  stability of the unmodified game.
- Multiplicative log-ratio residual encoding, which transfers correctly between
  resolutions, makes intensity linear in stops, makes zero an exact no-op, and
  puts the low and high frequency bands on the runtime's Tone and Structure
  controls.
- A monotone nine-rung quality ladder with an autotuner that holds a measured
  GPU-time budget. It steps down within 6 frames of going over and needs 90
  frames of headroom before stepping up, so it protects frame rate quickly
  without pumping quality visibly. Manual settings are the ceiling, never the
  floor.
- Layered GPU classification. TU116 and TU117 are carved out of the Turing range
  explicitly, because those dies carry the Turing name with no tensor cores and
  a false positive there freezes a game.
- Cadence clamped to 2 on backends that carry recurrent temporal state. Beyond
  that the state goes stale enough to beat visibly, which is the flicker other
  tools produce from aggressive frame-skip settings.
- Safety gate that refuses rather than warns, in both the installer and the
  module, when anti-cheat is present.
- Installer window with GPU detection, a game scanner covering Steam, Epic, GOG,
  installed programs and arbitrary folders, PE import parsing to read each
  game's real graphics API, visual tuning that writes the config, and a complete
  uninstall backed by a manifest.
- Five compute shaders for extract, band split, reprojection, composite and tile
  compaction, compiled with warnings as errors.
- 122 C++ checks and 75 PowerShell checks, none of which need a GPU, a runtime
  or a game.
- One workflow covering logic tests on Windows and Linux, installer tests,
  module and shader compilation, licence-header and vendor-binary hygiene, and
  release publication on a tag.

### Known limitations

- The neural rendering stage does not run. `IBackend` implementations are
  interfaces.
- The NGX feature identifier and its parameter names are inferred rather than
  read from an SDK header. They carry an `_Unverified` suffix and fail closed.
- A game with no temporal upscaler has no interception point, because motion
  vectors do not survive to `Present()`. This is structural.
- AMD is not playable. Published results for a ground-up reimplementation are
  around 33 fps at 1080p on an RX 9070 XT.
- GTX 16xx and older cannot run this at all.

[Unreleased]: https://github.com/Jonuffy/NeuralForge/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Jonuffy/NeuralForge/releases/tag/v0.1.0
