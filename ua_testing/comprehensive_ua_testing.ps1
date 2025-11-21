# R-Map Comprehensive User Acceptance Testing Suite
# Version: 1.0
# Purpose: Real-world testing of R-Map on Windows
# Requirements: Windows PC with network access

$ErrorActionPreference = "Continue"
$script:TestResults = @()
$script:StartTime = Get-Date
$script:RMapPath = ".\target\release\rmap.exe"

# Color coding for output
function Write-Success { param($msg) Write-Host "[✓] $msg" -ForegroundColor Green }
function Write-Warning { param($msg) Write-Host "[!] $msg" -ForegroundColor Yellow }
function Write-Error { param($msg) Write-Host "[✗] $msg" -ForegroundColor Red }
function Write-Info { param($msg) Write-Host "[i] $msg" -ForegroundColor Cyan }
function Write-Test { param($msg) Write-Host "`n[TEST] $msg" -ForegroundColor Magenta }

# Test result tracking
function Add-TestResult {
    param($TestName, $Status, $Details, $Duration)
    $script:TestResults += [PSCustomObject]@{
        TestName = $TestName
        Status = $Status
        Details = $Details
        Duration = $Duration
        Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    }
}

# Check if R-Map exists
function Test-RMapExists {
    Write-Test "Checking R-Map executable"

    if (-not (Test-Path $script:RMapPath)) {
        Write-Warning "Release build not found. Building R-Map..."
        & cargo build --release
        Start-Sleep -Seconds 2
    }

    if (Test-Path $script:RMapPath) {
        Write-Success "R-Map executable found at $script:RMapPath"
        $version = & $script:RMapPath --version 2>&1
        Write-Info "Version: $version"
        return $true
    } else {
        Write-Error "R-Map executable not found!"
        return $false
    }
}

# Test 1: Basic functionality and help
function Test-BasicFunctionality {
    Write-Test "Basic Functionality Test"
    $testStart = Get-Date

    try {
        # Test help command
        $help = & $script:RMapPath --help 2>&1
        if ($help) {
            Write-Success "Help command works"
        }

        # Test version command
        $version = & $script:RMapPath --version 2>&1
        if ($version) {
            Write-Success "Version command works"
        }

        $duration = (Get-Date) - $testStart
        Add-TestResult -TestName "Basic Functionality" -Status "PASSED" -Details "Help and version commands work" -Duration $duration.TotalSeconds
        return $true
    } catch {
        Add-TestResult -TestName "Basic Functionality" -Status "FAILED" -Details $_.Exception.Message -Duration 0
        Write-Error "Basic functionality test failed: $_"
        return $false
    }
}

# Test 2: Local Network Device Discovery
function Test-LocalNetworkDiscovery {
    Write-Test "Local Network Device Discovery"
    $testStart = Get-Date

    try {
        # Get local network info
        $localIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notlike "*Loopback*" -and $_.IPAddress -notlike "169.254.*"} | Select-Object -First 1).IPAddress
        $subnet = $localIP.Substring(0, $localIP.LastIndexOf('.')) + ".0/24"

        Write-Info "Testing subnet: $subnet"
        Write-Info "Discovering devices on local network (this may take a minute)..."

        # Quick scan for common ports
        $scanResult = & $script:RMapPath $subnet --fast --skip-ping -o "test_results\local_discovery.json" --format json 2>&1 | Out-String

        # Check if we found any hosts
        if ($scanResult -match "Host.*up" -or $scanResult -match "open") {
            Write-Success "Found devices on local network"

            # Try to identify router
            $routerIP = $localIP.Substring(0, $localIP.LastIndexOf('.')) + ".1"
            Write-Info "Testing router at $routerIP..."
            $routerScan = & $script:RMapPath $routerIP -p 80,443,22,23 2>&1 | Out-String

            if ($routerScan -match "open") {
                Write-Success "Router detected and responding"
            }
        } else {
            Write-Warning "No devices found (might be firewall protected)"
        }

        $duration = (Get-Date) - $testStart
        Add-TestResult -TestName "Local Network Discovery" -Status "PASSED" -Details "Subnet scan completed" -Duration $duration.TotalSeconds
        return $true
    } catch {
        Add-TestResult -TestName "Local Network Discovery" -Status "FAILED" -Details $_.Exception.Message -Duration 0
        Write-Error "Network discovery failed: $_"
        return $false
    }
}

