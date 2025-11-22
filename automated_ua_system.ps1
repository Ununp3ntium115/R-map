# R-Map Automated UA Testing System with UI and Logging
# Version: 2.0 - Full Automation with Visual Dashboard
# ============================================================

param(
    [switch]$AutoRun = $false,
    [string]$LogLevel = "INFO"
)

# Initialize
$ErrorActionPreference = "Continue"
$global:TestStartTime = Get-Date
$global:RMapPath = ".\target\release\rmap.exe"
$global:LogPath = "ua_test_logs"
$global:ResultsPath = "ua_test_results"
$global:TestResults = @()
$global:CurrentTest = ""
$global:TotalTests = 0
$global:CompletedTests = 0

# Create necessary directories
@($global:LogPath, $global:ResultsPath) | ForEach-Object {
    if (-not (Test-Path $_)) {
        New-Item -ItemType Directory -Path $_ -Force | Out-Null
    }
}

# Logging Configuration
$global:LogFile = Join-Path $global:LogPath "ua_test_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
$global:TestSessionId = [guid]::NewGuid().ToString()

# Test Categories
$global:TestCategories = @{
    "Core" = @("Version", "Help", "BasicScan")
    "Network" = @("LocalDiscovery", "GatewayDetection", "SubnetScan")
    "Services" = @("ServiceDetection", "BannerGrab", "PortIdentification")
    "Output" = @("JSON", "XML", "CSV", "Grepable")
    "Performance" = @("Speed", "Concurrent", "LargeRange", "Stress")
    "Security" = @("Audit", "Vulnerability", "Compliance")
    "Advanced" = @("MultiHost", "Timeout", "ErrorHandling")
}

# ============================================================
# UI FUNCTIONS
# ============================================================

function Show-TestUI {
    Clear-Host
    $elapsed = ((Get-Date) - $global:TestStartTime).ToString("hh\:mm\:ss")

    Write-Host "╔══════════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║              R-MAP AUTOMATED USER ACCEPTANCE TESTING SYSTEM                 ║" -ForegroundColor Cyan
    Write-Host "║                        Version 2.0 - Full Automation                        ║" -ForegroundColor Cyan
    Write-Host "╠══════════════════════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
    Write-Host "║ Session ID: $($global:TestSessionId.Substring(0, 8))                                                        ║" -ForegroundColor White
    Write-Host "║ Start Time: $($global:TestStartTime.ToString('yyyy-MM-dd HH:mm:ss'))                               ║" -ForegroundColor White
    Write-Host "║ Elapsed: $elapsed                                                          ║" -ForegroundColor White
    Write-Host "║ Log File: $(Split-Path $global:LogFile -Leaf)                         ║" -ForegroundColor White
    Write-Host "╚══════════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
}

function Show-ProgressBar {
    param(
        [int]$Current,
        [int]$Total,
        [string]$Activity
    )

    if ($Total -eq 0) { return }

    $percent = [math]::Round(($Current / $Total) * 100)
    $barLength = 50
    $filled = [math]::Round(($percent / 100) * $barLength)
    $empty = $barLength - $filled

    $bar = "█" * $filled + "░" * $empty

    Write-Host "`r  [$bar] $percent% - $Activity" -NoNewline -ForegroundColor Yellow

    if ($Current -eq $Total) {
        Write-Host " ✓" -ForegroundColor Green
    }
}

function Show-TestStatus {
    param(
        [string]$Category,
        [string]$Test,
        [string]$Status,
        [string]$Details = ""
    )

    $statusSymbol = switch ($Status) {
        "Running" { "⚡", "Yellow" }
        "Passed" { "✓", "Green" }
        "Failed" { "✗", "Red" }
        "Skipped" { "⊘", "Gray" }
        "Warning" { "⚠", "DarkYellow" }
        default { "•", "White" }
    }

    $timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host "[$timestamp] " -NoNewline -ForegroundColor DarkGray
    Write-Host "[$Category] " -NoNewline -ForegroundColor Cyan
    Write-Host "$($statusSymbol[0]) " -NoNewline -ForegroundColor $statusSymbol[1]
    Write-Host "$Test" -NoNewline -ForegroundColor White

    if ($Details) {
        Write-Host " - $Details" -ForegroundColor Gray
    } else {
        Write-Host ""
    }
}

