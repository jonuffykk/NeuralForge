# Architecture

## The one idea

Every existing approach to making DLSS neural rendering affordable trades image
stability for speed. NeuralForge does not, because it never lets the generative
signal enter the temporal upscaler. Everything below follows from that.

---

## What the stage is

DLSS 5 is not an upscaler and not frame generation. It is a one-step
pixel-space diffusion model that runs as a final stage over an already-rendered
frame, conditioned on the current colour frame, engine motion vectors, carried
temporal state, and artistic-direction values. It produces the final displayed
appearance directly. Inference is causal and deterministic.

Two properties of that description govern the rest of this document.

It is expensive, and its cost scales with pixels processed. Roughly 148M
parameters, a 158 MB FP8 weight blob, evaluated every frame.

It carries recurrent state. Evaluations are not independent. That is what makes
it temporally stable, and it is also what punishes naive frame-skipping.

---

## The placement problem

The stage has to run somewhere relative to super resolution. There are two
obvious choices and both are bad.

### Post-SR, the reference placement

```
game colour (render res) ──► SR ──► colour (output res) ──► NR ──► final
```

Correct, and what the vendor implementation does. Cost scales with output
pixels. At 4K that is the full bill, which is why the stage ships gated to the
newest hardware.

### Pre-SR, what the community forks do

```
game colour (render res) ──► NR ──► SR ──► final
```

Cost scales with render pixels, which at Quality preset is 2.25x fewer. A large,
real saving.

It also breaks temporal stability. A temporal upscaler reconstructs detail by
accumulating jittered samples of a scene it assumes is stable. The output of a
generative model is not a jittered sample of anything, so the history clamp
rejects it and you get shimmer, boiling and ghosting. That is what users report
from pre-SR forks, and what those forks warn about in their own documentation.

The saving is real. So is the cost. Both are unavoidable if you feed the network
output forward.

---

## Deferred residual injection

So don't feed it forward.

```
                    ┌──────────────────────────────────────────┐
game colour ────────┼──────────────────► SR ──► SR output ──┐  │
 (render res)       │                                       │  │
                    ▼                                       │  │
              NR @ render×scale                             │  │
                    │                                       │  │
                    ▼                                       ▼  │
              residual = NR ⊖ colour ──► band split ──► composite ──► final
```

1. Evaluate NR at `render × workingScale`. Cheap.
2. Extract the residual, meaning what NR changed rather than what it produced.
3. Super resolution runs on the original, untouched game colour. It never sees a
   generated pixel, so temporal stability is byte for byte the unmodified
   game's.
4. Upsample the residual to output resolution, guided by the SR result.
5. Composite.

The upscaler's input is unchanged, so its history clamp has nothing to reject.
The generative signal arrives afterwards, at output resolution, as a modulation
of a stable image.

### Why the residual is multiplicative

It is stored as a per-channel log₂ ratio, not a difference:

```
residual = log2(nr) − log2(colour)
final    = colour × exp2(residual × intensity)
```

Three reasons this matters.

It transfers across resolutions. The residual is extracted at one resolution and
applied against a different image, the SR output, whose absolute values differ.
A difference would inject the wrong absolute energy wherever SR changed
brightness. A ratio is scale-invariant.

Intensity becomes linear in stops, which is how a strength slider should behave,
and `0.0` is an exact no-op rather than approximately one.

The band split falls out for free. Low-frequency ratio is broad lighting and
colour response. High-frequency ratio is ambient occlusion, contact shadows,
subsurface scattering, sheen. Those are the Tone and Structure controls the
runtime exposes. They are not bolted on, they are the two halves of the
residual.

### The failure target is the original frame

Every degraded path converges on `residual = 0`, which composites to
`colour × exp2(0) = colour`, the game unmodified.

A failed reprojection, a disocclusion, a dropped evaluation, a rejected
bilateral tap, a backend error: all of them fade toward showing the player
exactly what the game rendered.

This is the most important property in the codebase. A change to
`nf_residual.hlsl` that breaks it is a bug regardless of how it looks.

---

## The four cost levers

| Lever | Mechanism | Cost | Quality impact |
|---|---|---|---|
| WorkingScale | evaluate below render resolution | `s²` | sublinear, the residual is band-limited |
| Passes | refinement iterations | `n` | diminishing after 2 |
| Selective refinement | passes 2..n only on high-energy tiles | `1 + (n−1)·frac` | negligible |
| Cadence | evaluate every N frames, reproject between | `1/N` | sharp cliff past N=2 |

At the recommended Ampere settings, working scale 0.75 with deferred placement
at render scale 0.667, the stage processes `(0.75 × 0.667)² = 0.25` of the
pixels a post-SR placement would. That is where the 40 to 60 percent recovery
figure comes from. It is a pixel-count argument, not a benchmark claim.

### Why cadence is capped at 2

The runtime carries recurrent temporal state. Skipping a frame means the next
evaluation resumes from state that is one frame stale.

At cadence 2 the reprojected residual covers the gap, because reprojecting a
delta is far more forgiving than reprojecting a full image. A bad reprojection
fades toward "no enhancement", which is a correct image. At cadence 3 and above
the staleness compounds and the state chain visibly beats.

That is the flicker people report from aggressive frame-skip settings in
existing forks. NeuralForge clamps the ladder at 2 for stateful backends. The
portable backends reconstruct temporal state explicitly instead of delegating it
to an opaque runtime, so they can checkpoint it and are not subject to the clamp.

---

## The autotuner

Four levers that interact is three too many to tune per title, and tuning them
independently oscillates.

