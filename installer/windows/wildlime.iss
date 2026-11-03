; WildLime VPN - Windows installer (InnoSetup 6)
; build:  ISCC.exe /DVersion=4.2.0 wildlime.iss
; 说明：安装包携带 xray.exe + wintun.dll（runtime core），不携带任何节点凭据。

#ifndef Version
  #define Version "0.0.0"
#endif
#define AppName "WildLime VPN"
#define AppExe  "wildlime.exe"
#define Source  "..\..\app\build\windows\x64\runner\Release"

[Setup]
AppId={{B7C1B0B4-2E1B-4E0B-9E52-WILDLIME00001}
AppName={#AppName}
AppVersion={#Version}
AppPublisher=BitNest Studio
DefaultDirName={autopf}\WildLime
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=admin
OutputDir=..\..\app\dist
OutputBaseFilename=WildLime-Setup-v{#Version}-win64
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
UninstallDisplayIcon={app}\{#AppExe}
; 未签名发布：不启用 SignedUninstaller
SignedUninstaller=no

[Languages]
Name: "en";   MessagesFile: "compiler:Default.isl"
Name: "zhcn"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#Source}\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; 卸载时先杀掉核心进程，避免文件占用；路由/网卡随进程退出由 xray 自己清理
Filename: "{sys}\taskkill.exe"; Parameters: "/IM xray.exe /F"; Flags: runhidden; RunOnceId: "KillXray"

[Code]
function InitializeSetup(): Boolean;
begin
  Result := True;
end;
