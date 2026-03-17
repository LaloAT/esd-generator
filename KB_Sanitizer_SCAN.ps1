# ============================================================
# ESD KB Sanitizer - Step 1: SCAN
# ============================================================
# This script ONLY SCANS your MHTML files for sensitive data.
# It does NOT modify anything. It generates a report.
# ============================================================

# --- CONFIGURATION ---
$BaseFolder = "$env:USERPROFILE\OneDrive - Oportun\Desktop\LLM-ESD-LALO"
$SourceFolder = "$BaseFolder\SNOW KB"
$ReportFile = "$BaseFolder\SCAN_REPORT.txt"

# --- PATTERNS TO DETECT ---
$Patterns = @(
    @{ Name = "PASSWORD_FIELD";    Regex = '(?i)(password|contrase.a|pwd|passw|pass\s*:)\s*[:=]?\s*.+' }
    @{ Name = "USERNAME_FIELD";    Regex = '(?i)(username|user\s*name|user\s*:?|login\s*:?|usuario)\s*[:=]\s*.+' }
    @{ Name = "CREDENTIAL_FIELD";  Regex = '(?i)(credential|cred\s*:)\s*[:=]?\s*.+' }
    @{ Name = "API_KEY";           Regex = '(?i)(api[_\s]?key|apikey|api[_\s]?token|secret[_\s]?key)\s*[:=]\s*.+' }
    @{ Name = "CONNECTION_STRING"; Regex = '(?i)(connection\s*string|conn\s*str)\s*[:=]\s*.+' }
    @{ Name = "SECRET";            Regex = '(?i)(secret|token)\s*[:=]\s*[^\s]{8,}' }
)

# --- SCAN ---
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  ESD KB Sanitizer - SCAN MODE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path $SourceFolder)) {
    Write-Host "ERROR: Folder not found: $SourceFolder" -ForegroundColor Red
    Write-Host "Update the SourceFolder path in the script." -ForegroundColor Yellow
    exit
}

$Files = Get-ChildItem -Path $SourceFolder -Include "*.mhtml","*.mht","*.html" -Recurse -ErrorAction SilentlyContinue

Write-Host "Found $($Files.Count) files to scan." -ForegroundColor Green
Write-Host "Scanning for sensitive data..." -ForegroundColor Yellow
Write-Host ""

$TotalFindings = 0
$FilesWithFindings = 0
$Report = @()
$Report += "============================================================"
$Report += "  ESD KB SANITIZER - SCAN REPORT"
$Report += "  Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$Report += "  Source: $SourceFolder"
$Report += "  Files scanned: $($Files.Count)"
$Report += "============================================================"
$Report += ""

$FileCount = 0
foreach ($File in $Files) {
    $FileCount++
    if ($FileCount % 50 -eq 0) {
        Write-Host "  Scanned $FileCount / $($Files.Count) files..." -ForegroundColor Gray
    }

    try {
        $Content = Get-Content -Path $File.FullName -Raw -ErrorAction SilentlyContinue
        if (-not $Content) { continue }

        $FileFindings = @()
        $LineNumber = 0

        foreach ($Line in ($Content -split "`n")) {
            $LineNumber++
            foreach ($Pattern in $Patterns) {
                if ($Line -match $Pattern.Regex) {
                    $CleanLine = $Line.Trim()
                    if ($CleanLine.Length -gt 80) {
                        $CleanLine = $CleanLine.Substring(0, 80) + "..."
                    }
                    $FileFindings += @{
                        Line = $LineNumber
                        Type = $Pattern.Name
                        Content = $CleanLine
                    }
                    $TotalFindings++
                }
            }
        }

        if ($FileFindings.Count -gt 0) {
            $FilesWithFindings++
            $ShortName = $File.Name
            $Report += "------------------------------------------------------------"
            $Report += "FILE: $ShortName"
            $Report += "  Findings: $($FileFindings.Count)"
            foreach ($Finding in $FileFindings) {
                $Report += "  [$($Finding.Type)] Line $($Finding.Line):"
                $Report += "    $($Finding.Content)"
            }
            $Report += ""
        }

    } catch {
        # Skip files that cant be read
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
$Report += ""
$Report += "  NEXT STEP: Review this report, then run the CLEAN script."
$Report += "============================================================"

# Save report
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
Write-Host "  Open the report and review what was found." -ForegroundColor White
Write-Host "  Then run KB_Sanitizer_CLEAN.ps1 to sanitize." -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Cyan
