# GPU compatibility

This page has to be willing to tell you that your card cannot do this. Three of
the six supported tiers are not a good experience, and one tier is not an
experience at all.

---

## Summary

| GPU | Tier | Backend | Cost vs RTX 50 | Verdict |
|---|---|---|---|---|
| RTX 50 Blackwell | native | vendor, FP8 | 1.0x | Works as intended |
| RTX 40 Ada | unlocked | vendor, FP8 | ~1.6x | Genuinely good, and closer to RTX 50 than people assume |
| RTX 30 Ampere | fallback | vendor, FP16 | ~9x | Playable only with aggressive settings |
| RTX 20 Turing | fallback | vendor, FP16 | ~18x | Technically functional, not a good idea |
| RX 9000 RDNA 4 | reimplementation | HIP / DirectML | ~6x+ | Experimental, not a way to play a game today |
| RX 7000 RDNA 3 | reimplementation | HIP / DirectML | ~12x+ | Research interest only |
| GTX 16xx, 10xx and older | none | none | n/a | Impossible, no tensor cores |

Cost is the per-frame cost of the neural rendering stage against an RTX 50
baseline at identical settings. It is a hardware-throughput argument, not a
benchmark result.

---

## RTX 50, Blackwell

The reference path. FP8 weights consumed as shipped, fifth-generation tensor
cores, vendor runtime. Everything in NeuralForge is tuned against this as 1.0.

Default budget 2.0 ms, full working scale, single pass, every frame.

---

## RTX 40, Ada

This is the tier most worth being precise about, because it is widely
misdescribed.

Ada has FP8 tensor cores. Nothing is emulated, nothing is requantised, no
precision is lost. The only thing between an RTX 40 and a native-precision
evaluation is a runtime capability check, which is a gate rather than a
limitation.

That is why the Ada path lands around 1.6x instead of the ~9x a genuine
precision fallback costs. If you have an RTX 40, you are not running a degraded
version of this. You are running the real thing on slightly slower silicon.

Default budget 2.5 ms. Full working scale is usually affordable at 1440p.

---

## RTX 30, Ampere

Ampere has third-generation tensor cores with FP16 and BF16, and no FP8 tensor
path. The weights must be requantised to FP16, which roughly doubles the tensor
work and roughly doubles the resident weight footprint, from about 158 MB to
about 340 MB of VRAM occupied while the stage is active.

Combined with Ampere's lower baseline throughput, the stage costs on the order
of 9x an RTX 50.

Concretely, this is playable, but only because of the deferred design. You will
be running working scale 0.75 or lower and you should leave the autotuner on.
NeuralForge raises the default budget to 4.0 ms and the starting working scale
to 0.75 automatically.

On a 3060 at 4K this will not work and no setting fixes it. At 1080p to 1440p on
a 3080 or better it is a real option.

---

## RTX 20, Turing

Everything in the Ampere section applies, plus roughly another factor of two
from lower tensor throughput. Around 18x an RTX 50.

Bluntly: on most Turing cards the neural rendering stage will cost more frame
time than the entire rest of the frame. NeuralForge will run it, will autotune
down to 0.55x working scale at cadence 2, and will still probably not give you
something you want to play.

It is supported because supported and recommended are different words, and
because a 2080 Ti at 1080p is borderline rather than hopeless. Default budget
6.0 ms, starting scale 0.65.

Please do not file performance bugs for this tier. The number is the number.

---

## AMD, RDNA 3 and RDNA 4

There is no vendor runtime for AMD. Running this at all requires a ground-up
reimplementation: weights extracted and converted locally, then executed against
HIP kernels or DirectML.

That work exists and it is genuinely impressive, see [CREDITS.md](CREDITS.md).
What it is not, yet, is playable. The published state of the art is around
33 fps at 1080p on an RX 9070 XT, a card that runs the same titles several times
faster with the stage disabled. The stated goal of reaching RTX 5070 Ti-class
performance is a goal, not a current result.

NeuralForge exposes this path because the work deserves to be built on, and sets
a wide default budget (8.0 ms on RDNA 3, 6.0 ms on RDNA 4) so the numbers you
see are honest. It does not pretend the result is a gaming configuration, and no
documentation, release note or chart in this repository will.

The portable backends also require you to convert weights locally first.
NeuralForge ships neither weights nor a downloader.

---

## GTX 16xx, GTX 10xx and older: impossible

Not slow, and not unsupported for now. **Impossible.**

The GTX 16xx family (TU116 and TU117) shares the Turing architecture name but
ships no tensor cores at all. That is the specific product-segmentation
difference between a GTX 1660 and an RTX 2060. Pascal and earlier have no matrix
units of any kind.

A 148M-parameter network evaluated every frame has nowhere to run on this
silicon. Executing it on shader cores would land somewhere in the hundreds of
milliseconds per frame. No optimisation, working scale or cadence changes this.

NeuralForge detects these parts and refuses with an explanation rather than
letting you discover it as a hard lock. The device-ID ranges for TU116 and TU117
are carved out of the Turing range in [nf_gpu.cpp](../src/nf_gpu.cpp), and the
carve-out is covered by a unit test, because a false positive here means
somebody watches their game freeze.

Intel Arc has XMX units and is theoretically in scope, but no reimplementation
exists and NeuralForge will not claim one. It reports as unsupported.

---

## How detection works

Three layers, most authoritative first.

1. Vendor library. NVAPI `NvAPI_GPU_GetArchInfo` and AGS `agsGetGPUInfo` report
   the architecture directly, which is correct by construction.
2. Capability probe. DirectML is asked which tensor data types the device can
   actually accelerate. That is the question we care about, answered without
   knowing the marketing name.
3. Device-ID heuristic. Broad PCI ID ranges, advisory only.

Layer 3 alone never enables anything. A device is promoted above `Unsupported`
only if layer 1 or 2 agrees. The ID ranges for tensor-less Turing dies interleave
with tensor-equipped ones, so the heuristic is not trusted to make that call on
its own.

If the overlay says the GPU was identified by device ID heuristic, the vendor SDK
was unavailable and the architecture name shown is a guess. Whether anything runs
is still gated by the capability probe, so that is a reporting limitation rather
than a safety one.
