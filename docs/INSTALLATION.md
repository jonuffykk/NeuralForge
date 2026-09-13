# Installation

## Before anything else

**Single-player titles only.** NeuralForge modifies a game's render pipeline
from inside its process. In a title with kernel-level anti-cheat that is
indistinguishable from what a cheat does, and the consequence lands on your
account.

Setup refuses to install when it finds anti-cheat in the game directory, and the
module refuses to initialise when it finds one resident in the process. Do not
turn either off to see if it works. Nothing here hides from anti-cheat, detects
whether it is being observed, or behaves differently when it is, and that is
deliberate.

**You supply the runtime yourself.** NeuralForge does not ship, mirror, bundle
or download it. CI blocks any release archive containing a vendor binary. See
[runtimes/README.md](../runtimes/README.md).

### Requirements

Windows 10 21H2 or newer, x64.

A DirectX 12 or DirectX 11 game, ideally with a working temporal upscaler:
DLSS, FSR 2, 3 or 4, or XeSS. That call is where engine motion vectors live.
Without one the stage falls back to the optical flow accelerator, which is worse
and off by default. Vulkan and DirectX 9 have no route at all. See
[ARCHITECTURE.md](ARCHITECTURE.md#graphics-apis-and-motion-sources).

A GPU that can run it. Check [GPU_COMPATIBILITY.md](GPU_COMPATIBILITY.md) first,
especially on GTX 16xx or older, where the answer is no.

---

## Install

Extract the release and run `NeuralForge.bat`.

The window shows your GPU with its tier, the expected cost against an RTX 50, a
suggested budget, whether you have supplied a runtime, and whether the module is
built. Below that, every game found in Steam, Epic, GOG, your installed programs
and your game folders.

Each game's graphics API is read from its executable's import table rather than
guessed, so the status is a fact about the binary:

| Status | Meaning |
|---|---|
| Ready | DirectX 12 with an upscaler. Native path. |
| Ready via bridge | DirectX 11 with an upscaler. Runs through a private D3D12 device, roughly 10 percent on top of the stage cost. |
| No motion vectors | No DLSS, FSR or XeSS found. Needs the optical flow accelerator, which is off by default and measurably worse than engine motion vectors. |
| Unsupported API | Vulkan or DirectX 9. There is no bridge for either. |
| Blocked | Anti-cheat present. Setup refuses. |

If a game lives somewhere the scan does not reach, use Add folder and point it at
the directory that contains your game folders.

The Tuning tab sets Structure, Tone, the frame budget and the cost levers with
sliders, and writes them into the game's config on install, so there is no text
file to edit. Setup backs up anything it is about to overwrite, copies the module
and shaders, and seeds anything you left alone from your GPU tier.

Uninstall from the same window. Nothing is patched in place and nothing is
written to game memory, so removal restores from the backup manifest and deletes
what it added.

### Console mode

Same checks, no window:

```powershell
.\installer\NeuralForge.ps1 -Console
```

### Checking hardware without installing

```powershell
.\tools\nf_probe.ps1
```

Reports your adapter, its tier, the backend that would be selected, the expected
cost, and whether anything will stop you. Add `-CheckRuntime` to verify a runtime
you have supplied, including its Authenticode signature.

---

## First run

Launch the game and enable its upscaler. Any of DLSS, FSR or XeSS will do.

Press Insert. Confirm the top of the overlay shows your GPU and a backend line
that is not an error.

Leave `AutoTune` on and set `BudgetMs` to what you can afford. The
[performance guide](PERFORMANCE_GUIDE.md#working-out-the-budget) has the
arithmetic.

Adjust Structure and Tone to taste. If the game has a strong deliberate colour
grade, try `Tone = 0` first: you keep the game's exact colours and still get the
structural detail.

---

## When it does not work

The overlay status line is the first place to look. It is written to be read by
a player, not a programmer.

| Status | Meaning |
|---|---|
| an anti-cheat module is loaded | Working as designed. Do not override it. |
| no motion vectors at this call site | The upscaler was not intercepted, or it is running a path with no motion vectors. Confirm the upscaler is actually enabled in the game's settings. |
| runtime not found | You have not supplied the runtime. See [runtimes/README.md](../runtimes/README.md). |
| no tensor units | Your GPU cannot run this. Final. |
| needs locally converted weights | AMD path. Run the conversion tool first. |
| identified by device ID heuristic | Not an error. NVAPI and AGS were unavailable so the architecture name is a guess. Capability gating still applies. |

No overlay at all usually means the proxy DLL was not loaded. Confirm it sits
next to the game's executable rather than in a subdirectory, and that the game is
not launching a second executable from elsewhere, which launchers frequently do.

### Reporting a problem

Include the output of `nf_probe.ps1`, the overlay status line, the game and its
upscaler, and your `neuralforge.ini`.

Please do not file performance reports for RTX 20 or AMD. Those numbers are
documented and expected.
