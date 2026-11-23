; Instalador de exBel venta (Inno Setup 6).
; Se compila en GitHub Actions:
;   ISCC /DVersion=0.1.0.12 /DOrigen=...\Release /DIcono=...\app_icon.ico exbel-venta.iss

#ifndef Version
  #define Version "0.1.0"
#endif
#ifndef Origen
  #define Origen "..\build\windows\x64\runner\Release"
#endif
#ifndef Icono
  #define Icono "..\windows\runner\resources\app_icon.ico"
#endif

[Setup]
AppId={{6F1C2E7A-8B4D-4E1F-9A3C-EB5E1A0C7B21}
AppName=exBel venta
AppVersion={#Version}
AppVerName=exBel venta {#Version}
AppPublisher=exBel
DefaultDirName={autopf}\exBel venta
DefaultGroupName=exBel venta
DisableProgramGroupPage=yes
; Se instala sin pedir permisos de administrador.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputBaseFilename=exBel-venta-instalador
SetupIconFile={#Icono}
UninstallDisplayIcon={app}\exBelVenta.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes

[Languages]
Name: "es"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "escritorio"; Description: "Crear acceso directo en el escritorio"; GroupDescription: "Accesos directos:"

[Files]
Source: "{#Origen}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\exBel venta"; Filename: "{app}\exBelVenta.exe"
Name: "{group}\Desinstalar exBel venta"; Filename: "{uninstallexe}"
Name: "{autodesktop}\exBel venta"; Filename: "{app}\exBelVenta.exe"; Tasks: escritorio

[Run]
Filename: "{app}\exBelVenta.exe"; Description: "Abrir exBel venta"; Flags: nowait postinstall skipifsilent
