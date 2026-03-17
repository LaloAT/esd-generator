# ============================================================
# ESD KB Sanitizer - Step 1: SCAN (v2)
# ============================================================
# Extracts TEXT from MHTML first, then scans for credentials.
# Avoids false positives from HTML/CSS/base64 image data.
# Does NOT modify anything. Generates a report.
# ============================================================

$BaseFolder = "$env:USERPROFILE\OneDrive - Oportun\Desktop\LLM-ESD-LALO"
$SourceFolder = "$BaseFolder\SNOW KB"
$ReportFile = "$BaseFolder\SCAN_REPORT.txt"

# --- TEXT EXTRACTION FUNCTION ---
function Get-CleanText {
    param([string]$RawContent)

    # Find HTML portion
    $Html = $RawContent
    if ($RawContent -match '(?s)(<html[^>]*>.*?</html>)') {
        $Html = $Matches[1]
    }

    # Remove encoded content (base64 images, CSS, scripts)
    $Html = $Html -replace '(?s)<script[^>]*>.*?</script>', ''
    $Html = $Html -replace '(?s)<style[^>]*>.*?</style>', ''
    $Html = $Html -replace '(?s)<head[^>]*>.*?</head>', ''
    # Remove base64 data
    $Html = $Html -replace 'data:[^"''>\s]+', ''
    # Remove MIME boundaries and headers
    $Html = $Html -replace '(?m)^Content-[^\n]+\n', ''
    $Html = $Html -replace '(?m)^------[^\n]+\n', ''

    # Convert HTML to text
    $Text = $Html -replace '<br\s*/?>', "`n"
    $Text = $Text -replace '</?p[^>]*>', "`n"
    $Text = $Text -replace '</?div[^>]*>', "`n"
    $Text = $Text -replace '</?li[^>]*>', "`n"
    $Text = $Text -replace '</?tr[^>]*>', "`n"
    $Text = $Text -replace '</?td[^>]*>', ' '
    $Text = $Text -replace '</?h[1-6][^>]*>', "`n"
    # Remove all remaining HTML tags
    $Text = $Text -replace '<[^>]+>', ''
    # Decode entities
    $Text = $Text -replace '&amp;', '&'
    $Text = $Text -replace '&lt;', '<'
    $Text = $Text -replace '&gt;', '>'
    $Text = $Text -replace '&quot;', '"'
    $Text = $Text -replace '&nbsp;', ' '
    $Text = $Text -replace '&#\d+;', ''

    # Clean up
    $Lines = $Text -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 3 }
    # Remove lines that look like code/CSS (contain { } or very long strings without spaces)
    $CleanLines = @()
    foreach ($Line in $Lines) {
        # Skip CSS-like lines
        if ($Line -match '^\.' -and $Line -match '\{') { continue }
        if ($Line -match '\{[^}]+\}') { continue }
        # Skip base64-like strings (40+ chars without spaces)
        if ($Line -match '[A-Za-z0-9+/=]{40,}' -and $Line -notmatch '\s') { continue }
        # Skip MIME headers
        if ($Line -match '^Content-Type:') { continue }
        if ($Line -match '^MIME-') { continue }
        $CleanLines += $Line
    }

    return ($CleanLines -join "`n")
}

# --- PATTERNS TO DETECT (more specific to avoid false positives) ---
$Patterns = @(
    @{ Name = "PASSWORD"; Regex = '(?i)(password|contrase.a)\s*[:=]\s*\S+' }
    @{ Name = "PASSWORD"; Regex = '(?i)(pwd|pass)\s*[:=]\s*\S+' }
    @{ Name = "USERNAME"; Regex = '(?i)(username|user name)\s*[:=]\s*\S+' }
    @{ Name = "CREDENTIAL"; Regex = '(?i)(credential|login)\s*[:=]\s*\S+' }
    @{ Name = "API_KEY"; Regex = '(?i)(api[_\s]?key|secret[_\s]?key)\s*[:=]\s*\S+' }
    @{ Name = "GENERIC_PASS"; Regex = '(?i)password\s+is\s+\S+' }
    @{ Name = "GENERIC_PASS"; Regex = '(?i)use\s+password\s*:\s*\S+' }
    @{ Name = "GENERIC_PASS"; Regex = '(?i)default\s+password\s*[:=]?\s*\S+' }
    @{ Name = "GENERIC_PASS"; Regex = '(?i)temporary\s+password\s*[:=]?\s*\S+' }
    @{ Name = "GENERIC_PASS"; Regex = '(?i)reset\s+password\s+to\s+\S+' }
)

