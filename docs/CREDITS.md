# Credits and prior art

NeuralForge is a synthesis, not an invention. Almost every capability here
exists because somebody else built it first, usually in public and usually for
free. This page says what came from where.

If you are credited here and want the wording changed or your name removed, open
an issue and it will be done without argument.

---

## Research

NVIDIA ADLR, *DLSS 5: Generative Neural Rendering*. The one-step pixel-space
diffusion formulation, the conditioning set (rendered frame, engine motion
vectors, carried temporal state, artistic-direction values), consistency
supervision from renderer-derived scene attributes, and the causal-deterministic
inference guarantee.

<https://research.nvidia.com/labs/adlr/DLSS5/>

The carried temporal state detail matters most to this codebase and is the one
most often left out of secondary coverage. It is the entire reason NeuralForge
caps cadence at 2 instead of exposing it as a free performance lever.

NVIDIA, for the Structure and Tone intensity split, semantic masking, and
per-asset artist overrides. NeuralForge's residual band separation maps onto that
control scheme because it is the correct decomposition, not because it was
convenient.

---

## Foundations

**OptiScaler**, the project this whole category exists because of. Upscaler API
bridging across vendors, the proxy-DLL loading model, the in-game overlay
pattern, and the general idea of sitting inside the call the game already makes.
NeuralForge's interception layer is a reimplementation of ideas proven there.

<https://github.com/cdozdil/OptiScaler>

**Dagherbou, `OptiScaler_DLSSNR`**, first to get the neural rendering stage
running through OptiScaler on DX12, and the reference for what the integration
actually has to touch.

<https://github.com/Dagherbou/OptiScaler_DLSSNR>

**ShyVortex, `OptiScaler-DLSSNR-PreSR-Multipass`**, guarded pre-SR placement,
configurable 1 to 3 pass processing, model-resolution reduction (the direct
ancestor of `WorkingScale`), separate skin and scenery controls, and the clean
forwarder.

NeuralForge's four cost levers are this project's contribution, rethought around
a residual rather than adopted as-is. The disagreement is about placement, not
about the levers, and the honest record is that the levers came first.

<https://github.com/ShyVortex/OptiScaler-DLSSNR-PreSR-Multipass>

**wilsjo2**, for the pre-SR placement work and per-pass controls contributed
upstream to `OptiScaler_DLSSNR`
([PR #36](https://github.com/Dagherbou/OptiScaler_DLSSNR/pull/36)).

**ShyVortex, `dlss-unlocked`**, feature unlocking across RTX 20, 30 and 40 for
upscaling, multi-frame generation and neural rendering. Prior art for the Ada
capability path.

<https://github.com/ShyVortex/dlss-unlocked>

**Daniel Blanco (`danielblnc`), `DLSS-NR-on-AMD`**, a ground-up reimplementation
of the network runtime for AMD: HIP kernels, memory layouts, FSR-pipeline
integration, written from scratch with no vendor code included or translated at
runtime.

This is the most technically ambitious work in the space and it deserves to be
described accurately rather than flatteringly. It currently produces around
33 fps at 1080p on an RX 9070 XT, and the stated target of RTX 5070 Ti-class
performance is a goal rather than a result. That is not a criticism. Building a
working reimplementation of a 148M-parameter runtime for another vendor's
architecture is remarkable whether or not it is playable yet.

NeuralForge's portable backend design follows this project's approach.

<https://github.com/danielblnc/DLSS-NR-on-AMD>

**DaniilSokolyuk, `video2dlssnr`**, offline application of the stage to video,
useful for reasoning about its behaviour without a game in the way.

<https://github.com/DaniilSokolyuk/video2dlssnr>

---

## Techniques

ReShade (crosire), for the proxy-DLL injection model and the expectation that an
in-game overlay is a normal thing to have.

RenoDX (clshortfuse), for the discipline of modifying a game's output without
destroying its colour intent. Making `Tone = 0` a first-class, fully supported
configuration, where you keep the game's exact grade and take only the structural
detail, comes directly from time spent in that project's issue threads.

DXVK and vkd3d-proton, for the standard of how to reimplement a graphics API
cleanly and document the limits honestly.

Dear ImGui (ocornut), for the overlay.

Kopf et al., 2007, for joint bilateral upsampling. The guided residual upsample
is a direct application.

---

## What NeuralForge contributes

Being equally precise in the other direction, because a synthesis project that
overstates its own novelty is worse than one that has none.

Deferred residual injection. Extract what the network changed rather than what it
produced, let super resolution run on the untouched game buffer, and composite
the residual afterwards at output resolution. This is the one genuinely new idea
here, and it is what makes render-resolution evaluation cost-compatible with an
unmodified temporal upscaler.

Multiplicative log-ratio residual encoding, which makes the residual
resolution-transferable, makes intensity linear in stops, makes zero an exact
no-op, and makes the Structure and Tone split fall out of the representation.

The monotone quality ladder and autotuner. Existing tools expose the levers and
leave you to it, but four interacting levers is three too many to tune per title
and tuning them independently oscillates.

Failure convergence on the original frame. Every degraded path fades to
`residual = 0`, which composites to the unmodified game image.

A safety gate that refuses rather than warns, in both the module and the
installer, and a layered GPU classifier that will not enable anything on a
device-ID guess alone.

A first-party installer with GPU detection and a game scanner. OptiScaler
explicitly warns users against third-party "manager" applications claiming
official status, which is a gap worth closing properly rather than leaving open.

None of that would exist without the five projects above having gone first.

---

## Licence

NeuralForge is MIT. It contains no vendor code, no extracted weights and no
redistributed runtime, and it never will. See
[runtimes/README.md](../runtimes/README.md).
