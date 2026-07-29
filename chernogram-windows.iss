#define MyAppName "Чернограм"
#define MyAppVersion "0.21.0"
#define MyAppPublisher "Chernogram"
#define MyAppExeName "chernogram.exe"

[Setup]
AppId={{B6C33A77-38D4-4CA0-BE3A-B0C431E40F16}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\Programs\Chernogram
DefaultGroupName=Чернограм
DisableProgramGroupPage=yes
DisableDirPage=yes
OutputDir=.
OutputBaseFilename=Chernogram-Windows-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
SetupIconFile=windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Files]
Source: "windows-package\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Чернограм"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{autodesktop}\Чернограм"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"

[Run]
Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Description: "Запустить Чернограм"; Flags: nowait runascurrentuser