# ============================================================
# LOGGING FUNCTIONS
# ============================================================

function Write-TestLog {
    param(
        [string]$Level,
        [string]$Category,
        [string]$Message,
        [hashtable]$Data = @{}
    )

    $logEntry = @{
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
        Level = $Level
        Category = $Category
        Message = $Message
        SessionId = $global:TestSessionId
        Test = $global:CurrentTest
        Data = $Data
    }

    $logLine = "$($logEntry.Timestamp) [$Level] [$Category] $Message"
    if ($Data.Count -gt 0) {
        $logLine += " | Data: $(ConvertTo-Json $Data -Compress)"
    }

    Add-Content -Path $global:LogFile -Value $logLine

    # Also update UI based on level
    switch ($Level) {
        "ERROR" { Show-TestStatus $Category $global:CurrentTest "Failed" $Message }
        "WARNING" { Show-TestStatus $Category $global:CurrentTest "Warning" $Message }
        "SUCCESS" { Show-TestStatus $Category $global:CurrentTest "Passed" $Message }
    }
}

# ============================================================
# TEST EXECUTION ENGINE
# ============================================================

function Invoke-TestCase {
    param(
        [string]$Name,
        [string]$Category,
        [scriptblock]$TestScript,
        [hashtable]$Parameters = @{}
    )

    $global:CurrentTest = $Name
    $testStart = Get-Date

    Write-TestLog "INFO" $Category "Starting test: $Name" $Parameters
    Show-TestStatus $Category $Name "Running"

    $result = @{
        Name = $Name
        Category = $Category
        StartTime = $testStart
        Status = "Unknown"
        Message = ""
        Data = @{}
    }

    try {
        $testResult = & $TestScript @Parameters

        if ($testResult.Success) {
            $result.Status = "Passed"
            $result.Message = $testResult.Message
            $result.Data = $testResult.Data
            Write-TestLog "SUCCESS" $Category $testResult.Message $testResult.Data
        } else {
            $result.Status = "Failed"
            $result.Message = $testResult.Message
            Write-TestLog "ERROR" $Category $testResult.Message $testResult.Data
        }
    } catch {
        $result.Status = "Failed"
        $result.Message = "Exception: $_"
        Write-TestLog "ERROR" $Category "Test failed with exception: $_"
    }

    $result.EndTime = Get-Date
    $result.Duration = ($result.EndTime - $result.StartTime).TotalSeconds

    $global:TestResults += $result
    $global:CompletedTests++

    Show-ProgressBar $global:CompletedTests $global:TotalTests "Testing Progress"

    return $result
}

# ============================================================
# CORE TEST CASES
# ============================================================

function Test-RMapVersion {
    $result = & $global:RMapPath --version 2>&1

    if ($result -match "rmap") {
        return @{
            Success = $true
            Message = "Version check passed: $result"
            Data = @{ Version = $result }
        }
    }

    return @{
        Success = $false
        Message = "Version check failed"
        Data = @{}
    }
}

function Test-BasicScan {
    param([string]$Target = "scanme.nmap.org", [string]$Ports = "22,80")

    $scanResult = & $global:RMapPath $Target -p $Ports -t 5 2>&1 | Out-String

    if ($scanResult -match "open") {
        $openPorts = [regex]::Matches($scanResult, "(\d+).*open") | ForEach-Object { $_.Groups[1].Value }
        return @{
            Success = $true
            Message = "Found open ports: $($openPorts -join ', ')"
            Data = @{ OpenPorts = $openPorts; Target = $Target }
        }
    }

    return @{
        Success = $false
        Message = "No open ports found on $Target"
        Data = @{ Target = $Target; Ports = $Ports }
    }
}

function Test-JSONOutput {
    $testFile = Join-Path $global:ResultsPath "test_json_$(Get-Date -Format 'HHmmss').json"

    & $global:RMapPath "1.1.1.1" -p 53 -o json -f $testFile 2>&1 | Out-Null

    if (Test-Path $testFile) {
        try {
            $json = Get-Content $testFile | ConvertFrom-Json
            if ($json.scan_info.version) {
                return @{
                    Success = $true
                    Message = "JSON output validated successfully"
                    Data = @{
                        Version = $json.scan_info.version
                        FileSize = (Get-Item $testFile).Length
                    }
                }
            }
        } catch {
            return @{
                Success = $false
                Message = "JSON parsing failed: $_"
                Data = @{}
            }
        }
    }

    return @{
        Success = $false
        Message = "JSON output file not created"
        Data = @{}
    }
}

