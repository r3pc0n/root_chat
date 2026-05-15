#define AppName "rootchat"
#define AppVersion "1.0"
#define AppPublisher "r3pc0n"
#define AppURL "https://github.com/r3pc0n/root_chat"
#define AppExeName "rootchat.exe"

[Setup]
AppId={{B7A2D4E1-3F8C-4A5B-9D2E-1C6F8A0B3E7D}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=dist
OutputBaseFilename=rootchat-setup-v{#AppVersion}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ChangesEnvironment=yes
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "dist\{#AppExeName}"; DestDir: "{app}"; Flags: ignoreversion

[Registry]
; Add install dir to system PATH
Root: HKLM; Subkey: "SYSTEM\CurrentControlSet\Control\Session Manager\Environment"; \
    ValueType: expandsz; ValueName: "Path"; \
    ValueData: "{olddata};{app}"; \
    Check: NeedsAddPath('{app}')

[Code]
function NeedsAddPath(Param: string): boolean;
var
  OrigPath: string;
begin
  if not RegQueryStringValue(HKEY_LOCAL_MACHINE,
    'SYSTEM\CurrentControlSet\Control\Session Manager\Environment',
    'Path', OrigPath)
  then begin
    Result := True;
    exit;
  end;
  Result := Pos(';' + Param + ';', ';' + OrigPath + ';') = 0;
end;

[UninstallRegistry]
; Remove from PATH on uninstall
Root: HKLM; Subkey: "SYSTEM\CurrentControlSet\Control\Session Manager\Environment"; \
    ValueType: expandsz; ValueName: "Path"; \
    ValueData: "{reg:HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment,Path}";

[Icons]
Name: "{group}\rootchat"; Filename: "{app}\{#AppExeName}"; Comment: "rootchat CLI"

[Messages]
FinishedLabel=rootchat has been installed. Open a new terminal and run:%n%n  rootchat%n%nThe interactive setup wizard will guide you through connecting.
