; 朝闻 —— Inno Setup 安装脚本
;
; 编译：pwsh scripts/build_installer_inno.ps1
;
; 升级逻辑：沿用同一个 AppId。安装程序启动时读取卸载注册表项，
;   · 已安装 → 显示「升级」，跳过安装方式选择，沿用上次的安装位置，只替换程序文件；
;   · 未安装 → 正常安装流程，可选择安装位置与安装范围。
; 用户数据（下载目录、%LOCALAPPDATA%\rmrb-reader）在任何情况下都不会被触碰。

#define AppName "朝闻"
#define AppVersion "0.2.0"
#define AppExe "rmrb_reader.exe"
#define AppId "8F3C2E87-6A1B-4B7E-9C2D-5A1E3B7D9C41"
#define ReleaseDir AddBackslash(SourcePath) + "..\app\build\windows\x64\runner\Release"
#define IconFile AddBackslash(SourcePath) + "..\app\windows\runner\resources\app_icon.ico"
#define OutDir AddBackslash(SourcePath) + "..\dist"

[Setup]
AppId={{{#AppId}}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=个人项目
AppPublisherURL=https://github.com/mysilicons/chaowen
AppSupportURL=https://github.com/mysilicons/chaowen/issues
AppUpdatesURL=https://github.com/mysilicons/chaowen/releases
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
DisableDirPage=no
UsePreviousAppDir=yes
DirExistsWarning=auto
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
CloseApplications=yes
RestartApplications=no
OutputDir={#OutDir}
OutputBaseFilename=Chaowen-{#AppVersion}-setup
SetupIconFile={#IconFile}
UninstallDisplayIcon={app}\{#AppExe}
VersionInfoVersion=0.2.0.0
VersionInfoProductName={#AppName}
VersionInfoProductVersion={#AppVersion}
VersionInfoDescription={#AppName} 安装程序
VersionInfoCompany=个人项目
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"

[Messages]
WelcomeLabel1=欢迎安装 [name]
WelcomeLabel2=即将把 [name/ver] 安装到你的电脑。%n%n安装到当前用户目录，无需管理员权限。%n%n继续前请关闭正在运行的朝闻。
FinishedHeadingLabel=安装完成
FinishedLabel=朝闻已安装完成，可从桌面或开始菜单启动。%n%n已下载的报纸保存在「文档\人民日报」，卸载不会删除。
ButtonInstall=安装(&I)
ButtonNext=下一步(&N)
ButtonBack=上一步(&B)
ButtonCancel=取消(&C)
ButtonFinish=完成(&F)
ButtonBrowse=浏览(&B)...
SelectDirLabel3=安装程序将把 [name] 安装到以下文件夹。
SelectDirDesc=选择安装位置
SelectTasksLabel2=请选择安装程序要执行的附加任务，然后点击「下一步」。
ReadyLabel1=安装程序已准备好，点击「安装」开始。
ReadyLabel2b=点击「安装」开始安装 [name]。
InstallingLabel=正在安装 [name]，请稍候...
ClickNext=点击「下一步」继续，或点击「取消」退出安装程序。
PrivilegesRequiredOverrideTitle=选择安装方式
PrivilegesRequiredOverrideInstruction=请选择 [name] 的安装方式。
PrivilegesRequiredOverrideText1=仅为当前用户安装，不需要管理员权限。
PrivilegesRequiredOverrideText2=为所有用户安装，需要管理员权限。
PrivilegesRequiredOverrideAllUsers=为所有用户安装(&A)
PrivilegesRequiredOverrideCurrentUser=仅为当前用户安装(&M)
PrivilegesRequiredOverrideAllUsersRecommended=为所有用户安装（推荐）(&A)
PrivilegesRequiredOverrideCurrentUserRecommended=仅为当前用户安装（推荐）(&M)

[CustomMessages]
CreateDesktopIcon=创建桌面快捷方式(&D)
LaunchProgram=立即运行朝闻(&L)

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "附加任务:"; Flags: checkedonce

[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[InstallDelete]
; 升级时先清掉上一版的程序目录，避免 PyInstaller / Flutter 的旧文件残留。
; 这两个目录只包含程序文件，用户数据不在这里。
Type: filesandordirs; Name: "{app}\data"
Type: filesandordirs; Name: "{app}\engine"

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; 只清安装目录里的程序文件，不碰下载目录与用户缓存
Type: filesandordirs; Name: "{app}\data"
Type: filesandordirs; Name: "{app}\engine"

[Code]
var
  PreviousVersion: String;
  IsUpdate: Boolean;

function UninstallKey(): String;
begin
  Result := 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{' +
    '{#AppId}' + '}_is1';
end;

function InitializeSetup(): Boolean;
var
  Value: String;
begin
  PreviousVersion := '';
  if RegQueryStringValue(HKCU, UninstallKey(), 'DisplayVersion', Value) then
    PreviousVersion := Value
  else if RegQueryStringValue(HKLM, UninstallKey(), 'DisplayVersion', Value) then
    PreviousVersion := Value;
  IsUpdate := PreviousVersion <> '';
  if IsUpdate then
    Log('检测到已安装版本 ' + PreviousVersion + '，按升级处理')
  else
    Log('未检测到已安装版本，按全新安装处理');
  Result := True;
end;

procedure InitializeWizard();
begin
  if IsUpdate then
  begin
    WizardForm.Caption := '升级 {#AppName}';
    WizardForm.WelcomeLabel1.Caption := '欢迎升级 {#AppName}';
    WizardForm.WelcomeLabel2.Caption :=
      '检测到已安装 {#AppName} ' + PreviousVersion + '，将升级到 {#AppVersion}。' + #13#10#13#10 +
      '安装位置、下载目录和已经下载的报纸都会保留。' + #13#10#13#10 +
      '继续前请关闭正在运行的朝闻。';
  end;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if IsUpdate and (CurPageID = wpFinished) then
  begin
    WizardForm.FinishedHeadingLabel.Caption := '升级完成';
    WizardForm.FinishedLabel.Caption :=
      '{#AppName} 已升级到 {#AppVersion}，可从桌面或开始菜单启动。' + #13#10#13#10 +
      '已下载的报纸保存在「文档\人民日报」，卸载不会删除。';
  end;
end;