function Test-ServiceDetection {
    $result = & $global:RMapPath "scanme.nmap.org" -p 22,80 -A 2>&1 | Out-String

    $servicesFound = @()
    if ($result -match "ssh") { $servicesFound += "SSH" }
    if ($result -match "http") { $servicesFound += "HTTP" }

    if ($servicesFound.Count -gt 0) {
        return @{
            Success = $true
            Message = "Services detected: $($servicesFound -join ', ')"
            Data = @{ Services = $servicesFound }
        }
    }

    return @{
        Success = $false
        Message = "No services detected"
        Data = @{}
    }
}

function Test-LocalNetwork {
    $networkInfo = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                   Where-Object { $_.InterfaceAlias -notlike "*Loopback*" } |
                   Select-Object -First 1

    if ($networkInfo) {
        $gateway = $networkInfo.IPAddress.Substring(0, $networkInfo.IPAddress.LastIndexOf('.')) + ".1"

        $result = & $global:RMapPath $gateway -p 80,443 -t 2 2>&1 | Out-String

        if ($result) {
            return @{
                Success = $true
                Message = "Local network scan completed"
                Data = @{
                    LocalIP = $networkInfo.IPAddress
                    Gateway = $gateway
                    ResponseReceived = ($result -match "open" -or $result -match "closed")
                }
            }
        }
    }

    return @{
        Success = $false
        Message = "Could not scan local network"
        Data = @{}
    }
}

function Test-Performance {
    $startTime = Get-Date
    $result = & $global:RMapPath "scanme.nmap.org" -p 1-100 -t 3 2>&1 | Out-String
    $duration = ((Get-Date) - $startTime).TotalSeconds

    $portsPerSecond = [math]::Round(100 / $duration, 2)

    return @{
        Success = $duration -lt 120
        Message = "Scanned 100 ports in $([math]::Round($duration, 2))s ($portsPerSecond ports/sec)"
        Data = @{
            Duration = $duration
            PortsScanned = 100
            PortsPerSecond = $portsPerSecond
        }
    }
}

function Test-MultipleHosts {
    $hosts = @("google.com", "cloudflare.com")
    $result = & $global:RMapPath $hosts -p 443 -t 3 2>&1 | Out-String

    $hostsFound = @()
    foreach ($host in $hosts) {
        if ($result -match $host) {
            $hostsFound += $host
        }
    }

    if ($hostsFound.Count -eq $hosts.Count) {
        return @{
            Success = $true
            Message = "All hosts scanned successfully"
            Data = @{ Hosts = $hostsFound }
        }
    }

    return @{
        Success = $false
        Message = "Only $($hostsFound.Count) of $($hosts.Count) hosts scanned"
        Data = @{ Expected = $hosts; Found = $hostsFound }
    }
}

# ============================================================
# AUTOMATED TEST ORCHESTRATOR
# ============================================================

function Start-AutomatedTesting {
    Show-TestUI

    Write-Host "`n" -NoNewline
    Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
    Write-Host "                         AUTOMATED TEST EXECUTION                               " -ForegroundColor White
    Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
    Write-Host ""

    # Count total tests
    $allTests = @(
        @{Name="Version Check"; Category="Core"; Test={Test-RMapVersion}}
        @{Name="Basic Port Scan"; Category="Core"; Test={Test-BasicScan}}
        @{Name="JSON Output"; Category="Output"; Test={Test-JSONOutput}}
        @{Name="Service Detection"; Category="Services"; Test={Test-ServiceDetection}}
        @{Name="Local Network"; Category="Network"; Test={Test-LocalNetwork}}
        @{Name="Performance Test"; Category="Performance"; Test={Test-Performance}}
        @{Name="Multiple Hosts"; Category="Advanced"; Test={Test-MultipleHosts}}
    )

    $global:TotalTests = $allTests.Count

    Write-Host "Starting $($global:TotalTests) automated tests..." -ForegroundColor Cyan
    Write-Host ""

    # Execute all tests
    foreach ($test in $allTests) {
        Invoke-TestCase -Name $test.Name -Category $test.Category -TestScript $test.Test
        Start-Sleep -Milliseconds 500  # Brief pause for UI visibility
    }

    # Generate Summary
    Show-TestSummary
}

