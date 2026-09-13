## What this changes

<!-- One or two sentences. -->

## Why

<!-- What problem it solves. Link an issue if there is one. -->

## Testing

<!-- What you ran, and on what hardware. Most contributors will not have every GPU. -->

- [ ] `.\build.ps1` passes
- [ ] `.\tests\Core.Tests.ps1` passes
- GPU tested on:
- Game tested on:

## Checklist

- [ ] No vendor binaries, weights, or download helpers added
- [ ] No anti-cheat evasion added
- [ ] No comments added to `src/` or `tests/` beyond the SPDX header
- [ ] Both tier tables still agree (`nf_gpu.cpp` and `NeuralForge.Core.ps1`)
- [ ] Every degraded path in the shaders still converges on `residual = 0`
- [ ] The quality ladder is still monotone
- [ ] Inferred vendor identifiers carry the `_Unverified` suffix and fail closed