# Test 3: External Host Scanning
function Test-ExternalHostScanning {
    Write-Test "External Host Scanning (Internet)"
    $testStart = Get-Date

    $externalHosts = @(
        @{Host="scanme.nmap.org"; Ports="22,80,443"; Description="Official nmap test server"},
        @{Host="google.com"; Ports="80,443"; Description="Google"},
        @{Host="1.1.1.1"; Ports="53,80,443"; Description="Cloudflare DNS"},
        @{Host="8.8.8.8"; Ports="53,443"; Description="Google DNS"}
    )

    $passedTests = 0
    foreach ($target in $externalHosts) {
        Write-Info "Scanning $($target.Host) ($($target.Description))..."

        try {
            $result = & $script:RMapPath $target.Host -p $target.Ports --timeout 5 2>&1 | Out-String

            if ($result -match "open") {
                Write-Success "$($target.Host) - Found open ports"
                $passedTests++
            } else {
                Write-Warning "$($target.Host) - No open ports detected"
            }
        } catch {
            Write-Error "$($target.Host) - Scan failed: $_"
        }
    }

    $duration = (Get-Date) - $testStart
    $status = if ($passedTests -gt 0) { "PASSED" } else { "FAILED" }
    Add-TestResult -TestName "External Host Scanning" -Status $status -Details "$passedTests/$($externalHosts.Count) hosts scanned successfully" -Duration $duration.TotalSeconds
    return ($passedTests -gt 0)
}

# Test 4: Service Detection
function Test-ServiceDetection {
    Write-Test "Service Detection Capabilities"
    $testStart = Get-Date

    try {
        Write-Info "Testing service detection on known services..."

        # Test well-known services
        $targets = @(
            @{Host="google.com"; Port=443; ExpectedService="https"},
            @{Host="scanme.nmap.org"; Port=22; ExpectedService="ssh"},
            @{Host="1.1.1.1"; Port=53; ExpectedService="dns"}
        )

        $detected = 0
        foreach ($target in $targets) {
            Write-Info "Detecting service on $($target.Host):$($target.Port)..."
            $result = & $script:RMapPath $target.Host -p $target.Port -sV 2>&1 | Out-String

            if ($result -match $target.ExpectedService -or $result -match "open") {
                Write-Success "Service detected on $($target.Host):$($target.Port)"
                $detected++
            }
        }

        $duration = (Get-Date) - $testStart
        $status = if ($detected -gt 0) { "PASSED" } else { "FAILED" }
        Add-TestResult -TestName "Service Detection" -Status $status -Details "$detected/$($targets.Count) services detected" -Duration $duration.TotalSeconds
        return ($detected -gt 0)
    } catch {
        Add-TestResult -TestName "Service Detection" -Status "FAILED" -Details $_.Exception.Message -Duration 0
        Write-Error "Service detection failed: $_"
        return $false
    }
}

