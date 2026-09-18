# Delta Force × iCreate Recording Crash Investigation

[中文](README.zh-CN.md) | **English**

An **unofficial, evidence-driven** investigation into a recording-related crash affecting the Windows version of *Delta Force*, involving Tencent's iCreate "Zhouzhou Moment" (洲洲时刻) recorder and a D3D12/NVIDIA capture conflict.

This repository publishes the reusable parts of a real failure investigation: the crash chain, evidence grading, a safe read-only evidence collector, a mitigation procedure that keeps recording enabled, and vendor-side fix recommendations. It contains no game files, no Tencent components, no raw dumps, no raw logs, and no user-identifying information.

> The detailed documents under [`docs/`](docs) are currently written in Chinese only.

## Summary of findings

In the analyzed sample, the deepest chain that can be substantiated is:

1. The end of a match triggers `StopRecorder` / capture resource destruction;
2. In the same time window, the recording-success toast overlay uploads `record_success.png`;
3. Windows logs `nvlddmkm` Event ID 153 and produces a GPU WATCHDOG `0x141`;
4. The game then observes `DXGI_ERROR_DEVICE_REMOVED`, with removal reason `DXGI_ERROR_DEVICE_HUNG`;
5. In Tencent's `graphics-hook64.dll 1.8.0.0`, the D3D12 image upload path does not check object creation results, and dereferences a null command list / command queue at `+0x1AB42` or `+0x1AB89`;
6. The same path also performs an unbounded fence wait, so the user-visible symptom can be "freeze first, then straight back to the desktop".

What is certain: **not checking a failed result and then dereferencing a null COM pointer is a defect in the recording overlay component.** The available public samples are not sufficient to uniquely prove which command list, shared resource, or cross-queue synchronization point first caused the GPU timeout, so the upstream race should still be described as "most credible, but pending final confirmation via DRED / vendor symbols".

The full evidence boundary is documented in [`docs/root-cause.md`](docs/root-cause.md).

## Working around the issue without disabling Zhouzhou Moment

### User-side minimal variable

Keep:

- the Zhouzhou Moment recorder enabled;
- process capture;
- NVENC;
- all other game graphics and BIOS settings unchanged.

Turn off only:

- the NVIDIA App in-game overlay;
- NVIDIA game filters;
- any other overlay that injects into Present/D3D12.

Then run three repeat tests of "fully exit WeGame → cold-start the game → complete the first match → stay through the results screen". This separates "a defect in Tencent's hook itself" from "Tencent and NVIDIA overlay layers jointly triggering it". Window capture produced a black screen during this investigation, and switching the encoder does not fix the overlay upload path, so it is not a first-choice variable.

### Vendor-side lossless mitigation

The investigation confirmed that recording and the in-game toast overlay are controlled by separate configuration. Ask Tencent for:

```text
enableSDK=true
enableRecord=true
overlayEnable=false
```

The goal is to keep automatic recording, NVENC, audio, and clipping, while stopping the injection of recording-notification images into the game process. See [`docs/mitigation.md`](docs/mitigation.md) for details.

## Safe evidence collector

### Default run

```powershell
$env:DELTA_FORCE_ROOT = 'D:\Games\DeltaForce\DeltaForce'
.\tools\Collect-Evidence.ps1
```

You can also double-click `collect-evidence.bat`, or pass the path explicitly:

```powershell
.\tools\Collect-Evidence.ps1 -GameRoot 'D:\Games\DeltaForce\DeltaForce' -LookbackHours 168
```

Default behavior:

- read-only queries against system state, event logs, related processes, and dump metadata;
- output written only to `evidence\<timestamp>` inside the repository;
- computer name, user name, user profile path, and suspected long account IDs are redacted from text;
- **raw dumps are not copied, and raw logs are not copied.**

Explicitly add redacted log tails:

```powershell
.\tools\Collect-Evidence.ps1 -GameRoot 'D:\Games\DeltaForce\DeltaForce' -IncludeLogTails
```

Only use this when you are preparing a local WinDbg analysis:

```powershell
.\tools\Collect-Evidence.ps1 -GameRoot 'D:\Games\DeltaForce\DeltaForce' -IncludeDumps
```

Raw dumps may contain private data; do not upload them directly before filing an issue. See [`docs/evidence-guide.md`](docs/evidence-guide.md).

## Tests

Windows PowerShell 5.1 or PowerShell 7:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\run.ps1
```

The tests cover:

- crash-correlated logs are not missed by "most recent N files only" selection;
- recognition of the known `graphics-hook64` signature;
- unknown signatures are not misreported as a confirmed root cause;
- text privacy redaction;
- the repository contains no common tokens, phone numbers, long account IDs, real user profile paths, or raw evidence files.

## Repository layout

```text
.
├─ docs/                  Findings, mitigation, evidence guide, vendor fix recommendations
├─ src/                   Reusable PowerShell evidence functions
├─ tools/                 Read-only evidence collection entry point
├─ tests/                 Behavior and publication-safety tests with no third-party dependencies
└─ collect-evidence.bat   Windows shortcut entry point
```

## Evidence-first principles

- The point where an API reports an error is not necessarily the upstream root cause; `ID3D12Resource::Map` is only where the device was observed to be already hung.
- Stress tests do not cover "injected capture + shared textures + encoding + stop/destroy + same-frame overlay upload".
- Correlation is not written as unique causation; the boundary is stated explicitly when DRED, vendor PDBs, or a failing HRESULT are unavailable.
- Each A/B round changes exactly one variable, and records the cold start, match count, results-screen timing, and generated files.

## Trademarks and affiliation

*Delta Force*, WeGame, "Zhouzhou Moment" (洲洲时刻), NVIDIA, OBS, and other names belong to their respective owners. This project is not affiliated with, or endorsed by, Tencent, NVIDIA, or the OBS Project.

## License

[MIT](LICENSE)
