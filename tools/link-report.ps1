# link-report.ps1
# 生成 V 形追溯覆盖报告（八层模型）
# 用法: powershell -NoProfile -ExecutionPolicy Bypass -File .\link-report.ps1

$ErrorActionPreference = 'Stop'

$root    = Split-Path -Parent $PSScriptRoot
$dxlPath = Join-Path $root 'dxl\link-coverage.dxl'
$dataTxt = Join-Path $root 'output\link-coverage.txt'
$report  = Join-Path $root 'output\link-report.txt'
$runner  = 'C:\doors-demo\doors\doors-run.ps1'
$psExe   = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

Remove-Item $dataTxt -ErrorAction SilentlyContinue
& $psExe -NoProfile -ExecutionPolicy Bypass -File $runner -DxlFile $dxlPath -WaitSeconds 600 | Out-Null

$lines = @()
if (Test-Path $dataTxt) {
    $lines = [System.IO.File]::ReadAllLines($dataTxt, [System.Text.Encoding]::GetEncoding(936))
}

$stats = @{}
foreach ($line in $lines) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $p = $line.Split('|')
    if ($p.Count -lt 3) { continue }
    $code = $p[0]
    $marks = $p[2]
    $out = 0; $in = 0
    if ($marks -match '^(x*)/(y*)$') { $out = $Matches[1].Length; $in = $Matches[2].Length }
    if (-not $stats.ContainsKey($code)) {
        $stats[$code] = [pscustomobject]@{ Total = 0; WithOut = 0; WithIn = 0; OutSum = 0; InSum = 0 }
    }
    $s = $stats[$code]
    $s.Total++
    if ($out -gt 0) { $s.WithOut++ }
    if ($in -gt 0) { $s.WithIn++ }
    $s.OutSum += $out
    $s.InSum += $in
}

function Pct($n, $d) { if ($d -eq 0) { return '0.0%' } return ('{0:N1}%' -f (100.0 * $n / $d)) }

$o = New-Object System.Text.StringBuilder
[void]$o.AppendLine('==================================================')
[void]$o.AppendLine(' V 形追溯覆盖报告（八层模型）')
[void]$o.AppendLine(' 时间: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
[void]$o.AppendLine('==================================================')
[void]$o.AppendLine('')
[void]$o.AppendLine('层级      模块   对象数  有出链  有入链  出链合计  入链合计')
[void]$o.AppendLine('------------------------------------------------------------')

$order = @(
    @('L1 用户需求', 'UR'), @('L2 系统需求', 'SYS'), @('L3 安防子系统', 'SEC'),
    @('L3 能源子系统', 'NRG'), @('L3 通行子系统', 'ACS'), @('L4 软件需求', 'SW'),
    @('L5 验证用例', 'TC'), @('L6 代码单元', 'CODE')
)
foreach ($row in $order) {
    $code = $row[1]
    if (-not $stats.ContainsKey($code)) { continue }
    $s = $stats[$code]
    [void]$o.AppendLine(('{0,-10} {1,-5} {2,6} {3,7} {4,7} {5,9} {6,9}' -f `
                $row[0], $code, $s.Total, $s.WithOut, $s.WithIn, $s.OutSum, $s.InSum))
}
[void]$o.AppendLine('')

$ur = $stats['UR']; $sys = $stats['SYS']; $sw = $stats['SW']; $tc = $stats['TC']; $code = $stats['CODE']
$subTotal = 0; $subCovered = 0
foreach ($c in @('SEC', 'NRG', 'ACS')) { if ($stats.ContainsKey($c)) { $subTotal += $stats[$c].Total; $subCovered += $stats[$c].WithIn } }

[void]$o.AppendLine('--- 关键指标 ---')
if ($ur) { [void]$o.AppendLine(('用户需求分解率    : {0}（{1}/{2} 条用户需求有系统需求承接）' -f (Pct $ur.WithOut $ur.Total), $ur.WithOut, $ur.Total)) }
if ($sys) { [void]$o.AppendLine(('系统需求分解率    : {0}（{1}/{2} 条有子系统需求承接）' -f (Pct $sys.WithOut $sys.Total), $sys.WithOut, $sys.Total)) }
if ($subTotal -gt 0) { [void]$o.AppendLine(('子系统需求承接率  : {0}（{1}/{2} 条有上游来源）' -f (Pct $subCovered $subTotal), $subCovered, $subTotal)) }
if ($sw) { [void]$o.AppendLine(('软件需求实现率    : {0}（{1}/{2} 条有代码单元实现）' -f (Pct $sw.WithIn $sw.Total), $sw.WithIn, $sw.Total)) }
if ($code) { [void]$o.AppendLine(('代码单元关联率    : {0}（{1}/{2} 个代码单元已关联需求）' -f (Pct $code.WithOut $code.Total), $code.WithOut, $code.Total)) }
if ($tc) { [void]$o.AppendLine(('测试用例关联率    : {0}（{1}/{2} 条已关联需求）' -f (Pct $tc.WithOut $tc.Total), $tc.WithOut, $tc.Total)) }
[void]$o.AppendLine('')
[void]$o.AppendLine('--- 测试层级分布（按设计）---')
[void]$o.AppendLine('  单元测试 30 条 -> 软件需求 SW')
[void]$o.AppendLine('  集成测试 25 条 -> SEC 8 / NRG 8 / ACS 9')
[void]$o.AppendLine('  系统测试 25 条 -> 系统需求 SYS')
[void]$o.AppendLine('  验收测试 13 条 -> 用户需求 UR')
[void]$o.AppendLine('')
[void]$o.AppendLine('--- 链接方向约定 ---')
[void]$o.AppendLine('  分解：需求 -> 子需求（向下）')
[void]$o.AppendLine('  实现：代码单元 -> 软件需求（向上）')
[void]$o.AppendLine('  验证：测试用例 -> 被验证对象（向上）')

[System.IO.File]::WriteAllText($report, $o.ToString(), (New-Object System.Text.UTF8Encoding($true)))
Write-Output $o.ToString()
