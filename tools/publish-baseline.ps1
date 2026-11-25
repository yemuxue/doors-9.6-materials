# publish-baseline.ps1
# 第 2 步：发布基线（快照 + 发布清单）
# 用法: powershell -NoProfile -ExecutionPolicy Bypass -File .\publish-baseline.ps1 -Version v1.0

param(
    [string]$Version = 'v1.0'
)

$ErrorActionPreference = 'Stop'

$root    = Split-Path -Parent $PSScriptRoot
$runner  = 'C:\doors-demo\doors\doors-run.ps1'
$psExe   = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$relDir  = Join-Path $root 'output\releases'
$manifest = Join-Path $relDir ($Version + '-manifest.txt')

if (-not (Test-Path $relDir)) { New-Item -ItemType Directory -Path $relDir | Out-Null }

# 1. 快照
Remove-Item (Join-Path $root 'output\_snap.txt') -ErrorAction SilentlyContinue
& $psExe -NoProfile -ExecutionPolicy Bypass -File $runner -DxlFile (Join-Path $root 'dxl\snapshot.dxl') -WaitSeconds 300 | Out-Null

$snapDst = Join-Path $relDir ($Version + '-snapshot.txt')
Copy-Item (Join-Path $root 'output\_snap.txt') $snapDst -Force

# 2. 统计
$snap = [System.IO.File]::ReadAllLines($snapDst, [System.Text.Encoding]::GetEncoding(936)) | Where-Object { $_ -ne '' }
$byModule = @{}
foreach ($line in $snap) {
    $code = $line.Split('|')[0]
    if (-not $byModule.ContainsKey($code)) { $byModule[$code] = 0 }
    $byModule[$code]++
}

# 覆盖率（如果之前跑过 link-report）
$covFile = Join-Path $root 'output\link-report.txt'
$covLines = @()
if (Test-Path $covFile) {
    $covLines = ([System.IO.File]::ReadAllLines($covFile, [System.Text.Encoding]::UTF8)) | Where-Object { $_ -match '系统需求分解率|系统需求测试覆盖率|子系统需求承接率|软件需求追溯率|测试用例关联率' }
}

# 变更单统计
$crFile = Join-Path $root 'data\change-requests.csv'
$crTotal = 0; $crOpen = 0
if (Test-Path $crFile) {
    $crs = Import-Csv -Path $crFile -Encoding UTF8
    $crTotal = $crs.Count
    $crOpen = @($crs | Where-Object { $_.Status -ne '已关闭' }).Count
}

$o = New-Object System.Text.StringBuilder
[void]$o.AppendLine('==================================================')
[void]$o.AppendLine(' 需求库发布基线清单')
[void]$o.AppendLine(' 版本: ' + $Version)
[void]$o.AppendLine(' 发布时间: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
[void]$o.AppendLine('==================================================')
[void]$o.AppendLine('')
[void]$o.AppendLine('--- 1. 快照 ---')
[void]$o.AppendLine('  文件: ' + (Split-Path -Leaf $snapDst))
[void]$o.AppendLine('  需求对象总数: ' + $snap.Count)
[void]$o.AppendLine('')
[void]$o.AppendLine('--- 2. 分模块数量 ---')
foreach ($k in ($byModule.Keys | Sort-Object)) {
    [void]$o.AppendLine(('  {0,-5} {1,4}' -f $k, $byModule[$k]))
}
[void]$o.AppendLine('')
[void]$o.AppendLine('--- 3. 追溯覆盖 ---')
if ($covLines.Count -gt 0) { foreach ($c in $covLines) { [void]$o.AppendLine('  ' + $c.Trim()) } }
else { [void]$o.AppendLine('  (未生成覆盖率报告，可先运行 tools/link-report.ps1)') }
[void]$o.AppendLine('')
[void]$o.AppendLine('--- 4. 变更单 ---')
[void]$o.AppendLine(('  总数: {0}   未关闭: {1}' -f $crTotal, $crOpen))
[void]$o.AppendLine('')
[void]$o.AppendLine('--- 5. 发布说明 ---')
[void]$o.AppendLine('  本清单是"快照式基线"：记录发布时刻的全部需求文本与追溯覆盖率。')
[void]$o.AppendLine('  DOORS 原生基线请按文档第 10.1 节在模块窗口手工创建。')

[System.IO.File]::WriteAllText($manifest, $o.ToString(), (New-Object System.Text.UTF8Encoding($true)))
Write-Output $o.ToString()
