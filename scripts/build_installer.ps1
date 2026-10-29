# 一键生成安装包：构造 payload → 压缩 → csc 编译自解压安装器
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$dist = Join-Path $root "dist"
$release = Join-Path $root "app\build\windows\x64\runner\Release"
$csc = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
$ico = Join-Path $root "app\windows\runner\resources\app_icon.ico"
$out = Join-Path $dist "朝闻-0.1.0-setup.exe"

if (-not (Test-Path (Join-Path $release "rmrb_reader.exe"))) {
    throw "请先 flutter build windows --release（含 engine 子目录）"
}

$payload = Join-Path $dist "payload"
if (Test-Path $payload) { Remove-Item $payload -Recurse -Force }
New-Item -ItemType Directory -Force $payload | Out-Null
Copy-Item -Recurse (Join-Path $release "*") $payload
Copy-Item (Join-Path $PSScriptRoot "uninstall.cmd") $payload

$zip = Join-Path $dist "payload.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $payload "*") -DestinationPath $zip -CompressionLevel Optimal

& $csc /nologo /target:winexe /platform:anycpu /optimize+ /out:$out /win32icon:$ico `
    /r:System.dll /r:System.Drawing.dll /r:System.Windows.Forms.dll `
    /r:System.IO.Compression.dll /r:System.IO.Compression.FileSystem.dll `
    /resource:$zip,payload.zip (Join-Path $PSScriptRoot "installer.cs")

Remove-Item $payload -Recurse -Force
Remove-Item $zip -Force
Write-Host ("安装包：{0}（{1:N1} MB）" -f $out, ((Get-Item $out).Length / 1MB)) -ForegroundColor Green
