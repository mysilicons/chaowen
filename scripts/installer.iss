; 朝闻 · 人民日报阅报器 —— Inno Setup 安装脚本
; 编译：ISCC.exe chaowen.iss

#define AppName "朝闻"
#define AppVersion "0.1.0"
#define AppExe "rmrb_reader.exe"
#define ReleaseDir "D:\YTH\code\rmrb\app\build\windows\x64\runner\Release"
#define IconFile "D:\YTH\code\rmrb\app\windows\runner\resources\app_icon.ico"

[Setup]
AppId={{8F3C2E87-6A1B-4B7E-9C2D-5A1E3B7D9C41}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=个人项目
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=D:\YTH\code\rmrb\dist
OutputBaseFilename=朝闻-{#AppVersion}-setup
SetupIconFile={#IconFile}
UninstallDisplayIcon={app}\{#AppExe}
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

[CustomMessages]
CreateDesktopIcon=创建桌面快捷方式(&D)
LaunchProgram=立即运行朝闻(&L)

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "附加任务:"; Flags: checkedonce

[Files]
Source: "{#ReleaseDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; 只清安装目录里的程序文件，不碰下载目录与用户缓存
Type: filesandordirs; Name: "{app}\data"



