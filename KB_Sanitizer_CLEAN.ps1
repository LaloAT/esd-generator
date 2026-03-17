# ============================================================
# ESD KB Sanitizer - Step 2: CLEAN (v2)
# ============================================================
# 1. Reads each MHTML file
# 2. Extracts text content (strips HTML/CSS/images/base64)
# 3. Replaces credential patterns with [CREDENTIAL REMOVED]
# 4. Saves clean .txt files to SNOW_KB_CLEAN folder
#
# ORIGINAL FILES ARE NEVER MODIFIED.
# ============================================================

$BaseFolder = "$env:USERPROFILE\OneDrive - Oportun\Desktop\LLM-ESD-LALO"
$SourceFolder = "$BaseFolder\SNOW KB"
$CleanFolder = "$BaseFolder\SNOW_KB_CLEAN"

# --- TEXT EXTRACTION FUNCTION ---
function Get-CleanText {
    param([string]$RawContent)

    $Html = $RawContent
    if ($RawContent -match '(?s)(<html[^>]*>.*?</html>)') {
        $Html = $Matches[1]
    }

    $Html = $Html -replace '(?s)<script[^>]*>.*?</script>', ''
    $Html = $Html -replace '(?s)<style[^>]*>.*?</style>', ''
    $Html = $Html -replace '(?s)<head[^>]*>.*?</head>', ''
    $Html = $Html -replace 'data:[^"''>\s]+', ''
    $Html = $Html -replace '(?m)^Content-[^\n]+\n', ''
    $Html = $Html -replace '(?m)^------[^\n]+\n', ''

    $Text = $Html -replace '<br\s*/?>', "`n"
    $Text = $Text -replace '</?p[^>]*>', "`n"
    $Text = $Text -replace '</?div[^>]*>', "`n"
    $Text = $Text -replace '</?li[^>]*>', "`n"
    $Text = $Text -replace '</?tr[^>]*>', "`n"
    $Text = $Text -replace '</?td[^>]*>', ' '
    $Text = $Text -replace '</?h[1-6][^>]*>', "`n"
    $Text = $Text -replace '<[^>]+>', ''
    $Text = $Text -replace '&amp;', '&'
    $Text = $Text -replace '&lt;', '<'
    $Text = $Text -replace '&gt;', '>'
    $Text = $Text -replace '&quot;', '"'
    $Text = $Text -replace '&nbsp;', ' '
    $Text = $Text -replace '&#\d+;', ''

    $Lines = $Text -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 3 }
    $CleanLines = @()
    foreach ($Line in $Lines) {
        if ($Line -match '^\.' -and $Line -match '\{') { continue }
        if ($Line -match '\{[^}]+\}') { continue }
        if ($Line -match '[A-Za-z0-9+/=]{40,}' -and $Line -notmatch '\s') { continue }
        if ($Line -match '^Content-Type:') { continue }
        if ($Line -match '^MIME-') { continue }
        $CleanLines += $Line
    }

    return ($CleanLines -join "`n")
}

# --- CREDENTIAL PATTERNS ---
$Patterns = @(
    @{ Regex = '(?i)(password|contrase.a)\s*[:=]\s*\S+'; Replace = '[CREDENTIAL REMOVED]' }
    @{ Regex = '(?i)(pwd|pass)\s*[:=]\s*\S+'; Replace = '[CREDENTIAL REMOVED]' }
    @{ Regex = '(?i)(username|user name)\s*[:=]\s*\S+'; Replace = '[CREDENTIAL REMOVED]' }
    @{ Regex = '(?i)(credential|login)\s*[:=]\s*\S+'; Replace = '[CREDENTIAL REMOVED]' }
    @{ Regex = '(?i)(api[_\s]?key|secret[_\s]?key)\s*[:=]\s*\S+'; Replace = '[CREDENTIAL REMOVED]' }
    @{ Regex = '(?i)password\s+is\s+\S+'; Replace = '[CREDENTIAL REMOVED]' }
    @{ Regex = '(?i)use\s+password\s*:\s*\S+'; Replace = '[CREDENTIAL REMOVED]' }
    @{ Regex = '(?i)default\s+password\s*[:=]?\s*\S+'; Replace = '[CREDENTIAL REMOVED]' }
    @{ Regex = '(?i)temporary\s+password\s*[:=]?\s*\S+'; Replace = '[CREDENTIAL REMOVED]' }
    @{ Regex = '(?i)reset\s+password\s+to\s+\S+'; Replace = '[CREDENTIAL REMOVED]' }
)

# --- MAIN ---
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  ESD KB Sanitizer - CLEAN MODE v2" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $SourceFolder)) {
    Write-Host "ERROR: Source folder not found: $SourceFolder" -ForegroundColor Red
    exit
}

if (-not (Test-Path $CleanFolder)) {
    New-Item -ItemType Directory -Path $CleanFolder -Force | Out-Null
}

$Files = Get-ChildItem -Path $SourceFolder -Include "*.mhtml","*.mht","*.html" -Recurse -ErrorAction SilentlyContinue
Write-Host "Found $($Files.Count) files to process." -ForegroundColor Green
Write-Host "Extracting text and cleaning (this takes about 2-3 minutes)..." -ForegroundColor Yellow
Write-Host ""

$Processed = 0
$Cleaned = 0
$TotalReplacements = 0
$Errors = 0

foreach ($File in $Files) {
    $Processed++
    if ($Processed % 50 -eq 0) {
        Write-Host "  Processing $Processed / $($Files.Count)..." -ForegroundColor Gray
    }

    try {
        $RawContent = Get-Content -Path $File.FullName -Raw -ErrorAction SilentlyContinue
        if (-not $RawContent) { $Errors++; continue }

        # Extract clean text
        $Text = Get-CleanText -RawContent $RawContent

        if ($Text.Length -lt 20) { $Errors++; continue }

        # Sanitize
        $FileReplacements = 0
        foreach ($Pattern in $Patterns) {
            $MatchCount = ([regex]::Matches($Text, $Pattern.Regex)).Count
            if ($MatchCount -gt 0) {
                $Text = [regex]::Replace($Text, $Pattern.Regex, $Pattern.Replace)
                $FileReplacements += $MatchCount
                $TotalReplacements += $MatchCount
            }
        }

        if ($FileReplacements -gt 0) { $Cleaned++ }

        # Save as .txt
        $NewName = [System.IO.Path]::GetFileNameWithoutExtension($File.Name) + ".txt"
        $OutPath = Join-Path $CleanFolder $NewName
        $Text | Out-File -FilePath $OutPath -Encoding UTF8

    } catch {
        $Errors++
    }
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  CLEAN COMPLETE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Files processed:     $Processed" -ForegroundColor White
Write-Host "  Files sanitized:     $Cleaned (had credentials removed)" -ForegroundColor Yellow
Write-Host "  Total replacements:  $TotalReplacements" -ForegroundColor Yellow
Write-Host "  Errors/skipped:      $Errors" -ForegroundColor White
Write-Host ""
Write-Host "  Clean files saved to:" -ForegroundColor White
Write-Host "  $CleanFolder" -ForegroundColor Green
Write-Host ""
Write-Host "  Originals untouched in:" -ForegroundColor White
Write-Host "  $SourceFolder" -ForegroundColor Green
Write-Host ""
$CleanFiles = Get-ChildItem -Path $CleanFolder -Filter "*.txt" -ErrorAction SilentlyContinue
Write-Host "  Total clean .txt files: $($CleanFiles.Count)" -ForegroundColor Green
Write-Host ""
Write-Host "  NEXT: Zip SNOW_KB_CLEAN folder and upload to Colab." -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Cyan
