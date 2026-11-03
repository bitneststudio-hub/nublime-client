# windows/core —— 运行时核心（不入库）

这里的二进制不提交到仓库（各 20–37 MB）。用脚本从官方 release 拉取：

```powershell
powershell -ExecutionPolicy Bypass -File tools\windows\fetch_core.ps1
```

拉取后本目录应包含：

```
xray.exe        Xray-core v26.7.11 (windows-64)   —— 版本必须与服务器一致
wintun.dll      官方 zip 自带，必须与 xray.exe 同目录
geoip.dat       geosite.dat   —— 国内直连分流数据
LICENSE         LICENSE-Wintun —— 合规声明，随安装包分发
```

`build.ps1` 会把整个目录拷进 `build\windows\x64\runner\Release\core\`。
