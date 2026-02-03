; =============================================================================
; MimikaStudio - Inno Setup Installer Script
; =============================================================================
; Produces MimikaStudio_Setup.exe
;
; Build with:
;   "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" mimikastudio.iss
; =============================================================================

#define MyAppName "MimikaStudio"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "MimikaStudio"
#define MyAppURL "https://github.com/mimikastudio"
#define MyAppExeName "MimikaStudio.exe"

; Paths relative to the .iss file location
#define DistDir "..\dist\MimikaStudio"
#define WebDir "..\dist\MimikaStudio\web"

[Setup]
AppId={{E4A7F2B1-3C5D-4E6F-8A9B-0C1D2E3F4567}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={localappdata}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
OutputDir=..\Output
OutputBaseFilename=MimikaStudio_Setup
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; PyInstaller output (backend + all dependencies)
Source: "{#DistDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

; Flutter web build (if present)
Source: "{#WebDir}\*"; DestDir: "{app}\web"; Flags: ignoreversion recursesubdirs createallsubdirs; Check: WebDirExists

; Include CUDA runtime DLLs if they exist alongside the build
Source: "{#DistDir}\*.dll"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}\outputs"
Type: filesandordirs; Name: "{app}\data\user_voices"
Type: filesandordirs; Name: "{app}\__pycache__"

[Code]
function WebDirExists(): Boolean;
begin
  Result := DirExists(ExpandConstant('{#WebDir}'));
end;