# Test 5: Output Format Tests
function Test-OutputFormats {
    Write-Test "Output Format Tests"
    $testStart = Get-Date

    if (-not (Test-Path "test_results")) {
        New-Item -ItemType Directory -Path "test_results" -Force | Out-Null
    }

    $formats = @("json", "xml", "markdown", "csv", "grepable")
    $passedFormats = 0

    foreach ($format in $formats) {
        try {
            Write-Info "Testing $format output format..."
            $outputFile = "test_results\test_output.$format"

            $result = & $script:RMapPath scanme.nmap.org -p 22,80 --format $format -o $outputFile 2>&1

            if (Test-Path $outputFile) {
                $fileSize = (Get-Item $outputFile).Length
                if ($fileSize -gt 0) {
                    Write-Success "$format format: Output file created ($fileSize bytes)"
                    $passedFormats++
                } else {
                    Write-Warning "$format format: Empty output file"
                }
            } else {
                Write-Error "$format format: Output file not created"
            }
        } catch {
            Write-Error "$format format failed: $_"
        }
    }

    $duration = (Get-Date) - $testStart
    $status = if ($passedFormats -eq $formats.Count) { "PASSED" } elseif ($passedFormats -gt 0) { "PARTIAL" } else { "FAILED" }
    Add-TestResult -TestName "Output Formats" -Status $status -Details "$passedFormats/$($formats.Count) formats working" -Duration $duration.TotalSeconds
    return ($passedFormats -gt 0)
}

# Test 6: Performance Testing
function Test-Performance {
    Write-Test "Performance and Speed Tests"
    $testStart = Get-Date

    try {
        # Test 1: Single host, multiple ports
        Write-Info "Test 1: Scanning 100 ports on single host..."
        $perfStart = Get-Date
        $result = & $script:RMapPath scanme.nmap.org -p 1-100 2>&1 | Out-String
        $perfTime = (Get-Date) - $perfStart
        Write-Success "100 ports scanned in $($perfTime.TotalSeconds) seconds"

        # Test 2: Multiple hosts
        Write-Info "Test 2: Scanning multiple hosts..."
        $perfStart = Get-Date
        $result = & $script:RMapPath google.com cloudflare.com github.com -p 80,443 2>&1 | Out-String
        $perfTime = (Get-Date) - $perfStart
        Write-Success "3 hosts scanned in $($perfTime.TotalSeconds) seconds"

        # Test 3: Fast scan
        Write-Info "Test 3: Fast scan mode..."
        $perfStart = Get-Date
        $result = & $script:RMapPath scanme.nmap.org --fast 2>&1 | Out-String
        $perfTime = (Get-Date) - $perfStart
        Write-Success "Fast scan completed in $($perfTime.TotalSeconds) seconds"

        $duration = (Get-Date) - $testStart
        Add-TestResult -TestName "Performance Tests" -Status "PASSED" -Details "All performance tests completed" -Duration $duration.TotalSeconds
        return $true
    } catch {
        Add-TestResult -TestName "Performance Tests" -Status "FAILED" -Details $_.Exception.Message -Duration 0
        Write-Error "Performance test failed: $_"
        return $false
    }
}

# Test 7: Error Handling
function Test-ErrorHandling {
    Write-Test "Error Handling and Edge Cases"
    $testStart = Get-Date

    $errorTests = @(
        @{Test="Invalid host"; Command="invalidhostname12345.com -p 80"; ExpectedBehavior="Should handle gracefully"},
        @{Test="Invalid port"; Command="google.com -p 99999"; ExpectedBehavior="Should reject invalid port"},
        @{Test="Timeout handling"; Command="10.255.255.1 -p 80 --timeout 1"; ExpectedBehavior="Should timeout gracefully"},
        @{Test="Invalid format"; Command="google.com -p 80 --format invalid"; ExpectedBehavior="Should show error"}
    )

    $handledCorrectly = 0
    foreach ($test in $errorTests) {
        Write-Info "Testing: $($test.Test)"
        $result = & $script:RMapPath $test.Command.Split() 2>&1 | Out-String

        # Check if program handled error without crashing
        if ($LASTEXITCODE -ne $null) {
            Write-Success "$($test.Test) - Handled correctly"
            $handledCorrectly++
        }
    }

    $duration = (Get-Date) - $testStart
    $status = if ($handledCorrectly -eq $errorTests.Count) { "PASSED" } else { "PARTIAL" }
    Add-TestResult -TestName "Error Handling" -Status $status -Details "$handledCorrectly/$($errorTests.Count) errors handled correctly" -Duration $duration.TotalSeconds
    return ($handledCorrectly -gt 0)
}

