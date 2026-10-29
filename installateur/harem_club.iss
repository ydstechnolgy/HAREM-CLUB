; =====================================================================
; HAREM CLUB · Programme d'installation Windows (Inno Setup)
; Fabriqué automatiquement par GitHub (.github/workflows/livraison.yml).
; =====================================================================
#define Version GetEnv("HAREM_VERSION")
#if Version == ""
  #define Version "1.0.0"
#endif

[Setup]
AppId={{4D2A9B71-3C5E-4F80-A6D2-7E1B9C3F5A24}
AppName=Harem Club
AppVersion={#Version}
AppVerName=Harem Club {#Version}
AppPublisher=YDS Tech
DefaultDirName={localappdata}\Programs\Harem Club
DefaultGroupName=Harem Club
DisableProgramGroupPage=yes
; Installation pour l'utilisateur : pas besoin d'être administrateur
PrivilegesRequired=lowest
OutputDir=..\livraison
OutputBaseFilename=Harem-Club-Installation
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\harem_club.exe
UninstallDisplayName=Harem Club
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Ferme le logiciel s'il est ouvert pendant une mise à jour
CloseApplications=yes

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "bureau"; Description: "Créer un raccourci sur le Bureau"; GroupDescription: "Raccourcis :"

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Harem Club"; Filename: "{app}\harem_club.exe"
Name: "{autodesktop}\Harem Club"; Filename: "{app}\harem_club.exe"; Tasks: bureau

[Run]
Filename: "{app}\harem_club.exe"; Description: "Ouvrir Harem Club maintenant"; Flags: nowait postinstall skipifsilent
