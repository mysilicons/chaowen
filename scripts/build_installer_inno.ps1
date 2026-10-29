# 用 Inno Setup 编译安装包
# 依赖：npm 包 innosetup-compiler 自带的 ISCC.exe（无需单独安装 Inno Setup）
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$dist = Join-Path $root "dist"
$bin = Join-Path $dist "iscc-tool\node_modules\innosetup-compiler\bin\ISCC.exe"

if (-not (Test-Path $bin)) {
    Write-Host "首次使用，正在通过 npm 获取 ISCC…"
    New-Item -ItemType Directory -Force (Join-Path $dist "iscc-tool") | Out-Null
    Push-Location (Join-Path $dist "iscc-tool")
    '{"name":"iscc-tool","private":true}' | Set-Content package.json -Encoding UTF8
    npm install innosetup-compiler --no-audit --no-fund | Out-Null
    Pop-Location
}

if (-not (Test-Path (Join-Path $root "app\build\windows\x64\runner\Release\rmrb_reader.exe"))) {
    throw "请先 flutter build windows --release，并把 PyInstaller 产物放进 Release\engine"
}

& $bin (Join-Path $PSScriptRoot "installer.iss")
if ($LASTEXITCODE -ne 0) { throw "ISCC 编译失败" }

Get-ChildItem $dist -Filter "*-setup.exe" | ForEach-Object {
    Write-Host ("安装包：{0}（{1:N1} MB）" -f $_.FullName, ($_.Length / 1MB)) -ForegroundColor Green
}