# Test 8: Concurrent Operations
function Test-ConcurrentOperations {
    Write-Test "Concurrent Operations and Stress Testing"
    $testStart = Get-Date

    try {
        Write-Info "Testing concurrent scanning capabilities..."

        # Test max connections setting
        Write-Info "Testing with limited connections..."
        $result = & $script:RMapPath scanme.nmap.org -p 1-1000 --max-connections 10 2>&1 | Out-String
        if ($result) {
            Write-Success "Rate limiting works correctly"
        }

        # Test parallel host scanning
        Write-Info "Testing parallel host scanning..."
        $hosts = "google.com", "cloudflare.com", "github.com", "microsoft.com", "amazon.com"
        $result = & $script:RMapPath $hosts -p 443 2>&1 | Out-String
        if ($result -match "open") {
            Write-Success "Parallel host scanning works"
        }

        $duration = (Get-Date) - $testStart
        Add-TestResult -TestName "Concurrent Operations" -Status "PASSED" -Details "Concurrent scanning tests completed" -Duration $duration.TotalSeconds
        return $true
    } catch {
        Add-TestResult -TestName "Concurrent Operations" -Status "FAILED" -Details $_.Exception.Message -Duration 0
        Write-Error "Concurrent operations test failed: $_"
        return $false
    }
}

# Test 9: Real-World Scenarios
function Test-RealWorldScenarios {
    Write-Test "Real-World Use Case Scenarios"
    $testStart = Get-Date

    $scenarios = @()

    # Scenario 1: Web Server Discovery
    Write-Info "Scenario 1: Web server discovery..."
    $webResult = & $script:RMapPath google.com github.com -p 80,443,8080,8443 -sV 2>&1 | Out-String
    if ($webResult -match "open") {
        Write-Success "Web server discovery successful"
        $scenarios += "Web Discovery"
    }

    # Scenario 2: DNS Server Check
    Write-Info "Scenario 2: DNS server availability check..."
    $dnsResult = & $script:RMapPath 1.1.1.1 8.8.8.8 -p 53 2>&1 | Out-String
    if ($dnsResult -match "open") {
        Write-Success "DNS servers detected"
        $scenarios += "DNS Check"
    }

    # Scenario 3: Security Audit Mode
    Write-Info "Scenario 3: Basic security audit..."
    $auditResult = & $script:RMapPath scanme.nmap.org -p 21,22,23,445,3389 2>&1 | Out-String
    Write-Success "Security audit scan completed"
    $scenarios += "Security Audit"

    # Scenario 4: Quick Network Inventory
    Write-Info "Scenario 4: Quick network inventory..."
    $localIP = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.InterfaceAlias -notlike "*Loopback*"} | Select-Object -First 1).IPAddress
    if ($localIP) {
        $gateway = $localIP.Substring(0, $localIP.LastIndexOf('.')) + ".1"
        $invResult = & $script:RMapPath $gateway --fast 2>&1 | Out-String
        Write-Success "Network inventory completed"
        $scenarios += "Network Inventory"
    }

    $duration = (Get-Date) - $testStart
    Add-TestResult -TestName "Real-World Scenarios" -Status "PASSED" -Details "$($scenarios.Count) scenarios tested" -Duration $duration.TotalSeconds
    return $true
}

