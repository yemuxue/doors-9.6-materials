# change-impact.ps1
# P1+P2 演示：基线快照 → 变更一条需求 → 差异对比 → 影响分析
# 用法: powershell -NoProfile -ExecutionPolicy Bypass -File .\change-impact.ps1

$ErrorActionPreference = 'Stop'

$root    = Split-Path -Parent $PSScriptRoot
$runner  = 'C:\doors-demo\doors\doors-run.ps1'
$psExe   = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$outDir  = Join-Path $root 'output'
$report  = Join-Path $outDir 'change-impact-report.txt'

function Run-Dxl([string]$file) {
    & $psExe -NoProfile -ExecutionPolicy Bypass -File $runner -DxlFile $file -WaitSeconds 300 | Out-Null
}

function Read-Gbk([string]$path) {
    if (-not (Test-Path $path)) { return @() }
    return [System.IO.File]::ReadAllLines($path, [System.Text.Encoding]::GetEncoding(936))
}

# ---- 1. 变更前快照（基线 v1.0）----
Remove-Item (Join-Path $outDir '_snap.txt') -ErrorAction SilentlyContinue
Run-Dxl (Join-Path $root 'dxl\snapshot.dxl')
Copy-Item (Join-Path $outDir '_snap.txt') (Join-Path $outDir 'snapshot-before.txt') -Force

# ---- 2. 执行变更 ----
Run-Dxl (Join-Path $root 'dxl\change-demo.dxl')

# ---- 3. 变更后快照 ----
Remove-Item (Join-Path $outDir '_snap.txt') -ErrorAction SilentlyContinue
Run-Dxl (Join-Path $root 'dxl\snapshot.dxl')
Copy-Item (Join-Path $outDir '_snap.txt') (Join-Path $outDir 'snapshot-after.txt') -Force

# ---- 4. 影响分析 ----
Run-Dxl (Join-Path $root 'dxl\impact.dxl')

# ---- 5. 差异对比 ----
$before = @{}
foreach ($line in (Read-Gbk (Join-Path $outDir 'snapshot-before.txt'))) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $p = $line.Split('|', 3)
    if ($p.Count -lt 3) { continue }
    if ($p[2] -match '^([A-Z]+-\d{4})') { $before[$Matches[1]] = $p[2] }
}
$after = @{}
foreach ($line in (Read-Gbk (Join-Path $outDir 'snapshot-after.txt'))) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $p = $line.Split('|', 3)
    if ($p.Count -lt 3) { continue }
    if ($p[2] -match '^([A-Z]+-\d{4})') { $after[$Matches[1]] = $p[2] }
}

$changedKeys = @()
foreach ($k in $after.Keys) {
    if (-not $before.ContainsKey($k)) { $changedKeys += $k }
    elseif ($before[$k] -ne $after[$k]) { $changedKeys += $k }
}

# ---- 6. 汇总影响 ----
$impact = Read-Gbk (Join-Path $outDir 'impact.txt')
$direct = @($impact | Where-Object { $_ -like 'D|*' })
$second = @($impact | Where-Object { $_ -like '2|*' })
$changedLine = ($impact | Where-Object { $_ -like 'CHANGED|*' } | Select-Object -First 1)

$o = New-Object System.Text.StringBuilder
[void]$o.AppendLine('==================================================')
[void]$o.AppendLine(' 变更影响分析报告（基线 v1.0 → 变更 v1.1）')
[void]$o.AppendLine(' 时间: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
[void]$o.AppendLine('==================================================')
[void]$o.AppendLine('')
[void]$o.AppendLine('--- 1. 基线 v1.0 快照 ---')
[void]$o.AppendLine(('  需求对象快照: {0} 条（snapshot-before.txt）' -f $before.Count))
[void]$o.AppendLine('')
[void]$o.AppendLine('--- 2. 本次变更 ---')
[void]$o.AppendLine(('  变更对象数: {0}' -f $changedKeys.Count))
foreach ($k in $changedKeys) {
    [void]$o.AppendLine(('  [{0}]' -f $k))
    [void]$o.AppendLine('    变更前: ' + $before[$k])
    [void]$o.AppendLine('    变更后: ' + $after[$k])
}
[void]$o.AppendLine('')
[void]$o.AppendLine('--- 3. 影响分析（按链接图遍历）---')
[void]$o.AppendLine(('  直接关联: {0} 个   二跳关联: {1} 个' -f $direct.Count, $second.Count))
[void]$o.AppendLine('')
foreach ($line in $direct) {
    $p = $line.Split('|')
    if ($p.Count -ge 5) {
        $dir = if ($p[1] -eq 'OUT') { '下游(分解)' } else { '上游(验证)' }
        [void]$o.AppendLine(('  [{0}][{1}] {2}' -f $dir, $p[2], $p[4]))
    }
}
[void]$o.AppendLine('')
if ($second.Count -gt 0) {
    [void]$o.AppendLine('  二跳（子系统需求 → 软件需求）:')
    foreach ($line in $second) {
        $p = $line.Split('|')
        if ($p.Count -ge 5) {
            [void]$o.AppendLine(('    [{0}] {1}' -f $p[2], $p[4]))
        }
    }
}
[void]$o.AppendLine('')
[void]$o.AppendLine('--- 4. 结论 ---')
[void]$o.AppendLine(('  本次变更 1 条系统需求，波及 {0} 条直接关联对象、{1} 条二跳对象，' -f $direct.Count, $second.Count))
[void]$o.AppendLine('  需要在评审中确认这些下游对象是否同步修改。')
[void]$o.AppendLine('')
[void]$o.AppendLine('说明：')
[void]$o.AppendLine('  * 本环境 DXL 的 baseline()/基线集接口返回 false 或不支持出参，')
[void]$o.AppendLine('    因此用"快照 + 差异对比"实现基线比对效果；DOORS 原生基线的 GUI 步骤见文档第 9 章。')

[System.IO.File]::WriteAllText($report, $o.ToString(), (New-Object System.Text.UTF8Encoding($true)))
Write-Output $o.ToString()
