# Runtimes

**This directory is empty in every release and will stay that way.**

Put your own `nvngx_dlssnr.dll` here, copied from software you already licence.
NeuralForge reads it and never modifies it.

```powershell
.\tools\nf_probe.ps1 -CheckRuntime
```

That reports the version, size and Authenticode signature. If the signature does
not validate, do not use the file. A 158 MB DLL from an unknown source that loads
into your game process is exactly the shape of a problem you do not want, and
"someone on a forum said it was the good version" is not a signature check.

Do not download it from mirrors, reuploads or Discord attachments. There is no
version of that which is safe.

## Why it is not bundled

The runtime is proprietary software licensed to end users as part of a driver or
a game installation. Redistributing it is not ours to do, and a project that does
gets taken down, after which nobody has the tool. CI blocks any release archive
containing a vendor binary, so this is enforced rather than promised.

The practical consequence is that NeuralForge is useless to someone without
legitimate access to the runtime. That is the correct outcome.

## AMD needs one more step

The portable backends cannot execute a runtime built for another vendor's
architecture. Convert the weights locally, from your own copy:

```powershell
.\tools\nf_convert.ps1 -Input runtimes\nvngx_dlssnr.dll -Output runtimes\weights.nfw
```

The result is derived from licensed material and carries the same terms. Do not
share it.

If you cannot obtain the runtime, NeuralForge will not work for you. Please do
not open issues asking where to find it, and please do not answer those issues.