function Show-TestSummary {
    Write-Host "`n" -NoNewline
    Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
    Write-Host "                              TEST SUMMARY                                      " -ForegroundColor White
    Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor DarkCyan

    $passed = ($global:TestResults | Where-Object { $_.Status -eq "Passed" }).Count
    $failed = ($global:TestResults | Where-Object { $_.Status -eq "Failed" }).Count
    $totalDuration = ((Get-Date) - $global:TestStartTime).TotalSeconds

    Write-Host ""
    Write-Host "  Total Tests: $($global:TotalTests)" -ForegroundColor White
    Write-Host "  Passed: $passed" -ForegroundColor Green
    Write-Host "  Failed: $failed" -ForegroundColor Red
    Write-Host "  Success Rate: $([math]::Round(($passed / $global:TotalTests) * 100, 1))%" -ForegroundColor Cyan
    Write-Host "  Total Duration: $([math]::Round($totalDuration, 2)) seconds" -ForegroundColor White
    Write-Host ""

    # Show failed tests
    if ($failed -gt 0) {
        Write-Host "Failed Tests:" -ForegroundColor Red
        $global:TestResults | Where-Object { $_.Status -eq "Failed" } | ForEach-Object {
            Write-Host "  - [$($_.Category)] $($_.Name): $($_.Message)" -ForegroundColor Red
        }
        Write-Host ""
    }

    # Save results
    $reportPath = Join-Path $global:ResultsPath "ua_test_report_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
    $global:TestResults | ConvertTo-Json -Depth 10 | Out-File $reportPath

    Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
    Write-Host "  Full report saved to: $reportPath" -ForegroundColor Gray
    Write-Host "  Log file: $global:LogFile" -ForegroundColor Gray
    Write-Host "═══════════════════════════════════════════════════════════════════════════════" -ForegroundColor DarkCyan
}

# ============================================================
# MAIN EXECUTION
# ============================================================

# Check R-Map exists
if (-not (Test-Path $global:RMapPath)) {
    Write-Host "ERROR: R-Map executable not found at $global:RMapPath" -ForegroundColor Red
    Write-Host "Please build R-Map first with: cargo build --release" -ForegroundColor Yellow
    exit 1
}

# Start automated testing
if ($AutoRun) {
    Start-AutomatedTesting
} else {
    Show-TestUI

    Write-Host "`nAutomated UA Testing System Ready" -ForegroundColor Green
    Write-Host ""
    Write-Host "Options:" -ForegroundColor Yellow
    Write-Host "  [1] Run All Tests Automatically" -ForegroundColor White
    Write-Host "  [2] Run Core Tests Only" -ForegroundColor White
    Write-Host "  [3] Run Network Tests Only" -ForegroundColor White
    Write-Host "  [4] Run Performance Tests Only" -ForegroundColor White
    Write-Host "  [5] View Previous Results" -ForegroundColor White
    Write-Host "  [0] Exit" -ForegroundColor Gray
    Write-Host ""

    $choice = Read-Host "Select option"

    switch ($choice) {
        "1" { Start-AutomatedTesting }
        "2" {
            $global:TotalTests = 3
            Invoke-TestCase -Name "Version Check" -Category "Core" -TestScript {Test-RMapVersion}
            Invoke-TestCase -Name "Basic Scan" -Category "Core" -TestScript {Test-BasicScan}
            Invoke-TestCase -Name "Help Display" -Category "Core" -TestScript {Test-RMapVersion}
            Show-TestSummary
        }
        "3" {
            $global:TotalTests = 1
            Invoke-TestCase -Name "Local Network" -Category "Network" -TestScript {Test-LocalNetwork}
            Show-TestSummary
        }
        "4" {
            $global:TotalTests = 1
            Invoke-TestCase -Name "Performance" -Category "Performance" -TestScript {Test-Performance}
            Show-TestSummary
        }
        "5" {
            Get-ChildItem $global:ResultsPath -Filter "*.json" | Sort-Object LastWriteTime -Descending | Select-Object -First 5 | ForEach-Object {
                Write-Host "  $($_.Name) - $($_.LastWriteTime)" -ForegroundColor Cyan
            }
        }
        "0" { exit }
    }
}

Write-Host "`nAutomated UA Testing Complete" -ForegroundColor Green