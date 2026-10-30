# 一键打包：引擎（PyInstaller）→ 应用（Flutter release）→ 便携目录
#
# 用法：
#   pwsh scripts/package.ps1
#   pwsh scripts/package.ps1 -Out "D:\dist\朝闻-portable"
param(
    [string]$Out = ""
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Out)) {
    $Out = Join-Path $root 'dist\朝闻-portable'
}

Write-Host '[1/3] 构建引擎…' -ForegroundColor Cyan
Push-Location (Join-Path $root 'engine')
try {
    # 用 python -m PyInstaller：venv 里的 console script 在目录改名后会指向旧路径
    uv run --no-sync python -m PyInstaller --noconfirm --clean --onedir --name rmrb_engine `
        --paths src --distpath dist --workpath build packaging/entry.py | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path 'dist\rmrb_engine\rmrb_engine.exe')) {
        throw '引擎构建失败：未生成 rmrb_engine.exe'
    }
}
finally { Pop-Location }

Write-Host '[2/3] 构建应用…' -ForegroundColor Cyan
Push-Location (Join-Path $root 'app')
try {
    flutter build windows --release --no-pub | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Flutter 构建失败' }
}
finally { Pop-Location }

$release = Join-Path $root 'app\build\windows\x64\runner\Release'
$engineDist = Join-Path $root 'engine\dist\rmrb_engine'
$engineTarget = Join-Path $release 'engine'

Write-Host '[3/3] 组装发布目录…' -ForegroundColor Cyan
if (Test-Path $engineTarget) { Remove-Item -Recurse -Force $engineTarget }
Copy-Item -Recurse $engineDist $engineTarget

# 清掉历史调试构建留下的多余可执行文件，避免被打进安装包
Get-ChildItem $release -Filter '*.exe' |
    Where-Object { $_.Name -ne 'rmrb_reader.exe' } |
    Remove-Item -Force

# 许可证与第三方声明（OFL 与 MIT/Apache 均要求随分发保留）
foreach ($name in @('LICENSE', 'THIRD-PARTY-NOTICES.md')) {
    $src = Join-Path $root $name
    if (Test-Path $src) { Copy-Item $src (Join-Path $release $name) -Force }
}
$ofl = Join-Path $root 'fonts\OFL.txt'
if (Test-Path $ofl) { Copy-Item $ofl (Join-Path $release 'OFL.txt') -Force }
$oflApp = Join-Path $root 'app\assets\fonts\OFL.txt'
if (Test-Path $oflApp) { Copy-Item $oflApp (Join-Path $release 'OFL.txt') -Force }

if (Test-Path $Out) { Remove-Item -Recurse -Force $Out }
New-Item -ItemType Directory -Force $Out | Out-Null
Copy-Item -Recurse (Join-Path $release '*') $Out

$size = (Get-ChildItem $Out -Recurse -File | Measure-Object Length -Sum).Sum / 1MB
Write-Host ("完成：{0}（{1:N1} MB）" -f $Out, $size) -ForegroundColor Green
Write-Host '运行：双击目录内的 rmrb_reader.exe'