# --- SCAN ---
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  ESD KB Sanitizer - SCAN MODE v2" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $SourceFolder)) {
    Write-Host "ERROR: Folder not found: $SourceFolder" -ForegroundColor Red
    exit
}

$Files = Get-ChildItem -Path $SourceFolder -Include "*.mhtml","*.mht","*.html" -Recurse -ErrorAction SilentlyContinue
Write-Host "Found $($Files.Count) files to scan." -ForegroundColor Green
Write-Host "Extracting text and scanning (this takes about 1-2 minutes)..." -ForegroundColor Yellow
Write-Host ""

$TotalFindings = 0
$FilesWithFindings = 0
$Report = @()
$Report += "============================================================"
$Report += "  ESD KB SANITIZER - SCAN REPORT v2"
$Report += "  Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$Report += "  Source: $SourceFolder"
$Report += "  Files scanned: $($Files.Count)"
$Report += "============================================================"
$Report += ""

$FileCount = 0
foreach ($File in $Files) {
    $FileCount++
    if ($FileCount % 100 -eq 0) {
        Write-Host "  Processed $FileCount / $($Files.Count) files..." -ForegroundColor Gray
    }

    try {
        $RawContent = Get-Content -Path $File.FullName -Raw -ErrorAction SilentlyContinue
        if (-not $RawContent) { continue }

        # Extract clean text first
        $CleanText = Get-CleanText -RawContent $RawContent

        $FileFindings = @()
        $LineNumber = 0

        foreach ($Line in ($CleanText -split "`n")) {
            $LineNumber++
            foreach ($Pattern in $Patterns) {
                if ($Line -match $Pattern.Regex) {
                    $DisplayLine = $Line.Trim()
                    if ($DisplayLine.Length -gt 100) {
                        $DisplayLine = $DisplayLine.Substring(0, 100) + "..."
                    }
                    $FileFindings += @{
                        Line = $LineNumber
                        Type = $Pattern.Name
                        Content = $DisplayLine
                    }
                    $TotalFindings++
                }
            }
        }

        if ($FileFindings.Count -gt 0) {
            $FilesWithFindings++
            $Report += "------------------------------------------------------------"
            $Report += "FILE: $($File.Name)"
            $Report += "  Findings: $($FileFindings.Count)"
            foreach ($Finding in $FileFindings) {
                $Report += "  [$($Finding.Type)] Line $($Finding.Line):"
                $Report += "    $($Finding.Content)"
            }
            $Report += ""
        }

    } catch {
        # Skip unreadable files
    }
}

# --- SUMMARY ---
$Report += "============================================================"
$Report += "  SUMMARY"
$Report += "============================================================"
$Report += "  Total files scanned:        $($Files.Count)"
$Report += "  Files with findings:         $FilesWithFindings"
$Report += "  Total findings:              $TotalFindings"
$Report += "  Files clean (no findings):   $($Files.Count - $FilesWithFindings)"
$Report += "============================================================"

$Report | Out-File -FilePath $ReportFile -Encoding UTF8

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  SCAN COMPLETE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Files scanned:      $($Files.Count)" -ForegroundColor White
Write-Host "  Files with issues:  $FilesWithFindings" -ForegroundColor Yellow
Write-Host "  Total findings:     $TotalFindings" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Report saved to:" -ForegroundColor White
Write-Host "  $ReportFile" -ForegroundColor Green
Write-Host ""
Write-Host "  Review the report, then run KB_Sanitizer_CLEAN.ps1" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Cyan
