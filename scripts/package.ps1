# 一键打包：引擎（PyInstaller）→ 应用（Flutter release）→ 便携目录
#
# 用法：
#   pwsh scripts/package.ps1
#   pwsh scripts/package.ps1 -Out "D:\dist\人民日报阅报器"
param(
    [string]$Out = ""
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Out)) {
    $Out = Join-Path $root 'dist\人民日报阅报器'
}

Write-Host '[1/3] 构建引擎…' -ForegroundColor Cyan
Push-Location (Join-Path $root 'engine')
try {
    uv run pyinstaller --noconfirm --clean --onedir --name rmrb_engine `
        --paths src --distpath dist --workpath build packaging/entry.py | Out-Null
    if (-not (Test-Path 'dist\rmrb_engine\rmrb_engine.exe')) {
        throw '引擎构建失败：未生成 rmrb_engine.exe'
    }
}
finally { Pop-Location }

Write-Host '[2/3] 构建应用…' -ForegroundColor Cyan
Push-Location (Join-Path $root 'app')
try {
    flutter build windows --release | Out-Null
}
finally { Pop-Location }

$release = Join-Path $root 'app\build\windows\x64\runner\Release'
$engineDist = Join-Path $root 'engine\dist\rmrb_engine'
$engineTarget = Join-Path $release 'engine'

Write-Host '[3/3] 组装便携目录…' -ForegroundColor Cyan
if (Test-Path $engineTarget) { Remove-Item -Recurse -Force $engineTarget }
Copy-Item -Recurse $engineDist $engineTarget

if (Test-Path $Out) { Remove-Item -Recurse -Force $Out }
New-Item -ItemType Directory -Force $Out | Out-Null
Copy-Item -Recurse (Join-Path $release '*') $Out

$size = (Get-ChildItem $Out -Recurse -File | Measure-Object Length -Sum).Sum / 1MB
Write-Host ("完成：{0}（{1:N1} MB）" -f $Out, $size) -ForegroundColor Green
Write-Host '运行：双击目录内的 rmrb_reader.exe'
