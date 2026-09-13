# Security

## Reporting

Report vulnerabilities through GitHub's private advisory form on this
repository, under Security, then Report a vulnerability. Please do not open a
public issue for anything that could be abused before it is fixed.

Expect an acknowledgement within a few days. I am one person, so complicated
fixes may take longer, and I will tell you where things stand rather than going
quiet.

## What counts

NeuralForge loads a DLL into a game process. The things worth reporting are the
ones that turn that into a problem for a user who did nothing wrong:

- A path where the anti-cheat gate can be bypassed without the user explicitly
  disabling it.
- A way to get the installer to write outside the selected game directory, or to
  destroy a backup it promised to keep.
- Code execution through a config file, a denylist entry, a manifest, or any
  other input the user did not author.
- A release archive that ships a vendor binary. CI is supposed to make this
  impossible, so a way around that check is a real finding.
- Anything that causes NeuralForge to load in a title it should have refused.

## What does not count

The project modifies a game's render pipeline by design. That it injects a DLL,
proxies an export, or hooks an upscaler call is the documented purpose, not a
vulnerability.

Performance on RTX 20 and AMD is documented and expected.

Reports asking where to obtain the neural rendering runtime will be closed.

## Design commitments

These are properties the project intends to keep, so a change that breaks one is
a bug worth reporting even without a working exploit.

**The safety gate refuses rather than warns.** The installer declines to write
to a game directory containing anti-cheat, and the module declines to initialise
when an anti-cheat module is resident in the process. Neither asks the user to
confirm past the refusal.

**Nothing evades detection.** No part of this project hides from anti-cheat,
detects whether it is being observed, or behaves differently when it is. This
will not change, and pull requests adding it are declined.

**Uninstall is complete.** Nothing is patched in place and nothing is written to
game memory. Every file the installer would overwrite is backed up with a
manifest first, so removal restores the directory exactly.

**No vendor binaries are redistributed.** The runtime, extracted weights and
converted weight blobs never enter this repository or a release archive. CI
enforces it on every push and blocks publication.

**Inferred vendor identifiers fail closed.** Names carrying an `_Unverified`
suffix were inferred rather than read from an SDK header. A wrong value must
produce a clear error, never a silent misbehaviour.

## Scope

This policy covers the code in this repository. It does not cover the
proprietary runtime users supply themselves, which is the vendor's to secure. If
you obtained that file from anywhere other than software you licence, verify its
Authenticode signature with `tools\nf_probe.ps1 -CheckRuntime` before going
further, and treat a failed signature as a compromised machine rather than a
NeuralForge bug.
