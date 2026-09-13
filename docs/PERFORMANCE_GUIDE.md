# Performance guide

## Start here

Leave the autotuner on and set a budget. For most people that is the whole
guide.

```ini
[Performance]
AutoTune = true
BudgetMs = 2.0
```

The tuner walks a fixed quality ladder against measured GPU time. It drops
quality within 6 frames of going over budget and takes 90 frames of comfortable
headroom before raising it again, so it protects your frame rate quickly and
never pumps quality visibly.

Everything below is for when that is not enough.

---

## Working out the budget

`BudgetMs` is the GPU time the stage is allowed to take. It is not a frame time
target and not a frame rate target.

```
budget = (1000 / current_fps) − (1000 / target_fps)
```

At 120 fps wanting to hold 100, that gives `8.33 − 10.0`, so you cannot afford
anything and the honest answer is that this feature is not free on your setup.

At 140 fps wanting to hold 100, that gives `7.14 − 10.0`, about 2.8 ms of
headroom.

Set the budget slightly under what you calculated. The stage is not the only
thing competing for the GPU.

---

## The levers, in the order to reach for them

### 1. WorkingScale

Resolution the network evaluates at, relative to render resolution. Cost falls
with the square.

| Scale | Cost | What you see |
|---|---|---|
| 1.00 | 100% | reference |
| 0.85 | 72% | nothing, honestly |
| 0.75 | 56% | very close to free |
| 0.65 | 42% | slight softening of fine contact shadows |
| 0.50 | 25% | visible, still clearly better than disabling the stage |

This lever is unusually forgiving here, and it is worth understanding why.
NeuralForge only consumes the residual, meaning the difference the network made
rather than the image it produced, and a residual is band-limited by
construction. Most of its energy sits in frequencies that survive a 0.75x round
trip intact. A conventional pre-SR fork upsamples the network's output, which is
not band-limited, and pays much more for the same scale reduction.

### 2. Passes with selective refinement

Pass 1 is full-frame. Passes 2 and 3 are restricted to tiles where pass 1
actually changed something, typically 15 to 30 percent of them.

| Passes | Cost, selective | Cost, non-selective |
|---|---|---|
| 1 | 1.00x | 1.00x |
| 2 | ~1.22x | 2.00x |
| 3 | ~1.44x | 3.00x |

Leave `SelectiveMultipass = true`. Pass 2 is worth having on Ada and Blackwell.
Pass 3 has clearly diminishing returns and mostly exists for screenshots.

### 3. Cadence

Evaluate every N frames, reprojecting the residual in between.

| Cadence | Cost | Verdict |
|---|---|---|
| 1 | 1.00x | default |
| 2 | 0.50x | safe, genuinely useful on Ampere and below |
| 3+ | 0.33x | don't |

The runtime carries recurrent temporal state between evaluations, so skipping a
frame leaves that state one frame stale. At cadence 2 the reprojected residual
covers the gap, because reprojecting a delta is far more forgiving than
reprojecting a frame and a bad reprojection fades toward "no enhancement", which
is a correct image.

At cadence 3 and above the staleness compounds and the state chain beats
visibly. If you have seen flicker from aggressive frame-skip settings in other
tools, that is what it was. NeuralForge clamps the ladder at 2 on stateful
backends.

### 4. Placement

| Setting | Cost basis | Use when |
|---|---|---|
| `deferred` | render res, residual composite | always, unless you have a reason |
| `postsr` | output res | RTX 40 or 50 at 1080p to 1440p, when you want the reference result |
| `presr` | render res, output fed to SR | never, see below |

`presr` is included for comparison. It is the placement other forks use, it is
cheap, and it feeds a generative signal into a temporal upscaler that will
reject it. That rejection is the shimmer. `deferred` gets the same cost basis
without it.

On tiers below Ada, `postsr` is moved to `deferred` automatically, because
paying output-resolution cost on silicon that struggles with render-resolution
cost is not a configuration anybody wants.

---

## Tuning by tier

### RTX 50 and RTX 40

```ini
AutoTune = true
BudgetMs = 2.0          ; 2.5 on Ada
WorkingScale = 1.0
Passes = 2
Placement = deferred
```

### RTX 30

```ini
AutoTune = true
BudgetMs = 4.0
WorkingScale = 0.75
Passes = 1
Placement = deferred
```

Expect the tuner to settle around rung 4 to 6. At 4K on anything below a 3080,
expect it to bottom out. See [GPU_COMPATIBILITY.md](GPU_COMPATIBILITY.md).

### RTX 20

```ini
AutoTune = true
BudgetMs = 6.0
WorkingScale = 0.65
Passes = 1
Placement = deferred
```

This tier costs roughly 18x an RTX 50, so on most Turing cards the stage will
cost more than the rest of the frame. It runs. That is a different claim from it
being a good idea.

### AMD

```ini
AutoTune = true
BudgetMs = 8.0
WorkingScale = 0.50
Passes = 1
Backend = hip           ; or directml if HIP is unavailable
```

Published results are around 33 fps at 1080p on an RX 9070 XT. These settings
make the number honest, not good. This path is for experimentation.

---

## Reading the overlay

```
Stage cost: 1.84 ms  (inference 1.61 + composite 0.23)
Active rung: Performance (0.75x, 1 pass)
```

Stage cost is measured GPU time, not an estimate.

Composite is the residual pipeline: extract, band split, guided upsample. It
scales with output resolution and is roughly constant per tier. If it is more
than about 15 percent of the total, your working scale is probably too low to be
buying you anything.

Active rung is what is actually running. When the tuner has overridden a manual
setting, the overlay says so next to that setting rather than showing you a
value that is not in effect.

---

## Things that will not help

Lowering `TileThreshold` makes more tiles hot, so refinement passes cost more.
Raise it to make them cheaper.

Turning off `SelectiveMultipass` to reduce overhead. The compaction pass costs
microseconds and saves whole milliseconds.

Cadence above 2, covered above. It trades a real artefact for frame time you can
get more cleanly from `WorkingScale`.

Running with `RequireMotionVectors = false`. Without motion vectors there is no
reprojection, no disocclusion test and no temporal coherence, so the stage
becomes a per-frame independent generative pass and flickers badly. The flag
exists for debugging.
