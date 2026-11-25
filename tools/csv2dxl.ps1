# csv2dxl.ps1
# 把 data\requirements.csv 转成 DOORS 可执行的 DXL 导入脚本 dxl\import-all.dxl
# 用法: powershell -NoProfile -ExecutionPolicy Bypass -File .\csv2dxl.ps1
#
# 关键点:
#   1. DXL 文件必须是 UTF-8 with BOM，DOORS 才能正确识别中文
#   2. 文件夹和模块都用"绝对路径"创建；相对名字会建到客户端当前所在文件夹
#   3. DXL 的 create(Module) 会把新对象插到模块最顶部，所以要"倒序"生成
#   4. 创建前先用 item(路径) 判重，避免重复导入时抛"项名称重复"运行时错误
#   5. 模块不能建在数据库根目录，必须先建项目文件夹

param(
    [string]$Csv = '',
    [string]$Out = ''
)

$ErrorActionPreference = 'Stop'

$root    = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($Csv)) { $Csv = Join-Path $root 'data\requirements.csv' }
if ([string]::IsNullOrWhiteSpace($Out)) { $Out = Join-Path $root 'dxl\import-all.dxl' }
$csvPath = $Csv
$dxlPath = $Out
$logFile = (($root -replace '\\', '/') + '/output/import.log')

$rows = Import-Csv -Path $csvPath -Encoding UTF8

function Esc([string]$s) {
    if ($null -eq $s) { return '' }
    return $s.Replace('\', '\\').Replace('"', '\"')
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('// 自动生成文件，请勿手工修改；源数据见 data/requirements.csv')
[void]$sb.AppendLine('// 生成脚本: tools/csv2dxl.ps1')
[void]$sb.AppendLine('')
[void]$sb.AppendLine('Stream log = write("' + $logFile + '")')
[void]$sb.AppendLine('log << "import start\n"')
[void]$sb.AppendLine('')

# ---- 1. 项目文件夹（模块不能直接建在根目录）----
$folders = @()
foreach ($r in $rows) {
    if ($folders -notcontains $r.Folder) { $folders += $r.Folder }
}

[void]$sb.AppendLine('// ---- 1. 项目文件夹 ----')
$i = 0
foreach ($f in $folders) {
    $i++
    $chk = 'chk' + $i
    $fd  = 'fd' + $i
    [void]$sb.AppendLine('Item ' + $chk + ' = item("/' + (Esc $f) + '")')
    [void]$sb.AppendLine('if (null ' + $chk + ') {')
    [void]$sb.AppendLine('    Folder ' + $fd + ' = create("/' + (Esc $f) + '", "' + (Esc ($f + '（企业级需求库）')) + '")')
    [void]$sb.AppendLine('    if (null ' + $fd + ') { log << "folder ' + (Esc $f) + ': failed\n" } else { log << "folder ' + (Esc $f) + ': created\n" }')
    [void]$sb.AppendLine('} else {')
    [void]$sb.AppendLine('    log << "folder ' + (Esc $f) + ': exists\n"')
    [void]$sb.AppendLine('}')
}
[void]$sb.AppendLine('')

# ---- 2. 各模块 ----
$codes = @()
foreach ($r in $rows) { if ($codes -notcontains $r.Module) { $codes += $r.Module } }

foreach ($code in $codes) {
    $modRows = @($rows | Where-Object { $_.Module -eq $code })
    if ($modRows.Count -eq 0) { continue }

    $folder    = $modRows[0].Folder
    $modName   = $modRows[0].ModuleName
    $modPath   = '/' + $folder + '/' + $modName
    $reqCount  = @($modRows | Where-Object { $_.Kind -eq '需求' }).Count
    $headCount = $modRows.Count - $reqCount
    $mvar      = 'm_' + $code
    $chk       = 'ex_' + $code

    [void]$sb.AppendLine('// ---- 模块 ' + $code + ' (' + $modName + ') ----')
    [void]$sb.AppendLine('Item ' + $chk + ' = item("' + (Esc $modPath) + '")')
    [void]$sb.AppendLine('if (null ' + $chk + ') {')
    [void]$sb.AppendLine('    Module ' + $mvar + ' = create("' + (Esc $modPath) + '", "' + (Esc ($code + ' 需求规格说明')) + '", "", 1, false)')
    [void]$sb.AppendLine('    if (null ' + $mvar + ') {')
    [void]$sb.AppendLine('        log << "' + $code + ': module create failed\n"')
    [void]$sb.AppendLine('    } else {')
    [void]$sb.AppendLine('        Object o')
    [void]$sb.AppendLine('        Object h')

    # 倒序：create(Module) 插到最前面，所以按相反顺序生成，最终显示顺序才正确
    [array]::Reverse($modRows)
    foreach ($r in $modRows) {
        if ($r.Kind -eq '需求') {
            $text = $r.ReqId + ' ' + $r.Title + '：' + $r.Desc +
                    '【类型:' + $r.Type + '｜优先级:' + $r.Priority + '｜验证:' + $r.Method +
                    '｜状态:' + $r.Status + '｜责任人:' + $r.Owner + '｜来源:' + $r.Source + '】'
            [void]$sb.AppendLine('        o = create(' + $mvar + ')')
            [void]$sb.AppendLine('        o."Object Text" = "' + (Esc $text) + '"')
        }
        else {
            [void]$sb.AppendLine('        h = create(' + $mvar + ')')
            [void]$sb.AppendLine('        h."Object Heading" = "' + (Esc $r.Chapter) + '"')
        }
    }

    [void]$sb.AppendLine('        save ' + $mvar)
    [void]$sb.AppendLine('        log << "' + $code + ': created (' + $reqCount + ' reqs, ' + $headCount + ' headings)\n"')
    [void]$sb.AppendLine('    }')
    [void]$sb.AppendLine('} else {')
    [void]$sb.AppendLine('    log << "' + $code + ': already exists, skipped\n"')
    [void]$sb.AppendLine('}')
    [void]$sb.AppendLine('')
}

[void]$sb.AppendLine('log << "import done\n"')
[void]$sb.AppendLine('close(log)')

[System.IO.File]::WriteAllText($dxlPath, $sb.ToString(), (New-Object System.Text.UTF8Encoding($true)))

Write-Output ('DXL 已生成: ' + $dxlPath)
Write-Output ('行数: ' + ($sb.ToString() -split "`n").Count)
Write-Output ('模块: ' + ($codes -join ', '))
