# R-Map UA Testing Suite
# Comprehensive User Acceptance Testing Script for Windows

param(
    [Parameter(Mandatory=$false)]
    [string]$BinaryPath = "target\release\rmap.exe",

    [Parameter(Mandatory=$false)]
    [switch]$Docker = $false,

    [Parameter(Mandatory=$false)]
    [string]$OutputDir = "ua_test_results"
)

# Color output functions
function Write-Success { param($msg) Write-Host "✅ $msg" -ForegroundColor Green }
function Write-Error { param($msg) Write-Host "❌ $msg" -ForegroundColor Red }
function Write-Info { param($msg) Write-Host "ℹ️  $msg" -ForegroundColor Cyan }
function Write-Section { param($msg) Write-Host "`n=== $msg ===" -ForegroundColor Yellow }

# Create output directory
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

# Initialize test results
$script:TestResults = @()
$script:PassCount = 0
$script:FailCount = 0
$script:TotalTime = 0

function Test-Command {
    param(
        [string]$TestName,
        [string]$Command,
        [string]$ExpectedPattern = "",
        [int]$ExpectedExitCode = 0
    )

    Write-Info "Running: $TestName"
    $startTime = Get-Date

    try {
        if ($Docker) {
            $fullCmd = "docker run --rm rmap:local-test $Command"
        } else {
            $fullCmd = "$BinaryPath $Command"
        }

        $output = Invoke-Expression $fullCmd 2>&1
        $exitCode = $LASTEXITCODE
        $duration = ((Get-Date) - $startTime).TotalSeconds

        $outputFile = Join-Path $OutputDir "$($TestName -replace '[^a-zA-Z0-9]', '_').txt"
        $output | Out-File -FilePath $outputFile -Encoding UTF8

        $passed = $true
        $reason = ""

        # Check exit code
        if ($exitCode -ne $ExpectedExitCode) {
            $passed = $false
            $reason = "Exit code $exitCode (expected $ExpectedExitCode)"
        }

        # Check pattern if specified
        if ($passed -and $ExpectedPattern -and $output -notmatch $ExpectedPattern) {
            $passed = $false
            $reason = "Pattern '$ExpectedPattern' not found in output"
        }

        # Record result
        $result = [PSCustomObject]@{
            TestName = $TestName
            Passed = $passed
            Duration = [math]::Round($duration, 2)
            ExitCode = $exitCode
            Reason = $reason
            OutputFile = $outputFile
        }

        $script:TestResults += $result
        if ($passed) {
            $script:PassCount++
            Write-Success "$TestName (${duration}s)"
        } else {
            $script:FailCount++
            Write-Error "$TestName - $reason"
        }

        $script:TotalTime += $duration

    } catch {
        $script:FailCount++
        Write-Error "$TestName - Exception: $_"
        $script:TestResults += [PSCustomObject]@{
            TestName = $TestName
            Passed = $false
            Duration = 0
            ExitCode = -1
            Reason = "Exception: $_"
            OutputFile = ""
        }
    }
}

# ==============================================================================
# TEST SUITE
# ==============================================================================

Write-Section "R-Map UA Test Suite Starting"
Write-Info "Binary: $BinaryPath"
Write-Info "Docker Mode: $Docker"
Write-Info "Output Directory: $OutputDir"

# Verify binary exists (if not Docker mode)
if (-not $Docker -and -not (Test-Path $BinaryPath)) {
    Write-Error "Binary not found at: $BinaryPath"
    Write-Info "Please build the project first with: cargo build --release"
    exit 1
}

# ==============================================================================
# BASIC FUNCTIONALITY TESTS
# ==============================================================================

Write-Section "Basic Functionality Tests"

Test-Command `
    -TestName "01-version-check" `
    -Command "--version" `
    -ExpectedPattern "rmap"

Test-Command `
    -TestName "02-help-output" `
    -Command "--help" `
    -ExpectedPattern "Usage:"

# ==============================================================================
# SCAN TESTS
# ==============================================================================

Write-Section "Scan Tests"

Test-Command `
    -TestName "03-localhost-basic" `
    -Command "127.0.0.1 -p 80" `
    -ExpectedPattern "(open|closed)"

Test-Command `
    -TestName "04-localhost-multiple-ports" `
    -Command "127.0.0.1 -p 80,443,22,3389" `
    -ExpectedPattern "scan report"

Test-Command `
    -TestName "05-localhost-port-range" `
    -Command "127.0.0.1 -p 80-85" `
    -ExpectedPattern "scan"

Test-Command `
    -TestName "06-google-dns" `
    -Command "8.8.8.8 -p 53" `
    -ExpectedPattern "8.8.8.8"

# ==============================================================================
# OUTPUT FORMAT TESTS
# ==============================================================================

Write-Section "Output Format Tests"

Test-Command `
    -TestName "07-json-output" `
    -Command "127.0.0.1 -p 80 -o json" `
    -ExpectedPattern '[\{].*[\}]'

Test-Command `
    -TestName "08-xml-output" `
    -Command "127.0.0.1 -p 80 -o xml" `
    -ExpectedPattern "<?xml"

Test-Command `
    -TestName "09-grepable-output" `
    -Command "127.0.0.1 -p 80 -o grepable" `
    -ExpectedPattern "Host:"

# ==============================================================================
# ADVANCED FEATURES
# ==============================================================================

Write-Section "Advanced Features"

Test-Command `
    -TestName "10-service-detection" `
    -Command "127.0.0.1 -p 80,443 -A" `
    -ExpectedPattern "scan"