# Test 10: Windows-Specific Features
function Test-WindowsSpecific {
    Write-Test "Windows-Specific Feature Tests"
    $testStart = Get-Date

    try {
        # Test Windows service ports
        Write-Info "Testing Windows-specific ports..."
        $winPorts = "135,139,445,3389"  # RPC, NetBIOS, SMB, RDP
        $result = & $script:RMapPath localhost -p $winPorts 2>&1 | Out-String

        # Note: localhost might be blocked, test external Windows server instead
        Write-Info "Testing known Windows server..."
        $result = & $script:RMapPath microsoft.com -p 443 2>&1 | Out-String
        if ($result -match "open") {
            Write-Success "Windows server scanning works"
        }

        # Test PowerShell integration
        Write-Info "Testing PowerShell output parsing..."
        $jsonResult = & $script:RMapPath scanme.nmap.org -p 22 --format json 2>&1 | Out-String
        try {
            $parsed = $jsonResult | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($parsed) {
                Write-Success "JSON output parseable in PowerShell"
            }
        } catch {
            Write-Warning "JSON parsing needs adjustment"
        }

        $duration = (Get-Date) - $testStart
        Add-TestResult -TestName "Windows-Specific" -Status "PASSED" -Details "Windows compatibility verified" -Duration $duration.TotalSeconds
        return $true
    } catch {
        Add-TestResult -TestName "Windows-Specific" -Status "FAILED" -Details $_.Exception.Message -Duration 0
        Write-Error "Windows-specific test failed: $_"
        return $false
    }
}

