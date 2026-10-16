$ErrorActionPreference = "Stop"

Set-Location -LiteralPath $PSScriptRoot

$branch = "main"
$linksFile = "links.txt"
$changedFile = "changed.txt"

function Update-Links {
    $exts = @(".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp", ".tiff", ".svg", ".avif")
    $files = Get-ChildItem -File |
        Where-Object { $exts -contains $_.Extension.ToLower() } |
        Sort-Object Name
    $links = $files | ForEach-Object { "https://raw.githubusercontent.com/cube-gif/NightTab/$branch/$($_.Name)" }
    [System.IO.File]::WriteAllLines("$PSScriptRoot\$linksFile", $links, (New-Object System.Text.UTF8Encoding($false)))
    return $files.Name
}

git add -A
$status = git status --porcelain

if (-not $status) {
    Write-Host "Изменений нет."
    exit 0
}

$realChanges = $status | Where-Object {
    $_ -notmatch "^..\s+$([regex]::Escape($linksFile))$" -and
    $_ -notmatch "^..\s+$([regex]::Escape($changedFile))$"
}

if ($realChanges) {
    $summary = git diff --cached --name-status |
        Where-Object { $_ -notmatch "\t$([regex]::Escape($linksFile))$" -and $_ -notmatch "\t$([regex]::Escape($changedFile))$" } |
        ForEach-Object {
            $p = $_ -split "`t"
            switch -Regex ($p[0]) {
                "^D" { "удалён: $($p[1])" }
                "^A" { "добавлен: $($p[1])" }
                default { "изменён: $($p[1])" }
            }
        }

    $date = Get-Date -Format "dd.MM HH:mm"
    git commit -m "$date Синхронизация файлов"
    git push origin $branch

    Write-Host "Закоммичено:"
    $summary | ForEach-Object { Write-Host "  $_" }
}

$allNames = Update-Links

$changedUrls = @()
if (Test-Path -LiteralPath "$PSScriptRoot\.git\refs\heads\$branch") {
    $changedUrls = git diff --name-status "HEAD~1" HEAD |
        Where-Object { $_ -match "^(A|M)\t" } |
        ForEach-Object {
            $name = ($_ -split "`t")[1]
            if (Test-Path -LiteralPath "$PSScriptRoot\$name") {
                "https://raw.githubusercontent.com/cube-gif/NightTab/$branch/$name"
            }
        }
}

[System.IO.File]::WriteAllLines("$PSScriptRoot\$changedFile", $changedUrls, (New-Object System.Text.UTF8Encoding($false)))

git add -A
if (git status --porcelain) {
    git commit -m "Обновить списки ссылок"
    git push origin $branch
}

Write-Host "Готово. Всего ссылок: $($allNames.Count), новых/изменённых: $($changedUrls.Count)"
