# Windows 安装包

```powershell
# 1) 拉运行时核心（xray.exe + wintun.dll + geo 数据）
powershell -ExecutionPolicy Bypass -File tools\windows\fetch_core.ps1

# 2) 构建 + 打包
powershell -ExecutionPolicy Bypass -File tools\windows\build.ps1

# 3) 出安装包（ISCC 在 Inno Setup 6 安装目录）
& "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" /DVersion=4.2.0 installer\windows\wildlime.iss
# 产物：app\dist\WildLime-Setup-v4.2.0-win64.exe
```

未签名发布（Bowen 决策）：用户首次运行需 `更多信息 → 仍要运行`；
Win11 Smart App Control enforcement 设备会被硬拦，出现此类工单即采购 OV 证书。