Test-Command `
    -TestName "11-verbose-mode" `
    -Command "127.0.0.1 -p 80 -v" `
    -ExpectedPattern "scan"

Test-Command `
    -TestName "12-timeout-setting" `
    -Command "127.0.0.1 -p 80 -t 5" `
    -ExpectedPattern "scan"

# ==============================================================================
# FILE OUTPUT TESTS
# ==============================================================================

Write-Section "File Output Tests"

$testFile = Join-Path $OutputDir "test-output.json"
Test-Command `
    -TestName "13-file-output" `
    -Command "127.0.0.1 -p 80 -o json -f `"$testFile`"" `
    -ExpectedPattern "scan"

if (Test-Path $testFile) {
    Write-Success "File output created successfully"
} else {
    Write-Error "File output was not created"
}

# ==============================================================================
# NETWORK TESTS
# ==============================================================================

Write-Section "Network Target Tests"

Test-Command `
    -TestName "14-hostname-resolution" `
    -Command "localhost -p 80" `
    -ExpectedPattern "(127.0.0.1|::1)"

Test-Command `
    -TestName "15-public-host-scan" `
    -Command "scanme.nmap.org -p 80,22" `
    -ExpectedPattern "scan"

# ==============================================================================
# ERROR HANDLING TESTS
# ==============================================================================

Write-Section "Error Handling Tests"

Test-Command `
    -TestName "16-invalid-target" `
    -Command "invalid.host.that.does.not.exist.local -p 80" `
    -ExpectedExitCode 1

Test-Command `
    -TestName "17-invalid-port" `
    -Command "127.0.0.1 -p 99999" `
    -ExpectedExitCode 1

# ==============================================================================
# RESULTS SUMMARY
# ==============================================================================

Write-Section "Test Results Summary"

$totalTests = $script:PassCount + $script:FailCount
$passRate = if ($totalTests -gt 0) { [math]::Round(($script:PassCount / $totalTests) * 100, 1) } else { 0 }

Write-Host ""
Write-Host "Total Tests: $totalTests" -ForegroundColor White
Write-Host "Passed: $script:PassCount" -ForegroundColor Green
Write-Host "Failed: $script:FailCount" -ForegroundColor Red
Write-Host "Pass Rate: $passRate%" -ForegroundColor $(if ($passRate -ge 80) { "Green" } elseif ($passRate -ge 60) { "Yellow" } else { "Red" })
Write-Host "Total Time: $([math]::Round($script:TotalTime, 2))s" -ForegroundColor White

# Generate HTML Report
$htmlReport = @"
<!DOCTYPE html>
<html>
<head>
    <title>R-Map UA Test Results</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .header { background: #2c3e50; color: white; padding: 20px; border-radius: 5px; }
        .summary { background: white; padding: 20px; margin: 20px 0; border-radius: 5px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .summary-stat { display: inline-block; margin: 0 20px; }
        .pass { color: #27ae60; font-weight: bold; }
        .fail { color: #e74c3c; font-weight: bold; }
        table { width: 100%; background: white; border-collapse: collapse; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        th { background: #34495e; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ecf0f1; }
        tr:hover { background: #f8f9fa; }
        .status-pass { color: #27ae60; }
        .status-fail { color: #e74c3c; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🦀 R-Map UA Test Results</h1>
        <p>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
        <p>Binary: $BinaryPath | Docker: $Docker</p>
    </div>

    <div class="summary">
        <div class="summary-stat">
            <h3>Total Tests</h3>
            <p style="font-size: 24px;">$totalTests</p>
        </div>
        <div class="summary-stat">
            <h3>Passed</h3>
            <p class="pass" style="font-size: 24px;">$($script:PassCount)</p>
        </div>
        <div class="summary-stat">
            <h3>Failed</h3>
            <p class="fail" style="font-size: 24px;">$($script:FailCount)</p>
        </div>
        <div class="summary-stat">
            <h3>Pass Rate</h3>
            <p style="font-size: 24px;">$passRate%</p>
        </div>
        <div class="summary-stat">
            <h3>Total Time</h3>
            <p style="font-size: 24px;">$([math]::Round($script:TotalTime, 2))s</p>
        </div>
    </div>

    <table>
        <thead>
            <tr>
                <th>Test Name</th>
                <th>Status</th>
                <th>Duration (s)</th>
                <th>Exit Code</th>
                <th>Details</th>
            </tr>
        </thead>
        <tbody>
"@

foreach ($result in $script:TestResults) {
    $statusClass = if ($result.Passed) { "status-pass" } else { "status-fail" }
    $statusText = if ($result.Passed) { "✅ PASS" } else { "❌ FAIL" }
    $details = if ($result.Reason) { $result.Reason } else { "OK" }

    $htmlReport += @"
            <tr>
                <td>$($result.TestName)</td>
                <td class="$statusClass">$statusText</td>
                <td>$($result.Duration)</td>
                <td>$($result.ExitCode)</td>
                <td>$details</td>
            </tr>
"@
}

$htmlReport += @"
        </tbody>
    </table>
</body>
</html>
"@

$htmlReportPath = Join-Path $OutputDir "test_results.html"
$htmlReport | Out-File -FilePath $htmlReportPath -Encoding UTF8

Write-Host ""
Write-Info "HTML Report: $htmlReportPath"
Write-Info "Output Directory: $OutputDir"

# Export to JSON
$jsonReportPath = Join-Path $OutputDir "test_results.json"
$script:TestResults | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonReportPath -Encoding UTF8
Write-Info "JSON Report: $jsonReportPath"

# Exit with appropriate code
if ($script:FailCount -eq 0) {
    Write-Success "`nAll tests passed! 🎉"
    exit 0
} else {
    Write-Error "`nSome tests failed. Review the output files for details."
    exit 1
}
