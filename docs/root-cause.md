# 根因与证据边界

## 现象

- 多发生于对局结束、停止录制或进入结算时；
- 游戏可能短暂冻结后直接消失，回到桌面；
- 关闭洲洲时刻后，在观察期内不再复现；
- CPU、GPU、内存压力测试未复现异常；
- 窗口捕获可能得到全黑视频，且不能绕过录制成功浮层。

## 已证实事实

### 1. 游戏看到的是已经发生的设备挂起

游戏 RHIThread 的 `ID3D12Resource::Map` 返回 `DXGI_ERROR_DEVICE_REMOVED`，`GetDeviceRemovedReason` 为 `DXGI_ERROR_DEVICE_HUNG`。`Map` 是发现设备已挂起的位置，而不是最早让 GPU 停止推进的调用。

### 2. Windows 检测到真实 GPU 引擎超时

故障时间附近存在：

- `nvlddmkm` Event ID 153；
- `GPUID: 100`；
- LiveKernelEvent/WATCHDOG `0x141`；
- 内核调度栈进入 `dxgmms2!VidSchiCheckHwProgress`、`VidSchiResetEngines` 与 `VidSchiResetHwEngine`。

因此不能把驱动事件简单解释为“游戏用户态崩溃后的伴随噪声”。

### 3. 腾讯浮层上传存在确定的错误处理缺陷

多个 CrashSight DMP 命中 `graphics-hook64.dll 1.8.0.0`：

- `+0x1AB42`：空 `ID3D12GraphicsCommandList*`；
- `+0x1AB89`：空 `ID3D12CommandQueue*`；
- 异常代码：`0xC0000005`。

反汇编显示，图片上传函数在 `CreateFence`、`CreateCommandQueue`、`CreateCommandAllocator`、`CreateCommandList` 等调用后继续使用输出指针，没有先验证 HRESULT 与指针。函数还会对 fence event 执行无限等待。由此可独立确认：无论上游为什么失败，这段代码都不应让提示浮层拖死或终止游戏进程。

### 4. 停止录制、浮层上传与 TDR 位于同一故障窗口

典型顺序为：

```text
StopRecorder
  -> DestroySources / capture stopped
  -> window=3 / record_success.png
  -> nvlddmkm 153
  -> WATCHDOG 0x141
  -> graphics-hook64 null dereference or game DXGI device hung
```

## 最可信的上游解释

腾讯旧版 D3D12/D3D11On12 注入捕获在停止时释放 wrapped backbuffer、共享纹理或相关对象；与此同时，录制成功浮层又建立 D3D12 上传工作。在多 DIRECT queue 和其他覆盖层并存时，资源生命周期或跨队列同步竞态最能统一解释：

- 为什么问题集中在停止录制/结算；
- 为什么先冻结后退出；
- 为什么出现 GPU `0x141`；
- 为什么随后对象创建失败并得到空 COM 指针；
- 为什么普通压力测试无法复现。

但在没有 DRED breadcrumbs/page-fault、失败 HRESULT、厂商 PDB 与注入端完整 fence 时序的情况下，不能声称已经唯一确定了第一个失效的 command list 或资源。

## 促进因素，不是已证明的唯一根因

已检查的崩溃进程同时加载过腾讯 `graphics-hook64` 与 NVIDIA `nvspcap64` / `NvCamera64`。第二套覆盖层可能改变 Present 时序、显存占用或资源回收窗口，因此“保留腾讯录制，只关闭 NVIDIA 覆盖层/滤镜”是高价值单变量测试；模块共存本身不等于 NVIDIA 单独致因。

## 已排除或降权

- **NVENC 过载**：故障发生在 D3D12 浮层上传路径，而非编码器调用点。
- **坏 PNG**：同一固定资源在大量成功场景中可正常显示。
- **CPU/GPU/内存一般性不稳定**：压力测试通过，且真实故障负载包含压力测试没有覆盖的注入与销毁路径。
- **单纯画质设置**：画质会改变时序和显存压力，但不能解释稳定的 `graphics-hook64` 空指针签名。
- **窗口捕获即修复**：实测可能黑屏，并且录制成功浮层仍可继续注入。

## 如何进一步证实

厂商复现版应启用：

- DRED automatic breadcrumbs；
- DRED page-fault；
- 每个 D3D12 创建/Close/Signal/SetEventOnCompletion 的 HRESULT；
- `ID3D12Device::GetDeviceRemovedReason`；
- 停止捕获、共享资源引用清零、queue fence 完成与浮层通知的统一时间戳。

## 官方技术参考

- [Microsoft: Use DRED to diagnose GPU faults](https://learn.microsoft.com/en-us/windows/win32/direct3d12/use-dred)
- [Microsoft: Handle device removed scenarios](https://learn.microsoft.com/en-us/windows/uwp/gaming/handling-device-lost-scenarios)
- [Microsoft: WDDM timeout detection and recovery](https://learn.microsoft.com/en-us/windows-hardware/drivers/display/timeout-detection-and-recovery)
