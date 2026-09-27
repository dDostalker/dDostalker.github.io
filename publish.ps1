#requires -Version 7
<#
.SYNOPSIS
    博客发布脚本：把 posts/ 下的平铺文章同步成 Zola 结构并构建/预览/部署。

.DESCRIPTION
    写作时和利刃笔记完全一样：
        blog/posts/文章名.md
        blog/posts/文章名.assets/图片.png   （Obsidian 粘贴自动生成）
    本脚本把每篇文章转换为 content/文章名/index.md + 文章名.assets/，
    front matter 从 YAML(---) 转为 Zola 需要的 TOML(+++)。

.USAGE
    .\publish.ps1              仅同步
    .\publish.ps1 -Preview     同步 + 本地预览 (http://127.0.0.1:1111)
    .\publish.ps1 -Build       同步 + 构建到本地目录（不推送）
    .\publish.ps1 -Deploy      同步 + 构建 + git 提交推送（触发 GitHub Actions 部署）
    .\publish.ps1 -SyncOnly    仅同步（CI 用）
#>
param(
    [switch]$Preview,
    [switch]$Build,
    [switch]$Deploy,
    [switch]$SyncOnly
)

$ErrorActionPreference = "Stop"
$root     = $PSScriptRoot
$postsDir = Join-Path $root "posts"
$destDir  = Join-Path $root "content"
$buildDir = "C:\Users\dDostalker\zola-build\ddostalker.github.io"   # 构建产物放 OneDrive 外，避免同步

$zola = 'zola'
if ($IsWindows -and (Test-Path (Join-Path $env:USERPROFILE 'bin\zola.exe'))) {
    $zola = Join-Path $env:USERPROFILE 'bin\zola.exe'
}

function Esc([string]$s) { $s.Replace('\', '\\').Replace('"', '\"') }

function Convert-Post {
    param([string]$mdPath)

    $lines = Get-Content -LiteralPath $mdPath -Encoding utf8
    $name = [IO.Path]::GetFileNameWithoutExtension($mdPath)
    $fm = @{}

    # front matter 可选：没有就自动用 文件名=标题、修改时间=日期
    if ($lines.Count -ge 1 -and $lines[0].Trim() -eq '---') {
        $end = -1
        for ($i = 1; $i -lt $lines.Count; $i++) {
            if ($lines[$i].Trim() -eq '---') { $end = $i; break }
        }
        if ($end -lt 0) { throw "front matter 未闭合: $mdPath" }
        $bodyStart = $end + 1
    }
    else {
        Write-Host "  [提示] $name 无 front matter，自动以文件名为标题、修改时间为日期" -ForegroundColor DarkYellow
        $bodyStart = 0
    }

    # ---- 解析 YAML front matter ----
    $fm = @{}
    $i = 1
    while ($i -lt $end) {
        if ($lines[$i] -match '^\s*([A-Za-z_][\w-]*)\s*:\s*(.*)$') {
            $key = $Matches[1].ToLower()
            $val = $Matches[2].Trim()
            if ($key -in 'tags', 'categories') {
                $items = @()
                if ($val -eq '') {
                    # 块列表: 每行 "  - xxx"
                    $j = $i + 1
                    while ($j -lt $end -and $lines[$j] -match '^\s+-\s+(.+)$') {
                        $items += $Matches[1].Trim().Trim('"', "'")
                        $j++
                    }
                    $i = $j
                }
                else {
                    # 行内列表: [a, b]
                    $items = $val.Trim().TrimStart('[').TrimEnd(']') -split ',' |
                        ForEach-Object { $_.Trim().Trim('"', "'") } | Where-Object { $_ }
                    $i++
                }
                if ($items) { $fm[$key] = @($items) }
                continue
            }
            $fm[$key] = $val
        }
        $i++
    }

    # ---- 生成 TOML front matter ----
    $toml = [System.Collections.Generic.List[string]]::new()
    $toml.Add('+++')
    $toml.Add('title = "' + (Esc ($fm['title'] ?? $name)) + '"')
    if ($fm['description']) { $toml.Add('description = "' + (Esc $fm['description']) + '"') }
    if ($fm['date']) {
        try {
            $d = [datetime]::Parse($fm['date'], [cultureinfo]::InvariantCulture)
            $toml.Add('date = ' + $d.ToString('yyyy-MM-ddTHH:mm:ss'))
        }
        catch { $toml.Add('date = "' + (Esc $fm['date']) + '"') }
    }
    else {
        $toml.Add('date = ' + (Get-Item -LiteralPath $mdPath).LastWriteTime.ToString('yyyy-MM-ddTHH:mm:ss'))
    }
    if ($fm['draft'] -eq 'true') { $toml.Add('draft = true') }
    if ($fm['tags'] -or $fm['categories']) {
        $toml.Add('')
        $toml.Add('[taxonomies]')
        if ($fm['tags'])       { $toml.Add('tags = [' + (($fm['tags']       | ForEach-Object { '"' + (Esc $_) + '"' }) -join ', ') + ']') }
        if ($fm['categories']) { $toml.Add('categories = [' + (($fm['categories'] | ForEach-Object { '"' + (Esc $_) + '"' }) -join ', ') + ']') }
    }
    $toml.Add('+++')
    $toml.Add('')

    # ---- 正文：把 .assets 相对路径里的 %XX 编码还原，避免构建警告 ----
    $body = if ($bodyStart -lt $lines.Count) { $lines[$bodyStart..($lines.Count - 1)] -join "`n" } else { '' }
    # Zola 不认识的语言名映射成等价高亮
    $body = [regex]::Replace($body, '(?m)^```(Plain|plain|text|Text|plaintext|txt)\s*$', '```')
    $body = [regex]::Replace($body, '(?m)^```(Shell|shell)\s*$', '```bash')
    $body = [regex]::Replace($body, '\]\(([^)\s]+\.assets/[^)\s]+)\)', {
        param($m)
        '](' + [uri]::UnescapeDataString($m.Groups[1].Value) + ')'
    })
    if ($body -match '!\[\[') {
        Write-Warning "$name 里存在 Obsidian 双链图片语法 ![[ ]]，Zola 不支持，请改用普通 markdown 链接"
    }

    # ---- 输出 index.md + 拷贝 .assets ----
    $postDir = Join-Path $destDir $name
    New-Item -ItemType Directory -Force $postDir | Out-Null
    Set-Content -LiteralPath (Join-Path $postDir 'index.md') -Value ($toml -join "`n") -NoNewline:$false -Encoding utf8
    Add-Content -LiteralPath (Join-Path $postDir 'index.md') -Value $body -Encoding utf8 -NoNewline:$true

    $assets = [IO.Path]::ChangeExtension($mdPath, '.assets')
    if (Test-Path -LiteralPath $assets) {
        Copy-Item -LiteralPath $assets -Destination (Join-Path $postDir (Split-Path $assets -Leaf)) -Recurse -Force
    }
    else {
        Write-Host "  [提示] $name 没有对应的 .assets 图片文件夹（纯文字文章可忽略）" -ForegroundColor DarkGray
    }
    Write-Host "  [同步] $name" -ForegroundColor Green
}

# ================= main =================
if (-not (Test-Path -LiteralPath $postsDir)) { throw "找不到 posts 目录: $postsDir" }

Write-Host "== 同步文章 posts/ -> content/ ==" -ForegroundColor Cyan
Get-ChildItem -LiteralPath $destDir -Directory -ErrorAction SilentlyContinue |
    Remove-Item -Recurse -Force

# 自愈：content/_index.md 是首页配置（分页/排序），误删时自动补建
$rootIndex = Join-Path $destDir "_index.md"
if (-not (Test-Path -LiteralPath $rootIndex)) {
    Set-Content -LiteralPath $rootIndex -Encoding utf8 -Value @(
        '+++'
        'paginate_by = 15'
        'sort_by = "date"'
        'template = "index.html"'
        '+++'
        ''
    )
    Write-Host "  [修复] 重新生成 content/_index.md" -ForegroundColor Yellow
}

$mds = Get-ChildItem -LiteralPath $postsDir -Filter *.md -File
if (-not $mds) { Write-Warning "posts/ 下没有 .md 文章" }
foreach ($md in $mds) { Convert-Post -mdPath $md.FullName }
Write-Host "== 共同步 $($mds.Count) 篇 ==" -ForegroundColor Cyan

if ($SyncOnly -or ($PSBoundParameters.Count -eq 0)) {
    if ($PSBoundParameters.Count -eq 0) {
        Write-Host "`n提示: -Preview 本地预览 / -Build 构建 / -Deploy 推送部署" -ForegroundColor DarkGray
    }
    return
}

if ($Preview) {
    Push-Location $root
    try { & $zola serve --force --output-dir $buildDir }
    finally { Pop-Location }
    return
}

if ($Build -or $Deploy) {
    Push-Location $root
    try {
        & $zola build --force --output-dir $buildDir
    }
    finally { Pop-Location }
    if ($LASTEXITCODE -ne 0) { throw "zola build 失败" }
    Write-Host "== 构建完成: $buildDir ==" -ForegroundColor Cyan
}

if ($Deploy) {
    Push-Location $root
    try {
        git add -A
        git diff --cached --quiet
        if ($LASTEXITCODE -ne 0) {
            git commit -m "publish: $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
            git push
            Write-Host "== 已推送，GitHub Actions 将自动部署 ==" -ForegroundColor Cyan
        }
        else {
            Write-Host "== 没有需要提交的变更 ==" -ForegroundColor DarkGray
        }
    }
    finally { Pop-Location }
}
