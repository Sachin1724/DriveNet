[Setup]
AppId={{E041DF81-80AC-4A42-B83C-11EAAE0FFCD9}
AppName=Drive Net Client
AppVersion=1.0.0
AppPublisher=Sachin1724
AppPublisherURL=https://github.com/Sachin1724/DriveNet
AppSupportURL=https://github.com/Sachin1724/DriveNet
AppUpdatesURL=https://github.com/Sachin1724/DriveNet
DefaultDirName={autopf}\Drive Net Client
DisableProgramGroupPage=yes
PrivilegesRequired=admin
OutputDir=build\setup
OutputBaseFilename=DriveNet_Setup_v1.0.0
SetupIconFile=windows\runner\resources\app_icon.ico
Compression=lzma
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "build\windows\x64\runner\Release\windows_agent_ui.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Drive Net Client"; Filename: "{app}\windows_agent_ui.exe"; IconFilename: "{app}\windows_agent_ui.exe"
Name: "{autodesktop}\Drive Net Client"; Filename: "{app}\windows_agent_ui.exe"; IconFilename: "{app}\windows_agent_ui.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\windows_agent_ui.exe"; Description: "{cm:LaunchProgram,Drive Net Client}"; Flags: nowait postinstall skipifsilent