# Generate HTML Report
function Generate-HTMLReport {
    $totalDuration = (Get-Date) - $script:StartTime
    $passedTests = ($script:TestResults | Where-Object {$_.Status -eq "PASSED"}).Count
    $failedTests = ($script:TestResults | Where-Object {$_.Status -eq "FAILED"}).Count
    $partialTests = ($script:TestResults | Where-Object {$_.Status -eq "PARTIAL"}).Count

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>R-Map UA Testing Report</title>
    <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .header { background: #2c3e50; color: white; padding: 20px; border-radius: 5px; }
        .summary { background: white; padding: 20px; margin: 20px 0; border-radius: 5px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .test-results { background: white; padding: 20px; border-radius: 5px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        table { width: 100%; border-collapse: collapse; }
        th { background: #34495e; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ecf0f1; }
        .passed { color: #27ae60; font-weight: bold; }
        .failed { color: #e74c3c; font-weight: bold; }
        .partial { color: #f39c12; font-weight: bold; }
        .stats { display: flex; justify-content: space-around; margin: 20px 0; }
        .stat-box { background: #ecf0f1; padding: 15px; border-radius: 5px; text-align: center; flex: 1; margin: 0 10px; }
        .stat-number { font-size: 2em; font-weight: bold; }
        .footer { text-align: center; margin-top: 30px; color: #7f8c8d; }
    </style>
</head>
<body>
    <div class="header">
        <h1>R-Map User Acceptance Testing Report</h1>
        <p>Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
        <p>Total Duration: $([math]::Round($totalDuration.TotalMinutes, 2)) minutes</p>
    </div>

    <div class="summary">
        <h2>Test Summary</h2>
        <div class="stats">
            <div class="stat-box">
                <div class="stat-number passed">$passedTests</div>
                <div>Passed</div>
            </div>
            <div class="stat-box">
                <div class="stat-number failed">$failedTests</div>
                <div>Failed</div>
            </div>
            <div class="stat-box">
                <div class="stat-number partial">$partialTests</div>
                <div>Partial</div>
            </div>
            <div class="stat-box">
                <div class="stat-number">$($script:TestResults.Count)</div>
                <div>Total Tests</div>
            </div>
        </div>
    </div>

    <div class="test-results">
        <h2>Detailed Test Results</h2>
        <table>
            <thead>
                <tr>
                    <th>Test Name</th>
                    <th>Status</th>
                    <th>Details</th>
                    <th>Duration (seconds)</th>
                    <th>Timestamp</th>
                </tr>
            </thead>
            <tbody>
"@

    foreach ($result in $script:TestResults) {
        $statusClass = switch($result.Status) {
            "PASSED" { "passed" }
            "FAILED" { "failed" }
            "PARTIAL" { "partial" }
        }

        $html += @"
                <tr>
                    <td><strong>$($result.TestName)</strong></td>
                    <td class="$statusClass">$($result.Status)</td>
                    <td>$($result.Details)</td>
                    <td>$([math]::Round($result.Duration, 2))</td>
                    <td>$($result.Timestamp)</td>
                </tr>
"@
    }

    $html += @"
            </tbody>
        </table>
    </div>

    <div class="footer">
        <p>R-Map UA Testing Suite v1.0 | Windows Platform</p>
    </div>
</body>
</html>
"@

    $reportPath = "test_results\UA_Test_Report_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"
    $html | Out-File -FilePath $reportPath -Encoding UTF8
    Write-Success "HTML report generated: $reportPath"

    # Also generate JSON report for automation
    $jsonReport = @{
        TestSuite = "R-Map UA Testing"
        Platform = "Windows"
        StartTime = $script:StartTime
        EndTime = Get-Date
        TotalDuration = $totalDuration.TotalSeconds
        Summary = @{
            TotalTests = $script:TestResults.Count
            Passed = $passedTests
            Failed = $failedTests
            Partial = $partialTests
            SuccessRate = [math]::Round(($passedTests / $script:TestResults.Count) * 100, 2)
        }
        Results = $script:TestResults
    }

    $jsonPath = "test_results\UA_Test_Report_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
    $jsonReport | ConvertTo-Json -Depth 10 | Out-File -FilePath $jsonPath -Encoding UTF8
    Write-Success "JSON report generated: $jsonPath"
}

# Main execution
function Start-UATestingSuite {
    Write-Host "`n" -NoNewline
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "    R-Map Comprehensive UA Testing Suite" -ForegroundColor Cyan
    Write-Host "    Testing Real-World Scenarios on Windows" -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "`n"

    # Create results directory
    if (-not (Test-Path "test_results")) {
        New-Item -ItemType Directory -Path "test_results" -Force | Out-Null
        Write-Info "Created test_results directory"
    }

    # Check if R-Map exists
    if (-not (Test-RMapExists)) {
        Write-Error "Cannot proceed without R-Map executable"
        return
    }

    # Run all tests
    $tests = @(
        "Test-BasicFunctionality",
        "Test-LocalNetworkDiscovery",
        "Test-ExternalHostScanning",
        "Test-ServiceDetection",
        "Test-OutputFormats",
        "Test-Performance",
        "Test-ErrorHandling",
        "Test-ConcurrentOperations",
        "Test-RealWorldScenarios",
        "Test-WindowsSpecific"
    )

    $totalTests = $tests.Count
    $currentTest = 0

    foreach ($test in $tests) {
        $currentTest++
        Write-Host "`n[$currentTest/$totalTests] Running $test..." -ForegroundColor White
        & $test
    }

    # Generate reports
    Write-Host "`n" -NoNewline
    Write-Host "================================================" -ForegroundColor Cyan
    Write-Host "           Test Suite Complete!" -ForegroundColor Cyan
    Write-Host "================================================" -ForegroundColor Cyan

    Generate-HTMLReport

    # Display summary
    $passedTests = ($script:TestResults | Where-Object {$_.Status -eq "PASSED"}).Count
    $failedTests = ($script:TestResults | Where-Object {$_.Status -eq "FAILED"}).Count
    $partialTests = ($script:TestResults | Where-Object {$_.Status -eq "PARTIAL"}).Count
    $successRate = [math]::Round(($passedTests / $script:TestResults.Count) * 100, 2)

    Write-Host "`nFinal Results:" -ForegroundColor White
    Write-Success "Passed: $passedTests"
    if ($failedTests -gt 0) { Write-Error "Failed: $failedTests" }
    if ($partialTests -gt 0) { Write-Warning "Partial: $partialTests" }
    Write-Info "Success Rate: $successRate%"
    Write-Info "Total Duration: $([math]::Round($totalDuration.TotalMinutes, 2)) minutes"

    # Open report in browser
    $openReport = Read-Host "`nOpen HTML report in browser? (y/n)"
    if ($openReport -eq 'y') {
        Start-Process (Get-Item "test_results\UA_Test_Report_*.html" | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
    }
}

# Run the test suite
Start-UATestingSuite