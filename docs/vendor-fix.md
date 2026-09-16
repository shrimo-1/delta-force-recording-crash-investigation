# 厂商修复方向与验收标准

## 立即修复：失败必须安全降级

D3D12 浮层上传路径应验证以下每一步的 HRESULT、输出指针或句柄：

- `CreateFence`；
- `CreateEventW`；
- `CreateCommandQueue`；
- `CreateCommandAllocator`；
- `CreateCommandList`；
- `CommandList::Close`；
- `CommandQueue::Signal`；
- `Fence::SetEventOnCompletion`；
- fence wait 返回值。

任一步失败时：

1. 记录 HRESULT 和 `GetDeviceRemovedReason`；
2. 释放已成功创建的对象；
3. 跳过本次图片，或降级为无图提示；
4. 不得影响游戏主进程；
5. 不得无限等待。

示意：

```cpp
ComPtr<ID3D12CommandQueue> queue;
HRESULT hr = device->CreateCommandQueue(&desc, IID_PPV_ARGS(&queue));
if (FAILED(hr) || !queue) {
    LogGpuFailure("CreateCommandQueue", hr,
                  device->GetDeviceRemovedReason());
    return false;
}

DWORD wait = WaitForSingleObject(eventHandle, 1000);
if (wait != WAIT_OBJECT_0) {
    LogGpuFailure("overlay upload wait", HRESULT_FROM_WIN32(
        wait == WAIT_TIMEOUT ? ERROR_TIMEOUT : GetLastError()),
        device->GetDeviceRemovedReason());
    return false;
}
```

## 结构性修复

仅加空指针判断会阻止二次崩溃，但不能消除上游 GPU 超时。还应：

1. 不为每条浮层通知临时创建 DIRECT queue；
2. 在 Overlay 初始化期建立并复用受控上传上下文；
3. 预加载固定图片，避免与 `StopRecorder` 同帧初始化 GPU 资源；
4. 停止捕获时等待 D3D11On12、共享纹理和相关 queue fence 完成；
5. 获得注入端 teardown-complete 后再销毁宿主资源；
6. 销毁完成后再发送录制成功提示；
7. 对 device removed/reset/hung 路径做明确降级。

## 失败注入测试

分别让每个创建、Close、Signal 和 SetEventOnCompletion 调用失败并清空输出。每项必须满足：

- 游戏不崩溃；
- 游戏线程不发生超过一秒的等待；
- 录制文件完成封装或给出明确错误；
- 日志保留 HRESULT 与设备移除原因；
- 浮层跳过或无图降级。

## 实机矩阵

- D3D12 多 DIRECT/COPY queue；
- NVIDIA Overlay/Filter 开与关；
- NVENC 与软编；
- 进程捕获与窗口捕获；
- 全屏与无边框；
- 冷启动第一局与连续多局；
- 结算同时切换前后台；
- 人工触发 device removed。

每个组合重复至少 20 次停止流程，不得出现：

- `nvlddmkm 153`；
- LiveKernelEvent `0x141`；
- `DXGI_ERROR_DEVICE_HUNG`；
- `graphics-hook64+0x1AB42/+0x1AB89`；
- 超过一秒的无限或无界等待。
