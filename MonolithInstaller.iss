; Monolith v1 runtime installer template (Inno Setup 6)
; This script installs an isolated runtime under %LOCALAPPDATA%\Monolith
; and never depends on system Python.

#define MyAppName "Monolith"
#ifndef MonolithVersion
  #define MonolithVersion "1.0.0"
#endif

[Setup]
AppId={{7AB0D1E0-A2EA-4BC4-9E43-13F3A7E5F7A0}
AppName={#MyAppName}
AppVersion={#MonolithVersion}
AppPublisher=Monolith
DefaultDirName={localappdata}\Monolith\app
DefaultGroupName=Monolith
DisableDirPage=yes
DisableProgramGroupPage=yes
OutputBaseFilename=MonolithInstaller_{#MonolithVersion}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
SetupLogging=yes
UninstallDisplayIcon={localappdata}\Monolith\app\MonolithLauncher.bat

[Dirs]
Name: "{localappdata}\Monolith\app"; Flags: uninsalwaysuninstall
Name: "{localappdata}\Monolith\runtime"; Flags: uninsalwaysuninstall
Name: "{localappdata}\Monolith\runtime\python"; Flags: uninsalwaysuninstall
Name: "{localappdata}\Monolith\install"; Flags: uninsalwaysuninstall
Name: "{localappdata}\Monolith\models"; Flags: uninsneveruninstall
Name: "{localappdata}\Monolith\data"; Flags: uninsneveruninstall

[Files]
; Bundled Python runtime payload (must include python.exe and pip or ensurepip).
Source: "payload\python\*"; DestDir: "{localappdata}\Monolith\runtime\python"; Flags: recursesubdirs ignoreversion

; Monolith app payload (UI/launcher/runtime assets, no ML models).
Source: "payload\app\*"; DestDir: "{localappdata}\Monolith\app"; Flags: recursesubdirs ignoreversion

; Installer helper scripts.
Source: "scripts\detect_gpu.bat"; DestDir: "{tmp}"; Flags: deleteafterinstall
Source: "scripts\install_env.bat"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Run]
; Step 1: detect hardware and write gpu_mode.txt to install directory.
Filename: "{tmp}\detect_gpu.bat"; Flags: runhidden waituntilterminated; StatusMsg: "Detecting hardware capabilities..."

; Step 2: install pip dependencies into isolated runtime.
Filename: "{tmp}\install_env.bat"; Flags: runhidden waituntilterminated; StatusMsg: "Installing Monolith runtime dependencies..."

[Icons]
Name: "{group}\Monolith"; Filename: "{localappdata}\Monolith\app\MonolithLauncher.bat"
Name: "{autodesktop}\Monolith"; Filename: "{localappdata}\Monolith\app\MonolithLauncher.bat"; Tasks: desktopicon

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional icons:"; Flags: unchecked

[Code]
procedure WriteInstallTrace(const Msg: String);
var
  LogPath: String;
begin
  LogPath := ExpandConstant('{localappdata}\Monolith\install\installer.log');
  SaveStringToFile(LogPath, Msg + #13#10, True);
end;

function InitializeSetup(): Boolean;
begin
  Result := True;
  ForceDirectories(ExpandConstant('{localappdata}\Monolith\install'));
  WriteInstallTrace('[SETUP] Monolith installer start');
  WriteInstallTrace('[SETUP] Version: {#MonolithVersion}');
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    WriteInstallTrace('[SETUP] Post-install completed');
  end;
end;

procedure DeinitializeSetup();
begin
  WriteInstallTrace('[SETUP] Installer exit');
end;
