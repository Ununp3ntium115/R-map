# R-Map PYRO Platform Integration Test Suite
# Tests the complete integration of R-Map with PYRO Platform components

param(
    [string]$Target = "scanme.nmap.org",
    [string]$ApiServer = "http://localhost:8080",
    [string]$McpServer = "http://localhost:3000",
    [switch]$Verbose
)

$ErrorActionPreference = "Stop"
$testResults = @()
$passedTests = 0
$failedTests = 0

function Write-TestHeader {
    param([string]$Title)
    Write-Host ""
    Write-Host "===================================================" -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host "===================================================" -ForegroundColor Cyan
}

function Test-Component {
    param(
        [string]$Name,
        [scriptblock]$TestCode,
        [string]$Category = "General"
    )

    Write-Host "  Testing: $Name... " -NoNewline

    try {
        $result = & $TestCode
        if ($result) {
            Write-Host "PASSED" -ForegroundColor Green
            $script:passedTests++
            $script:testResults += @{
                Name = $Name
                Category = $Category
                Status = "Passed"
                Message = "Test completed successfully"
            }
            return $true
        } else {
            throw "Test returned false"
        }
    }
    catch {
        Write-Host "FAILED" -ForegroundColor Red
        if ($Verbose) {
            Write-Host "    Error: $_" -ForegroundColor Yellow
        }
        $script:failedTests++
        $script:testResults += @{
            Name = $Name
            Category = $Category
            Status = "Failed"
            Message = $_.ToString()
        }
        return $false
    }
}

# Test 1: Check R-Map Executable
Write-TestHeader "1. R-Map Core Tests"

Test-Component -Name "R-Map executable exists" -Category "Core" -TestCode {
    $rmapPath = Join-Path $PSScriptRoot "target\release\rmap.exe"
    Test-Path $rmapPath
}

Test-Component -Name "R-Map version check" -Category "Core" -TestCode {
    $rmapPath = Join-Path $PSScriptRoot "target\release\rmap.exe"
    $output = & $rmapPath --version 2>&1
    $output -match "R-Map"
}

Test-Component -Name "R-Map basic scan" -Category "Core" -TestCode {
    $rmapPath = Join-Path $PSScriptRoot "target\release\rmap.exe"
    $output = & $rmapPath $Target -p 80 -t 2 2>&1
    $output -match "scan" -or $output -match "port" -or $output -match "80"
}

# Test 2: API Server Tests
Write-TestHeader "2. API Server Tests"

Test-Component -Name "API server health check" -Category "API" -TestCode {
    try {
        $response = Invoke-WebRequest -Uri "$ApiServer/health" -Method GET -TimeoutSec 5
        $response.StatusCode -eq 200
    } catch {
        $false
    }
}

