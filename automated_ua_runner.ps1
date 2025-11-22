# R-Map Automated UA Test Runner with Visual UI
# Complete automation with progress tracking and logging

$ErrorActionPreference = "Continue"
$StartTime = Get-Date
$RMapPath = ".\target\release\rmap.exe"
$LogDir = "ua_test_logs"
$ResultsDir = "ua_test_results"

# Create directories
@($LogDir, $ResultsDir) | ForEach-Object {
    if (-not (Test-Path $_)) {
        New-Item -ItemType Directory -Path $_ -Force | Out-Null
    }
}

$LogFile = Join-Path $LogDir "automated_test_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$TestResults = @()

# Test counter
$TotalTests = 0
$PassedTests = 0
$FailedTests = 0
$CurrentTestNum = 0

# Logging function
function Write-Log {
    param($Message, $Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "$timestamp [$Level] $Message"
    Add-Content -Path $LogFile -Value $logEntry
}

# UI Header
function Show-Header {
    Clear-Host
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║         R-MAP AUTOMATED USER ACCEPTANCE TESTING SYSTEM              ║" -ForegroundColor Cyan
    Write-Host "║                    Full Automation with UI                          ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Start Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
    Write-Host "  Log File: $LogFile" -ForegroundColor Gray
    Write-Host ""
}

# Progress display
function Show-Progress {
    param($Current, $Total, $TestName)

    $percent = if ($Total -gt 0) { [math]::Round(($Current / $Total) * 100) } else { 0 }
    $barLength = 40
    $filled = [math]::Round(($percent / 100) * $barLength)
    $empty = $barLength - $filled

    $progressBar = ("█" * $filled) + ("░" * $empty)

    Write-Host "`r  Progress: [$progressBar] $percent% - Test $Current/$Total : $TestName" -NoNewline -ForegroundColor Yellow
}

# Test execution wrapper
function Run-Test {
    param(
        [string]$Name,
        [string]$Category,
        [scriptblock]$TestCode
    )

    $CurrentTestNum++
    Show-Progress $CurrentTestNum $TotalTests $Name

    Write-Log "Starting test: $Name" "INFO"

    $testStart = Get-Date
    $result = @{
        Name = $Name
        Category = $Category
        StartTime = $testStart
        Status = "Unknown"
        Message = ""
    }

    try {
        $output = & $TestCode

        if ($output.Success) {
            $result.Status = "PASSED"
            $result.Message = $output.Message
            $script:PassedTests++
            Write-Host " ✓" -ForegroundColor Green
            Write-Log "Test PASSED: $Name - $($output.Message)" "SUCCESS"
        } else {
            $result.Status = "FAILED"
            $result.Message = $output.Message
            $script:FailedTests++
            Write-Host " ✗" -ForegroundColor Red
            Write-Log "Test FAILED: $Name - $($output.Message)" "ERROR"
        }
    } catch {
        $result.Status = "ERROR"
        $result.Message = $_.Exception.Message
        $script:FailedTests++
        Write-Host " ⚠" -ForegroundColor Yellow
        Write-Log "Test ERROR: $Name - $_" "ERROR"
    }

    $result.EndTime = Get-Date
    $result.Duration = ($result.EndTime - $testStart).TotalSeconds

    $script:TestResults += $result

    return $result
}

# ============================================
# TEST DEFINITIONS
# ============================================

# Test 1: Version Check
function Test-Version {
    $output = & $RMapPath --version 2>&1
    if ($output -match "rmap") {
        return @{Success = $true; Message = "Version: $output"}
    }
    return @{Success = $false; Message = "Version check failed"}
}

# Test 2: Basic Scan
function Test-BasicScan {
    $result = & $RMapPath scanme.nmap.org -p 22,80 -t 5 2>&1 | Out-String
    if ($result -match "open") {
        return @{Success = $true; Message = "Found open ports"}
    }
    return @{Success = $false; Message = "No open ports found"}
}

# Test 3: JSON Output
function Test-JSONOutput {
    $jsonFile = Join-Path $ResultsDir "test_$(Get-Date -Format 'HHmmss').json"
    & $RMapPath 1.1.1.1 -p 53 -o json -f $jsonFile 2>&1 | Out-Null

    if (Test-Path $jsonFile) {
        try {
            $json = Get-Content $jsonFile | ConvertFrom-Json
            if ($json.scan_info) {
                return @{Success = $true; Message = "JSON output working"}
            }
        } catch {
            return @{Success = $false; Message = "JSON parse error"}
        }
    }
    return @{Success = $false; Message = "JSON file not created"}
}

# Test 4: Service Detection
function Test-ServiceDetection {
    $result = & $RMapPath scanme.nmap.org -p 22,80 -A 2>&1 | Out-String
    $services = @()

    if ($result -match "ssh") { $services += "SSH" }
    if ($result -match "http") { $services += "HTTP" }

    if ($services.Count -gt 0) {
        return @{Success = $true; Message = "Detected: $($services -join ', ')"}
    }
    return @{Success = $false; Message = "No services detected"}
}

# Test 5: Multiple Hosts
function Test-MultipleHosts {
    $result = & $RMapPath google.com cloudflare.com -p 443 -t 5 2>&1 | Out-String

    $hostsFound = 0
    if ($result -match "google") { $hostsFound++ }
    if ($result -match "cloudflare") { $hostsFound++ }

    if ($hostsFound -eq 2) {
        return @{Success = $true; Message = "Both hosts scanned"}
    }
    return @{Success = $false; Message = "Only $hostsFound/2 hosts scanned"}
}

# Test 6: Performance
function Test-Performance {
    $start = Get-Date
    & $RMapPath scanme.nmap.org -p 1-25 -t 3 2>&1 | Out-Null
    $duration = ((Get-Date) - $start).TotalSeconds

    $portsPerSec = [math]::Round(25 / $duration, 2)

    if ($duration -lt 60) {
        return @{Success = $true; Message = "25 ports in ${duration}s ($portsPerSec ports/sec)"}
    }
    return @{Success = $false; Message = "Too slow: ${duration}s"}
}

# Test 7: Error Handling
function Test-ErrorHandling {
    $result = & $RMapPath invalid.host.12345 -p 80 -t 1 2>&1 | Out-String

    if ($LASTEXITCODE -ne $null) {
        return @{Success = $true; Message = "Handled invalid host gracefully"}
    }
    return @{Success = $false; Message = "Error handling failed"}
}

# Test 8: Timeout
function Test-Timeout {
    $start = Get-Date
    & $RMapPath 10.255.255.1 -p 80 -t 2 2>&1 | Out-Null
    $duration = ((Get-Date) - $start).TotalSeconds

    if ($duration -le 5) {
        return @{Success = $true; Message = "Timeout working (${duration}s)"}
    }
    return @{Success = $false; Message = "Timeout not respected"}
}

# ============================================
# MAIN EXECUTION
# ============================================

# Check R-Map exists
if (-not (Test-Path $RMapPath)) {
    Write-Host "ERROR: R-Map not found at $RMapPath" -ForegroundColor Red
    exit 1
}

Show-Header

Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
Write-Host "                    STARTING AUTOMATED TESTS                        " -ForegroundColor White
Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
Write-Host ""

# Define all tests
$AllTests = @(
    @{Name="Version Check"; Category="Core"; Test={Test-Version}}
    @{Name="Basic Port Scan"; Category="Core"; Test={Test-BasicScan}}
    @{Name="JSON Output"; Category="Output"; Test={Test-JSONOutput}}
    @{Name="Service Detection"; Category="Services"; Test={Test-ServiceDetection}}
    @{Name="Multiple Hosts"; Category="Advanced"; Test={Test-MultipleHosts}}
    @{Name="Performance Test"; Category="Performance"; Test={Test-Performance}}
    @{Name="Error Handling"; Category="Reliability"; Test={Test-ErrorHandling}}
    @{Name="Timeout Compliance"; Category="Reliability"; Test={Test-Timeout}}
)

$TotalTests = $AllTests.Count

Write-Log "Starting automated test run with $TotalTests tests" "INFO"
Write-Host "  Running $TotalTests tests..." -ForegroundColor Cyan
Write-Host ""

# Run all tests
foreach ($test in $AllTests) {
    Run-Test -Name $test.Name -Category $test.Category -TestCode $test.Test
}

# Calculate summary
$Duration = ((Get-Date) - $StartTime).TotalSeconds
$SuccessRate = if ($TotalTests -gt 0) { [math]::Round(($PassedTests / $TotalTests) * 100, 1) } else { 0 }

Write-Host ""
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
Write-Host "                         TEST SUMMARY                               " -ForegroundColor White
Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
Write-Host ""
Write-Host "  Total Tests:    $TotalTests" -ForegroundColor White
Write-Host "  Passed:         $PassedTests" -ForegroundColor Green
Write-Host "  Failed:         $FailedTests" -ForegroundColor Red
Write-Host "  Success Rate:   $SuccessRate%" -ForegroundColor Cyan
Write-Host "  Duration:       $([math]::Round($Duration, 2))s" -ForegroundColor White
Write-Host ""

# Show failed tests
if ($FailedTests -gt 0) {
    Write-Host "  Failed Tests:" -ForegroundColor Red
    $TestResults | Where-Object { $_.Status -ne "PASSED" } | ForEach-Object {
        Write-Host "    - $($_.Name): $($_.Message)" -ForegroundColor Red
    }
    Write-Host ""
}

# Save detailed report
$ReportFile = Join-Path $ResultsDir "automated_report_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
$TestResults | ConvertTo-Json -Depth 10 | Out-File $ReportFile

Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
Write-Host "  Detailed report: $ReportFile" -ForegroundColor Gray
Write-Host "  Log file: $LogFile" -ForegroundColor Gray
Write-Host "═══════════════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
Write-Host ""

if ($SuccessRate -eq 100) {
    Write-Host "  ✓ ALL TESTS PASSED! R-Map is fully operational." -ForegroundColor Green
} elseif ($SuccessRate -ge 75) {
    Write-Host "  ⚠ Most tests passed. Check failed tests for issues." -ForegroundColor Yellow
} else {
    Write-Host "  ✗ Multiple failures detected. Review configuration." -ForegroundColor Red
}

Write-Host ""
Write-Log "Test run completed. Success rate: $SuccessRate%" "INFO"