They are arranged into a monotone quality ladder of nine rungs, each strictly
cheaper than the one above, and the tuner walks one rung at a time against a
measured GPU-time budget with deliberately asymmetric hysteresis. Six frames
over budget to step down, so a hitch is corrected almost immediately. Ninety
frames comfortably under budget to step up, so a brief quiet moment does not
cause a visible quality pump.

Manual settings are the ceiling, never the floor. Someone who asked for working
scale 0.75 does not want 1.0 handed back because a corridor was cheap to render.

The monotonicity invariant is checked by
[tests/nf_tests.cpp](../tests/nf_tests.cpp), because a ladder where a lower rung
costs more lets the tuner step down and get slower.

See `kLadderOrderedByDescendingQuality` in [nf_schedule.cpp](../src/nf_schedule.cpp).

---

## Why we hook the upscaler, not Present

`Present()` is the obvious interception point and it is useless. By then the
only thing left is colour, and the stage needs motion vectors.

The upscaler call site has everything: colour, motion vectors, depth,
jitter, both extents, and an explicit history-reset flag. NeuralForge inserts
itself inside the call the game already makes to DLSS, FSR or XeSS, and gets a
complete frame description for free.

A game with no temporal upscaler has no such call site. That is a quality
problem rather than an impossibility, and the next section covers what is left.

---

## Graphics APIs and motion sources

Two things decide whether a title can be attached to, and they are independent.

### Which graphics API the game uses

NGX exposes a full `NVSDK_NGX_D3D11_*` family alongside the D3D12 one, so
DirectX 11 is not excluded by the runtime. What is missing in a DirectX 11 title
is a D3D12 command list to record into, which NeuralForge solves the way the
community already solved it for upscalers: a private D3D12 device, shared
textures, colour and motion vectors copied in, the result copied back.

| API | Route | Cost |
|---|---|---|
| DirectX 12 | native | the stage cost alone |
| DirectX 11 | private D3D12 device, shared textures | roughly 10 percent on top |
| Vulkan | none yet | not supported |
| DirectX 9 | none | no path to a D3D12 device |

The DirectX 11 figure matches what OptiScaler reports for its own D3D11on12
bridge, which is the same mechanism.

### Where motion vectors come from

| Source | Quality | Availability |
|---|---|---|
| Engine, via the upscaler call | reference | any game with DLSS, FSR or XeSS |
| Optical flow accelerator | measurably worse | Turing and newer, except TU117 |
| None | unusable | the stage stays off |

The optical flow accelerator produces block-wise flow vectors between two
frames, at 4x4, 2x2 or 1x1 granularity. That is not the same thing as engine
motion vectors: it cannot see through transparency, it has no notion of object
identity, and it guesses at disocclusions instead of knowing about them.

It is off by default, because the residual pipeline is built on the assumption
that reprojection is trustworthy and this weakens that. `AllowOpticalFlow = true`
turns it on for a title that has no upscaler at all, and the honest description
is that it turns "nothing" into "something degraded".

TU117 is carved out again here. The optical flow hardware is absent on exactly
the same die that has no tensor cores, so a GTX 1650 fails both tests.

---

## Module map

```
src/
├── nf.h              every declaration, one header
├── nf_ngx.h          the public NGX surface, loaded at runtime
├── nf_gpu.cpp        adapter identification and tiering
├── nf_config.cpp     INI, clamping, per-tier defaults
├── nf_schedule.cpp   the quality ladder and autotuner
├── nf_backend.cpp    NGX loader, D3D11 and D3D12 paths, GPU timing
├── nf_pipeline.cpp   per-frame orchestration
├── nf_hook.cpp       module entry, interception, safety gate
├── nf_overlay.cpp    in-game controls
└── nf_residual.hlsl  extract, band split, reproject, composite
```

The first four compile with `NF_NO_D3D` and need nothing but a C++20 compiler,
which is why the test suite runs on Linux with no GPU.

### The honesty boundary

`IBackend` is the seam between what this repository fully specifies and what it
does not.

Above the seam, everything is complete, vendor-neutral and covered by tests:
scheduling, residual mathematics, compositing, tuning, hooking, safety.

Below it sits the vendor runtime, which the user supplies from software they
already licence.

The NGX surface itself is public and documented: the init, capability query,
parameter allocation, scratch sizing, feature creation, evaluation and release
entry points for both D3D11 and D3D12, along with the standard parameter names.
[nf_ngx.h](../src/nf_ngx.h) declares that surface and
[nf_backend.cpp](../src/nf_backend.cpp) resolves it from `nvngx.dll` at runtime
through `GetProcAddress`, so the build needs no vendor SDK and a missing export
is a clear error rather than a link failure.

What is not public is the feature identifier for neural rendering and the
parameter names it consumes. Those carry an `_Unverified` suffix on their names,
sit in one block, and fail closed: a wrong value makes the capability check or
feature creation return a documented NGX error that the overlay prints verbatim,
never a silent misbehaviour. When the real identifiers become known, that block
changes and nothing else does.

---

## Safety gate

NeuralForge loads into a game process and modifies its render pipeline. In a
title with kernel-level anti-cheat, that is indistinguishable from what a cheat
does, and the consequence lands on the player's account.

The default is to refuse. Initialisation aborts, before a single hook is
installed, if an anti-cheat module is resident or the host executable is on the
denylist. The installer runs the same check against the game directory and
declines to write anything.

The direction of that check matters. Nothing in this project attempts to hide
NeuralForge from anti-cheat, detect whether it is being observed, or behave
differently when it is. If a title does not want third-party code in its
process, the correct response is to stay out.
