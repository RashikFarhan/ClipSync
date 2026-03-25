; ══════════════════════════════════════════════════════════════════
;  ClipSync v0.1.0 — Inno Setup Installer Script
; ══════════════════════════════════════════════════════════════════

#define AppName        "ClipSync"
#ifndef AppVersion
#define AppVersion     "0.1.0"
#endif

#define AppPublisher   "Antigravity"
#define AppURL         "https://github.com/antigravity/clipsync"
#define AppExeName     "ClipSync.exe"
#define BuildDir       "..\build\windows\x64\runner\Release"

[Setup]
AppId={{A1B2C3D4-E5F6-7890-ABCD-EF1234567890}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}
AppUpdatesURL={#AppURL}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
AllowNoIcons=yes
OutputBaseFilename=ClipSync
SetupIconFile=..\windows\runner\resources\app_icon.ico
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
MinVersion=10.0.17763
; Enable restart after install — needed to flush any locked DLLs
RestartIfNeededByRun=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon";  Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "startupentry"; Description: "Launch ClipSync automatically on Windows startup (runs in system tray)"; GroupDescription: "Background Sync:"; Flags: checkedonce

[Files]
Source: "{#BuildDir}\{#AppExeName}";  DestDir: "{app}"; Flags: ignoreversion
Source: "{#BuildDir}\*.dll";          DestDir: "{app}"; Flags: ignoreversion recursesubdirs
Source: "{#BuildDir}\data\*";         DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\windows\runner\resources\app_icon.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#AppName}";            Filename: "{app}\{#AppExeName}"; IconFilename: "{app}\app_icon.ico"
Name: "{group}\Uninstall {#AppName}";  Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}";      Filename: "{app}\{#AppExeName}"; IconFilename: "{app}\app_icon.ico"; Tasks: desktopicon

[Registry]
; Startup registry entry — only if the startup task is selected
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "{#AppName}"; ValueData: """{app}\{#AppExeName}"" --autostart"; Flags: uninsdeletevalue; Tasks: startupentry

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(AppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; ── All user data folders — wiped on uninstall so reinstall is always clean ──

; 1. SQLite DB + keys (now in %LOCALAPPDATA%\com.antigravity.clipsync or \ClipSync)
Type: filesandordirs; Name: "{localappdata}\com.antigravity.clipsync"
Type: filesandordirs; Name: "{localappdata}\{#AppName}"

; 2. Flutter SharedPreferences / window state (%APPDATA%\ClipSync)
Type: filesandordirs; Name: "{userappdata}\{#AppName}"
Type: filesandordirs; Name: "{userappdata}\com.antigravity.clipsync"

; 3. Old Documents folder (previous versions stored DB here)
Type: filesandordirs; Name: "{userdocs}\{#AppName}"

; 4. Install directory itself
Type: filesandordirs; Name: "{app}"

[Code]
// ── Kill ALL running instances before uninstall ───────────────────────────────
// This prevents "file in use" errors that leave partial installs behind.
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ResultCode: Integer;
begin
  if CurUninstallStep = usUninstall then
  begin
    // Kill every ClipSync.exe process — /F = force, /IM = by image name
    Exec('taskkill.exe', '/F /IM {#AppExeName}', '', SW_HIDE,
         ewWaitUntilTerminated, ResultCode);
    // Also kill any flutter_tool or dart.exe that may hold DLLs
    Exec('taskkill.exe', '/F /IM dart.exe', '', SW_HIDE,
         ewWaitUntilTerminated, ResultCode);
    Sleep(800); // give OS time to release all file handles
  end;
end;

// ── Before install: kill any existing instance so DLLs can be replaced ───────
procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
begin
  if CurStep = ssInstall then
  begin
    Exec('taskkill.exe', '/F /IM {#AppExeName}', '', SW_HIDE,
         ewWaitUntilTerminated, ResultCode);
    Sleep(500);
  end;
end;
