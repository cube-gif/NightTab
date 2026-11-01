$ErrorActionPreference = "Stop"

Set-Location -LiteralPath $PSScriptRoot

$branch = "main"
$linksFile = "links.txt"
$changedFile = "changed.txt"
$imgExts = @(".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp", ".tiff", ".svg", ".avif")

function ConvertTo-RawUrl([string]$relativePath) {
    $segments = $relativePath -split '[\\/]'
    $encoded = $segments | ForEach-Object {
        ([Uri]::EscapeDataString($_)).Replace('%28', '(').Replace('%29', ')')
    }
    return "https://raw.githubusercontent.com/cube-gif/NightTab/$branch/" + ($encoded -join '/')
}

function Push-Changes {
    git push origin $branch
    if ($LASTEXITCODE -eq 0) { return }
    Write-Host "Push отклонён — подтягиваю изменения с remote..."
    git pull --rebase --autostash origin $branch
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Не удалось синхронизироваться с remote (возможен конфликт)."
        exit 1
    }
    git push origin $branch
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Не удалось отправить изменения на remote."
        exit 1
    }
}

Write-Host "Синхронизация с remote..."
git pull --rebase --autostash origin $branch
if ($LASTEXITCODE -ne 0) {
    Write-Host "Не удалось синхронизироваться с remote (возможен конфликт). Решите его вручную."
    exit 1
}

$python = Get-Command py -ErrorAction SilentlyContinue
if ($python) {
    & $python.Source -3 "$PSScriptRoot\optimize.py"
} else {
    $python = Get-Command python -ErrorAction SilentlyContinue
    if (-not $python) {
        throw "Python не найден: он нужен для optimize.py (Pillow)."
    }
    & $python.Source "$PSScriptRoot\optimize.py"
}
if ($LASTEXITCODE -ne 0) {
    throw "Оптимизация изображений завершилась с ошибкой (код $LASTEXITCODE)."
}

function Update-Links {
    $files = Get-ChildItem -File |
        Where-Object { $imgExts -contains $_.Extension.ToLower() } |
        Sort-Object Name
    $links = $files | ForEach-Object { ConvertTo-RawUrl $_.Name }
    [System.IO.File]::WriteAllLines("$PSScriptRoot\$linksFile", @($links), (New-Object System.Text.UTF8Encoding($false)))
    return $files.Name
}

git add -A
$changedNames = @(git -c core.quotepath=false diff --cached --name-only --diff-filter=AM)
$status = git status --porcelain

if (-not $status) {
    $unpushed = @(git log --oneline "origin/$branch..HEAD")
    if ($unpushed.Count -gt 0) {
        Write-Host "Есть неотправленные коммиты — отправляю..."
        Push-Changes
    } else {
        Write-Host "Изменений нет."
    }
    exit 0
}

$realChanges = $status | Where-Object {
    $_ -notmatch "^..\s+$([regex]::Escape($linksFile))$" -and
    $_ -notmatch "^..\s+$([regex]::Escape($changedFile))$"
}

if ($realChanges) {
    $summary = git -c core.quotepath=false diff --cached --name-status |
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
    Push-Changes

    Write-Host "Закоммичено:"
    $summary | ForEach-Object { Write-Host "  $_" }
}

$allNames = Update-Links

$changedUrls = @($changedNames | Where-Object {
    (Test-Path -LiteralPath "$PSScriptRoot\$_") -and ($imgExts -contains [System.IO.Path]::GetExtension($_).ToLower())
} | ForEach-Object {
    ConvertTo-RawUrl $_
})

if ($changedUrls.Count -gt 0 -or -not (Test-Path -LiteralPath "$PSScriptRoot\$changedFile")) {
    [System.IO.File]::WriteAllLines("$PSScriptRoot\$changedFile", @($changedUrls), (New-Object System.Text.UTF8Encoding($false)))
}

git add -A
if (git status --porcelain) {
    git commit -m "Обновить списки ссылок"
    Push-Changes
}

Write-Host "Готово. Всего ссылок: $($allNames.Count), новых/изменённых: $($changedUrls.Count)"