Test-Component -Name "API scan endpoint available" -Category "API" -TestCode {
    try {
        $body = @{
            targets = @($Target)
            ports = "80"
            timeout = 3
        } | ConvertTo-Json

        $response = Invoke-RestMethod -Uri "$ApiServer/api/scan" -Method POST `
            -Body $body -ContentType "application/json" -TimeoutSec 10

        $response.scanId -ne $null
    } catch {
        $false
    }
}

Test-Component -Name "API history endpoint" -Category "API" -TestCode {
    try {
        $response = Invoke-WebRequest -Uri "$ApiServer/api/history" -Method GET -TimeoutSec 5
        $response.StatusCode -eq 200
    } catch {
        $false
    }
}

# Test 3: WebSocket Tests
Write-TestHeader "3. WebSocket Tests"

Test-Component -Name "WebSocket connection" -Category "WebSocket" -TestCode {
    try {
        # Simple WebSocket test using .NET WebSocket
        Add-Type -AssemblyName System.Net.WebSockets.Client
        $ws = New-Object System.Net.WebSockets.ClientWebSocket
        $uri = [System.Uri]::new("ws://localhost:8080")
        $cts = New-Object System.Threading.CancellationTokenSource
        $cts.CancelAfter(5000)

        $task = $ws.ConnectAsync($uri, $cts.Token)
        $task.Wait(5000)

        $connected = $ws.State -eq [System.Net.WebSockets.WebSocketState]::Open
        if ($connected) {
            $ws.CloseAsync([System.Net.WebSockets.WebSocketCloseStatus]::NormalClosure, "", $cts.Token).Wait()
        }
        $connected
    } catch {
        $false
    }
}

# Test 4: MCP Server Tests (if available)
Write-TestHeader "4. MCP Server Tests"

Test-Component -Name "MCP server health check" -Category "MCP" -TestCode {
    try {
        $response = Invoke-WebRequest -Uri "$McpServer/health" -Method GET -TimeoutSec 5 -ErrorAction SilentlyContinue
        $response.StatusCode -eq 200
    } catch {
        # MCP server might not have a health endpoint, check if it's running
        try {
            Test-NetConnection -ComputerName "localhost" -Port 3000 -InformationLevel Quiet
        } catch {
            $false
        }
    }
}

# Test 5: Integration Tests
Write-TestHeader "5. Integration Tests"

Test-Component -Name "End-to-end scan via API" -Category "Integration" -TestCode {
    try {
        # Start a scan
        $scanBody = @{
            targets = @($Target)
            ports = "22,80,443"
            timeout = 5
            outputFormat = "json"
        } | ConvertTo-Json

        $scanResponse = Invoke-RestMethod -Uri "$ApiServer/api/scan" -Method POST `
            -Body $scanBody -ContentType "application/json" -TimeoutSec 10

        if (-not $scanResponse.scanId) {
            throw "No scan ID returned"
        }

        # Wait for scan to complete (max 30 seconds)
        $maxWait = 30
        $elapsed = 0
        $completed = $false

        while ($elapsed -lt $maxWait) {
            Start-Sleep -Seconds 2
            $elapsed += 2

            try {
                $statusResponse = Invoke-RestMethod -Uri "$ApiServer/api/scan/$($scanResponse.scanId)" `
                    -Method GET -TimeoutSec 5

                if ($statusResponse.status -eq "completed") {
                    $completed = $true
                    break
                }
            } catch {
                # Continue waiting
            }
        }

        $completed
    } catch {
        $false
    }
}

Test-Component -Name "Network discovery" -Category "Integration" -TestCode {
    try {
        $body = @{
            network = "127.0.0.1/32"
            quickMode = $true
        } | ConvertTo-Json

        $response = Invoke-RestMethod -Uri "$ApiServer/api/discover" -Method POST `
            -Body $body -ContentType "application/json" -TimeoutSec 10

        $response.scanId -ne $null
    } catch {
        $false
    }
}

Test-Component -Name "Vulnerability scan" -Category "Integration" -TestCode {
    try {
        $body = @{
            targets = @("127.0.0.1")
        } | ConvertTo-Json

        $response = Invoke-RestMethod -Uri "$ApiServer/api/vulnerability" -Method POST `
            -Body $body -ContentType "application/json" -TimeoutSec 10

        $response.scanId -ne $null
    } catch {
        $false
    }
}

# Test 6: Demo UI Tests
Write-TestHeader "6. Demo UI Tests"

Test-Component -Name "Demo UI accessible" -Category "UI" -TestCode {
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:8081" -Method GET -TimeoutSec 5 -ErrorAction SilentlyContinue
        $response.StatusCode -eq 200
    } catch {
        # Try to check if port is listening
        try {
            Test-NetConnection -ComputerName "localhost" -Port 8081 -InformationLevel Quiet
        } catch {
            $false
        }
    }
}

# Generate Summary Report
Write-TestHeader "Test Summary"

Write-Host ""
Write-Host "Total Tests: " -NoNewline
Write-Host ($passedTests + $failedTests) -ForegroundColor White

Write-Host "Passed: " -NoNewline
Write-Host $passedTests -ForegroundColor Green

Write-Host "Failed: " -NoNewline
Write-Host $failedTests -ForegroundColor Red

Write-Host ""
Write-Host "Pass Rate: " -NoNewline
if (($passedTests + $failedTests) -gt 0) {
    $passRate = [math]::Round(($passedTests / ($passedTests + $failedTests)) * 100, 2)
    $color = if ($passRate -ge 80) { "Green" } elseif ($passRate -ge 60) { "Yellow" } else { "Red" }
    Write-Host "$passRate%" -ForegroundColor $color
} else {
    Write-Host "N/A" -ForegroundColor Gray
}

# Show failed tests
if ($failedTests -gt 0) {
    Write-Host ""
    Write-Host "Failed Tests:" -ForegroundColor Red
    $testResults | Where-Object { $_.Status -eq "Failed" } | ForEach-Object {
        Write-Host "  - $($_.Name)" -ForegroundColor Yellow
        if ($Verbose) {
            Write-Host "    $($_.Message)" -ForegroundColor Gray
        }
    }
}

# Generate HTML Report
$reportPath = Join-Path $PSScriptRoot "pyro_integration_test_report.html"
$html = @"
<!DOCTYPE html>
<html>
<head>
    <title>R-Map PYRO Integration Test Report</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            padding: 20px;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            border-radius: 10px;
            padding: 30px;
            box-shadow: 0 10px 40px rgba(0,0,0,0.2);
        }
        h1 {
            color: #333;
            border-bottom: 3px solid #667eea;
            padding-bottom: 10px;
        }
        .summary {
            display: flex;
            justify-content: space-around;
            margin: 20px 0;
            padding: 20px;
            background: #f8f9fa;
            border-radius: 10px;
        }
        .stat {
            text-align: center;
        }
        .stat-value {
            font-size: 36px;
            font-weight: bold;
            color: #667eea;
        }
        .stat-label {
            color: #666;
            margin-top: 5px;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 20px;
        }
        th {
            background: #667eea;
            color: white;
            padding: 12px;
            text-align: left;
        }
        td {
            padding: 10px;
            border-bottom: 1px solid #ddd;
        }
        .passed { color: green; font-weight: bold; }
        .failed { color: red; font-weight: bold; }
        .timestamp {
            color: #666;
            font-size: 14px;
            margin-top: 20px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>R-Map PYRO Platform Integration Test Report</h1>

        <div class="summary">
            <div class="stat">
                <div class="stat-value">$($passedTests + $failedTests)</div>
                <div class="stat-label">Total Tests</div>
            </div>
            <div class="stat">
                <div class="stat-value" style="color: green;">$passedTests</div>
                <div class="stat-label">Passed</div>
            </div>
            <div class="stat">
                <div class="stat-value" style="color: red;">$failedTests</div>
                <div class="stat-label">Failed</div>
            </div>
            <div class="stat">
                <div class="stat-value">$passRate%</div>
                <div class="stat-label">Pass Rate</div>
            </div>
        </div>

        <h2>Test Results</h2>
        <table>
            <thead>
                <tr>
                    <th>Category</th>
                    <th>Test Name</th>
                    <th>Status</th>
                    <th>Message</th>
                </tr>
            </thead>
            <tbody>
"@

foreach ($test in $testResults) {
    $statusClass = if ($test.Status -eq "Passed") { "passed" } else { "failed" }
    $html += @"
                <tr>
                    <td>$($test.Category)</td>
                    <td>$($test.Name)</td>
                    <td class="$statusClass">$($test.Status)</td>
                    <td>$($test.Message)</td>
                </tr>
"@
}

$html += @"
            </tbody>
        </table>

        <div class="timestamp">
            Report generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        </div>
    </div>
</body>
</html>
"@

$html | Out-File -FilePath $reportPath -Encoding UTF8

Write-Host ""
Write-Host "HTML report saved to: $reportPath" -ForegroundColor Cyan

# Return exit code based on results
if ($failedTests -eq 0) {
    Write-Host ""
    Write-Host "All tests passed successfully!" -ForegroundColor Green
    exit 0
} else {
    Write-Host ""
    Write-Host "Some tests failed. Please review the results." -ForegroundColor Yellow
    exit 1
}