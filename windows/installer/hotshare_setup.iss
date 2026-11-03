; HotShare Inno Setup Script
; Generates a clean Windows installer with desktop and Start Menu shortcuts,
; bundled VC++ runtime DLLs, and conditional VC++ Redistributable fallback.

#define MyAppName "HotShare"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "HotShare Team"
#define MyAppURL "https://github.com/hotshare/hotshare"
#define MyAppExeName "hotshare.exe"
#define MyAppSourceDir "..\..\build\windows\x64\runner\Release"

[Setup]
AppId={{D6E97A14-38B9-4C41-B892-F7B6D1A25B3E}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DisableProgramGroupPage=yes
OutputDir=..\..\build\installer
OutputBaseFilename=HotShare-Setup-x64
SetupIconFile=..\runner\resources\app_icon.ico
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
Name: "sendto"; Description: "Add to Windows 'Send to' menu"; GroupDescription: "Explorer Integration:"

[Files]
; Main application binaries and assets
Source: "{#MyAppSourceDir}\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyAppSourceDir}\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#MyAppSourceDir}\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs
; App-local Visual C++ runtime DLLs (allows immediate execution even on clean machines)
Source: "redist\vcruntime140.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "redist\vcruntime140_1.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "redist\msvcp140.dll"; DestDir: "{app}"; Flags: ignoreversion
; Fallback redistributable installer, extracted only when system runtime is missing
Source: "redist\vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall; Check: NeedsVCRedist

[Icons]
Name: "{autoprograms}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon
Name: "{userappdata}\Microsoft\Windows\SendTo\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Parameters: "--send"; Tasks: sendto

[Run]
Filename: "{tmp}\vc_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Installing Visual C++ runtime..."; Flags: waituntilterminated; Check: NeedsVCRedist
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[Code]
function NeedsVCRedist: Boolean;
var
  Installed: Cardinal;
begin
  Result := True;
  if RegQueryDWordValue(HKLM, 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64', 'Installed', Installed) then
    Result := (Installed <> 1);
end;
