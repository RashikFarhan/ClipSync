; ══════════════════════════════════════════════════════════════════
;  ClipSync Alpha v0.4 — Inno Setup Installer Script
;  Generates:  ClipSync_Setup_v0.4.exe
;  Run with:   Inno Setup Compiler (https://jrsoftware.org/isdl.php)
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
; Output location is set via ISCC CLI (/O)
OutputBaseFilename=ClipSync
; Use the app icon for the installer wizard
SetupIconFile=..\windows\runner\resources\app_icon.ico
; Compress the payload
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
; Run as admin so it installs to Program Files
PrivilegesRequired=admin
; Minimum Windows version: Windows 10
MinVersion=10.0.17763

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon";    Description: "{cm:CreateDesktopIcon}";    GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "startupentry";   Description: "Launch ClipSync automatically on Windows startup (runs in system tray)"; GroupDescription: "Background Sync:"; Flags: checkedonce

[Files]
; Main executable
Source: "{#BuildDir}\{#AppExeName}";          DestDir: "{app}"; Flags: ignoreversion
; Flutter engine + plugin DLLs
Source: "{#BuildDir}\*.dll";                  DestDir: "{app}"; Flags: ignoreversion recursesubdirs
; App data folder (assets, fonts, ICU)
Source: "{#BuildDir}\data\*";                 DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs
; Visual C++ redistributables (bundled so no separate VC++ install needed)
Source: "..\windows\runner\resources\app_icon.ico"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
; Start Menu shortcut
Name: "{group}\{#AppName}";                        Filename: "{app}\{#AppExeName}"; IconFilename: "{app}\app_icon.ico"
Name: "{group}\Uninstall {#AppName}";              Filename: "{uninstallexe}"
; Desktop shortcut (only if task selected)
Name: "{autodesktop}\{#AppName}";                  Filename: "{app}\{#AppExeName}"; IconFilename: "{app}\app_icon.ico"; Tasks: desktopicon

[Registry]
; Add to Windows "Apps & Features" uninstall list (done automatically by Inno)
; Optional: Run on startup (only if task selected)
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "{#AppName}"; ValueData: """{app}\{#AppExeName}"" --autostart"; Flags: uninsdeletevalue; Tasks: startupentry

[Run]
; Launch app after install finishes
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(AppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Remove AppData roaming folder (SharedPreferences / Flutter window state)
Type: filesandordirs; Name: "{userappdata}\{#AppName}"
; Remove Documents\ClipSync folder (SQLite database — clipsync.db)
Type: filesandordirs; Name: "{userdocs}\{#AppName}"
; Remove any leftover files in app install dir
Type: filesandordirs; Name: "{app}"

[Code]
// Kill the running ClipSync process before uninstalling so no "file in use" errors occur.
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ResultCode: Integer;
begin
  if CurUninstallStep = usUninstall then
  begin
    Exec('taskkill.exe', '/F /IM {#AppExeName}', '', SW_HIDE,
         ewWaitUntilTerminated, ResultCode);
    Sleep(500); // give OS time to release file handles
  end;
end;
