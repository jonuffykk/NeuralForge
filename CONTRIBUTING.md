# Contributing

Thanks for looking. This page covers what the project will and will not accept,
and how to get a change through CI on the first try.

## The three rules

**No vendor binaries, ever.** No runtime, no extracted weights, no converted
weight blobs, no download helper that fetches one. CI fails the build and blocks
the release if any appear, and that check will not be relaxed. A project that
redistributes the runtime gets taken down, and then nobody has the tool.

**No anti-cheat evasion.** Nothing here hides NeuralForge from anti-cheat,
detects whether it is being observed, or behaves differently when it is.
Contributions that add any of that are declined without discussion. If a title
does not want third-party code in its process, the correct response is to stay
out.

**No comments in source.** The only comment permitted in `src/` and `tests/` is
the two-line SPDX and copyright header. Reasoning belongs in `docs/`, and
anything that felt like it needed a comment should be a better name instead.
Look at `kNvidiaDiesWithoutTensorCores` or `cachedResidualIsUnusable` for the
style.

## Getting set up

```powershell
.\build.ps1
```

It finds Visual Studio and its bundled CMake and Ninja, so there is nothing to
install and no developer prompt to open. `-TestsOnly` skips the module and runs
only the vendor-neutral tests, which also work on Linux:

```bash
cmake -S . -B build -DNF_BUILD_MODULE=OFF && cmake --build build && ctest --test-dir build
```

## Running the tests

One command runs everything CI runs, locally:

```powershell
.\tools\nf_verify.ps1
```

That covers the build with warnings as errors, both test suites, shader
compilation, script parsing, the installer window, the comment and licence-header
rules, the vendor-binary scan, documentation links, prose style, and whether the
two tier tables still agree. Run it before opening a pull request.

The suites individually, if you want them separately:

```powershell
.\build.ps1              # 122 C++ checks over tiering, the ladder, config, tuning
.\tests\Core.Tests.ps1   # 75 PowerShell checks over detection, PE parsing, scanning
```

Neither needs a GPU, a runtime, or a game. Everything above the `IBackend` seam
is vendor-neutral on purpose, so most of the project is testable anywhere.

## What a good change looks like

Keep the two tier tables in sync. `classifyByDeviceId` in
[src/nf_gpu.cpp](src/nf_gpu.cpp) and `Get-NfTier` in
[installer/NeuralForge.Core.ps1](installer/NeuralForge.Core.ps1) describe the
same hardware. Changing one without the other is a bug, and the test suites
check both.

Preserve the failure target. Every degraded path in `nf_residual.hlsl` must
converge on `residual = 0`, which composites to the untouched game frame. A
change that can produce garbage instead of "no enhancement" will be rejected
however good it looks in a screenshot.

Keep the ladder monotone. Each rung in `kLadderOrderedByDescendingQuality` must
be strictly cheaper than the one above it, or the autotuner can step down and
get slower. There is a test for this.

Mark inferred vendor identifiers. Anything not read from a real SDK header gets
an `_Unverified` suffix on its name, and lives in the one block at the top of
[src/nf_backend.cpp](src/nf_backend.cpp). They must fail closed.

## Adding hardware support

To add a GPU family, update both tier tables, add the cost multiplier, add the
per-tier defaults in `resolveAuto`, and add test cases including at least one
negative case for a die in the same family that lacks matrix units. The GTX 16xx
carve-out is the model to follow: a false positive there means somebody watches
their game freeze.

## Adding a game source

Game discovery lives in `Get-NfGames`. A new source is a function returning the
same shape as `Test-NfGame`, added to the aggregate. Run the scanner afterwards
and check the precision: a game selector that lists driver packages and text
editors is worse than one that misses a title.

## Pull requests

Keep them focused. Say what you tested and on which hardware, since most
contributors will not have the silicon for every path. Both test suites and the
hygiene checks must pass.

Performance reports for RTX 20 and AMD are not bugs. Those numbers are
documented and expected.

## Licence

Contributions are accepted under the MIT licence in [LICENSE](LICENSE).
