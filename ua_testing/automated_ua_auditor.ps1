# R-Map Automated UA Testing & Audit Framework
# Production-grade testing with comprehensive logging and reporting

param(
    [Parameter(Mandatory=$false)]
    [string]$BinaryPath = "target\release\rmap.exe",

    [Parameter(Mandatory=$false)]
    [string]$LogDir = "audit_logs",

    [Parameter(Mandatory=$false)]
    [string]$ReportDir = "audit_reports",

    [Parameter(Mandatory=$false)]
    [switch]$RealWorldTests = $true,

    [Parameter(Mandatory=$false)]
    [switch]$ComplianceTests = $true
)

# Initialize
$ErrorActionPreference = "Continue"
$script:StartTime = Get-Date
$script:TestResults = @()
$script:AuditLog = @()

# Create directories
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null

# Logging functions
function Write-AuditLog {
    param($Level, $Message, $Data = $null)

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    $entry = [PSCustomObject]@{
        Timestamp = $timestamp
        Level = $Level
        Message = $Message
        Data = $Data
        User = $env:USERNAME
        Host = $env:COMPUTERNAME
    }

    $script:AuditLog += $entry

    $color = switch($Level) {
        "INFO" { "Cyan" }
        "SUCCESS" { "Green" }
        "WARNING" { "Yellow" }
        "ERROR" { "Red" }
        "AUDIT" { "Magenta" }
        default { "White" }
    }

    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

function New-TestResult {
    param(
        [string]$TestName,
        [string]$Category,
        [string]$Target,
        [string]$Command,
        [bool]$Passed,
        [double]$Duration,
        [string]$Output,
        [hashtable]$Metrics = @{}
    )

    $result = [PSCustomObject]@{
        TestName = $TestName
        Category = $Category
        Target = $Target
        Command = $Command
        Passed = $Passed
        Duration = $Duration
        Timestamp = Get-Date
        Output = $Output
        Metrics = $Metrics
        ExitCode = $LASTEXITCODE
    }

    $script:TestResults += $result
    return $result
}

# Real-World Test Scenarios
function Invoke-WebServerAudit {
    param([string]$Target)

    Write-AuditLog "AUDIT" "Starting Web Server Security Audit: $Target"

    $tests = @(
        @{Name="HTTP Port Check"; Ports="80"; ExpectOpen=$true}
        @{Name="HTTPS Port Check"; Ports="443"; ExpectOpen=$true}
        @{Name="HTTP Alt Port"; Ports="8080,8443"; ExpectOpen=$false}
        @{Name="Admin Ports"; Ports="8000,8888,9000"; ExpectOpen=$false}
    )

    foreach ($test in $tests) {
        Write-AuditLog "INFO" "  - Testing: $($test.Name) on ports $($test.Ports)"

        $startTime = Get-Date
        $output = & $BinaryPath $Target -p $test.Ports -o json 2>&1 | Out-String
        $duration = ((Get-Date) - $startTime).TotalSeconds

        $passed = $LASTEXITCODE -eq 0

        # Parse results
        try {
            $json = $output | ConvertFrom-Json
            $openPorts = ($json.hosts[0].ports | Where-Object {$_.state -eq "open"}).Count

            $metrics = @{
                OpenPorts = $openPorts
                TotalPorts = ($json.hosts[0].ports).Count
                ScanTime = $json.scan_info.scan_time
            }

            Write-AuditLog "INFO" "    Found $openPorts open ports"
        } catch {
            $metrics = @{Error = $_.Exception.Message}
        }

        New-TestResult -TestName $test.Name `
                      -Category "WebServer" `
                      -Target $Target `
                      -Command "$BinaryPath $Target -p $($test.Ports)" `
                      -Passed $passed `
                      -Duration $duration `
                      -Output $output `
                      -Metrics $metrics
    }

    Write-AuditLog "SUCCESS" "Web Server Audit Complete: $Target"
}

function Invoke-DatabaseServerAudit {
    param([string]$Target)

    Write-AuditLog "AUDIT" "Starting Database Server Audit: $Target"

    $dbPorts = @{
        "MySQL" = "3306"
        "PostgreSQL" = "5432"
        "MSSQL" = "1433"
        "MongoDB" = "27017"
        "Redis" = "6379"
        "Cassandra" = "9042"
    }

    foreach ($db in $dbPorts.GetEnumerator()) {
        Write-AuditLog "INFO" "  - Checking for $($db.Key) on port $($db.Value)"

        $startTime = Get-Date
        $output = & $BinaryPath $Target -p $db.Value -o json 2>&1 | Out-String
        $duration = ((Get-Date) - $startTime).TotalSeconds

        try {
            $json = $output | ConvertFrom-Json
            $state = $json.hosts[0].ports[0].state

            if ($state -eq "open") {
                Write-AuditLog "WARNING" "    $($db.Key) port is OPEN - potential security risk!"
            } else {
                Write-AuditLog "SUCCESS" "    $($db.Key) port is closed"
            }

            $metrics = @{
                Database = $db.Key
                Port = $db.Value
                State = $state
            }
        } catch {
            $metrics = @{Error = $_.Exception.Message}
        }

        New-TestResult -TestName "$($db.Key) Detection" `
                      -Category "Database" `
                      -Target $Target `
                      -Command "$BinaryPath $Target -p $($db.Value)" `
                      -Passed ($LASTEXITCODE -eq 0) `
                      -Duration $duration `
                      -Output $output `
                      -Metrics $metrics
    }

    Write-AuditLog "SUCCESS" "Database Server Audit Complete"
}

function Invoke-NetworkInfrastructureAudit {
    param([string[]]$Targets)

    Write-AuditLog "AUDIT" "Starting Network Infrastructure Audit"
    Write-AuditLog "INFO" "Targets: $($Targets -join ', ')"

    $infraPorts = "22,23,80,443,3389,5900,8080"

    foreach ($target in $Targets) {
        Write-AuditLog "INFO" "  - Scanning infrastructure: $target"

        $startTime = Get-Date
        $output = & $BinaryPath $target -p $infraPorts -A -o json 2>&1 | Out-String
        $duration = ((Get-Date) - $startTime).TotalSeconds

        # Save detailed output
        $logFile = Join-Path $LogDir "infra_$($target)_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
        $output | Out-File -FilePath $logFile -Encoding UTF8

        try {
            $json = $output | ConvertFrom-Json
            $openPorts = ($json.hosts[0].ports | Where-Object {$_.state -eq "open"})

            Write-AuditLog "INFO" "    Discovered $($openPorts.Count) open services:"
            foreach ($port in $openPorts) {
                $svc = if ($port.service) { $port.service } else { "unknown" }
                $ver = if ($port.version) { " ($($port.version))" } else { "" }
                Write-AuditLog "INFO" "      - Port $($port.port): $svc$ver"
            }

            $metrics = @{
                OpenServices = $openPorts.Count
                Services = ($openPorts | ForEach-Object { "$($_.port)/$($_.service)" }) -join ","
                LogFile = $logFile
            }
        } catch {
            $metrics = @{Error = $_.Exception.Message}
        }

        New-TestResult -TestName "Infrastructure Scan" `
                      -Category "Infrastructure" `
                      -Target $target `
                      -Command "$BinaryPath $target -p $infraPorts -A" `
                      -Passed ($LASTEXITCODE -eq 0) `
                      -Duration $duration `
                      -Output $output `
                      -Metrics $metrics
    }

    Write-AuditLog "SUCCESS" "Network Infrastructure Audit Complete"
}

function Invoke-SecurityComplianceScan {
    param([string]$Target)

    Write-AuditLog "AUDIT" "Starting Security Compliance Scan: $Target"

    # Common vulnerable services
    $vulnChecks = @(
        @{Name="Telnet (Insecure)"; Port="23"; Severity="HIGH"}
        @{Name="FTP (Unencrypted)"; Port="21"; Severity="MEDIUM"}
        @{Name="HTTP (Unencrypted)"; Port="80"; Severity="LOW"}
        @{Name="RDP"; Port="3389"; Severity="MEDIUM"}
        @{Name="VNC"; Port="5900"; Severity="HIGH"}
        @{Name="SMB"; Port="445"; Severity="MEDIUM"}
    )

    $findings = @()

    foreach ($check in $vulnChecks) {
        Write-AuditLog "INFO" "  - Checking: $($check.Name)"

        $startTime = Get-Date
        $output = & $BinaryPath $Target -p $check.Port -o json 2>&1 | Out-String
        $duration = ((Get-Date) - $startTime).TotalSeconds

        try {
            $json = $output | ConvertFrom-Json
            $state = $json.hosts[0].ports[0].state

            if ($state -eq "open") {
                Write-AuditLog "WARNING" "    [$($check.Severity)] $($check.Name) is exposed!"
                $findings += [PSCustomObject]@{
                    Service = $check.Name
                    Port = $check.Port
                    Severity = $check.Severity
                    Status = "EXPOSED"
                }
            } else {
                Write-AuditLog "SUCCESS" "    $($check.Name) is not exposed"
            }

            $metrics = @{
                Service = $check.Name
                State = $state
                Severity = $check.Severity
            }
        } catch {
            $metrics = @{Error = $_.Exception.Message}
        }

        New-TestResult -TestName "Compliance: $($check.Name)" `
                      -Category "Compliance" `
                      -Target $Target `
                      -Command "$BinaryPath $Target -p $($check.Port)" `
                      -Passed ($state -ne "open") `
                      -Duration $duration `
                      -Output $output `
                      -Metrics $metrics
    }

    if ($findings.Count -gt 0) {
        Write-AuditLog "WARNING" "Found $($findings.Count) security compliance issues"
    } else {
        Write-AuditLog "SUCCESS" "No security compliance issues found"
    }

    return $findings
}

function Invoke-PerformanceBenchmark {
    Write-AuditLog "AUDIT" "Starting Performance Benchmarks"

    $benchmarks = @(
        @{Name="Single Port Fast"; Target="8.8.8.8"; Ports="53"}
        @{Name="Common Ports"; Target="scanme.nmap.org"; Ports="22,80,443"}
        @{Name="Port Range Small"; Target="127.0.0.1"; Ports="80-90"}
        @{Name="Multi-Target"; Target="1.1.1.1 8.8.8.8"; Ports="80,443"}
    )

    foreach ($bench in $benchmarks) {
        Write-AuditLog "INFO" "  - Benchmark: $($bench.Name)"

        $times = @()
        for ($i = 1; $i -le 3; $i++) {
            $startTime = Get-Date
            & $BinaryPath $bench.Target -p $bench.Ports -o json | Out-Null
            $duration = ((Get-Date) - $startTime).TotalSeconds
            $times += $duration
            Write-AuditLog "INFO" "    Run $i: ${duration}s"
        }

        $avgTime = ($times | Measure-Object -Average).Average
        $minTime = ($times | Measure-Object -Minimum).Minimum
        $maxTime = ($times | Measure-Object -Maximum).Maximum

        Write-AuditLog "INFO" "    Average: ${avgTime}s (min: ${minTime}s, max: ${maxTime}s)"

        New-TestResult -TestName $bench.Name `
                      -Category "Performance" `
                      -Target $bench.Target `
                      -Command "$BinaryPath $($bench.Target) -p $($bench.Ports)" `
                      -Passed $true `
                      -Duration $avgTime `
                      -Output "Benchmark completed" `
                      -Metrics @{
                          AverageTime = $avgTime
                          MinTime = $minTime
                          MaxTime = $maxTime
                          Runs = 3
                      }
    }

    Write-AuditLog "SUCCESS" "Performance Benchmarks Complete"
}

# Generate Reports
function New-ComplianceReport {
    param($Findings)

    $reportPath = Join-Path $ReportDir "compliance_report_$(Get-Date -Format 'yyyyMMdd_HHmmss').html"

    $html = @"
<!DOCTYPE html>
<html>
<head>
    <title>R-Map Security Compliance Report</title>
    <style>
        body { font-family: 'Segoe UI', Arial; margin: 20px; background: #f5f5f5; }
        .header { background: #d32f2f; color: white; padding: 20px; border-radius: 5px; }
        .summary { background: white; padding: 20px; margin: 20px 0; border-radius: 5px; }
        .finding { background: white; padding: 15px; margin: 10px 0; border-left: 5px solid #ff9800; }
        .severity-HIGH { border-left-color: #d32f2f; }
        .severity-MEDIUM { border-left-color: #ff9800; }
        .severity-LOW { border-left-color: #ffc107; }
        table { width: 100%; border-collapse: collapse; background: white; }
        th { background: #424242; color: white; padding: 12px; text-align: left; }
        td { padding: 10px; border-bottom: 1px solid #ddd; }
        .pass { color: #4caf50; font-weight: bold; }
        .fail { color: #f44336; font-weight: bold; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🛡️ R-Map Security Compliance Report</h1>
        <p>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')</p>
        <p>Auditor: $env:USERNAME @ $env:COMPUTERNAME</p>
    </div>

    <div class="summary">
        <h2>Executive Summary</h2>
        <p><strong>Total Tests:</strong> $($script:TestResults.Count)</p>
        <p><strong>Passed:</strong> <span class="pass">$(($script:TestResults | Where-Object {$_.Passed}).Count)</span></p>
        <p><strong>Failed:</strong> <span class="fail">$(($script:TestResults | Where-Object {-not $_.Passed}).Count)</span></p>
        <p><strong>Compliance Issues:</strong> <span class="fail">$($Findings.Count)</span></p>
    </div>
"@

    if ($Findings.Count -gt 0) {
        $html += @"
    <div class="summary">
        <h2>⚠️ Security Findings</h2>
"@
        foreach ($finding in $Findings) {
            $html += @"
        <div class="finding severity-$($finding.Severity)">
            <h3>[$($finding.Severity)] $($finding.Service)</h3>
            <p><strong>Port:</strong> $($finding.Port)</p>
            <p><strong>Status:</strong> $($finding.Status)</p>
        </div>
"@
        }
        $html += "</div>"
    }

    $html += @"
    <div class="summary">
        <h2>Test Results</h2>
        <table>
            <thead>
                <tr>
                    <th>Test Name</th>
                    <th>Category</th>
                    <th>Target</th>
                    <th>Duration</th>
                    <th>Status</th>
                </tr>
            </thead>
            <tbody>
"@

    foreach ($result in $script:TestResults) {
        $status = if ($result.Passed) { "<span class='pass'>PASS</span>" } else { "<span class='fail'>FAIL</span>" }
        $html += @"
                <tr>
                    <td>$($result.TestName)</td>
                    <td>$($result.Category)</td>
                    <td>$($result.Target)</td>
                    <td>$([math]::Round($result.Duration, 3))s</td>
                    <td>$status</td>
                </tr>
"@
    }

    $html += @"
            </tbody>
        </table>
    </div>
</body>
</html>
"@

    $html | Out-File -FilePath $reportPath -Encoding UTF8
    Write-AuditLog "SUCCESS" "Compliance report generated: $reportPath"
    return $reportPath
}

function New-AuditLogReport {
    $logPath = Join-Path $LogDir "audit_log_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
    $script:AuditLog | ConvertTo-Json -Depth 10 | Out-File -FilePath $logPath -Encoding UTF8
    Write-AuditLog "SUCCESS" "Audit log saved: $logPath"

    $csvPath = Join-Path $ReportDir "test_results_$(Get-Date -Format 'yyyyMMdd_HHmmss').csv"
    $script:TestResults | Export-Csv -Path $csvPath -NoTypeInformation
    Write-AuditLog "SUCCESS" "CSV report generated: $csvPath"

    return @{LogPath = $logPath; CSVPath = $csvPath}
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

Write-AuditLog "AUDIT" "========================================="
Write-AuditLog "AUDIT" "R-Map Automated UA Testing & Audit Suite"
Write-AuditLog "AUDIT" "========================================="
Write-AuditLog "INFO" "Binary: $BinaryPath"
Write-AuditLog "INFO" "Log Directory: $LogDir"
Write-AuditLog "INFO" "Report Directory: $ReportDir"

# Verify binary
if (-not (Test-Path $BinaryPath)) {
    Write-AuditLog "ERROR" "Binary not found: $BinaryPath"
    exit 1
}

Write-AuditLog "SUCCESS" "Binary verified: $BinaryPath"

# Real-World Tests
if ($RealWorldTests) {
    Write-AuditLog "AUDIT" "=== REAL-WORLD TEST SCENARIOS ==="

    # Web Server Audits
    Invoke-WebServerAudit -Target "scanme.nmap.org"
    Invoke-WebServerAudit -Target "github.com"

    # Database Audit
    Invoke-DatabaseServerAudit -Target "scanme.nmap.org"

    # Infrastructure Audit
    Invoke-NetworkInfrastructureAudit -Targets @("8.8.8.8", "1.1.1.1", "scanme.nmap.org")

    # Performance Benchmarks
    Invoke-PerformanceBenchmark
}

# Compliance Tests
$complianceFindings = @()
if ($ComplianceTests) {
    Write-AuditLog "AUDIT" "=== SECURITY COMPLIANCE SCANS ==="
    $complianceFindings = Invoke-SecurityComplianceScan -Target "scanme.nmap.org"
}

# Generate Reports
Write-AuditLog "AUDIT" "=== GENERATING REPORTS ==="

$complianceReport = New-ComplianceReport -Findings $complianceFindings
$auditReports = New-AuditLogReport

# Final Summary
$totalDuration = ((Get-Date) - $script:StartTime).TotalSeconds
$passCount = ($script:TestResults | Where-Object {$_.Passed}).Count
$failCount = ($script:TestResults | Where-Object {-not $_.Passed}).Count
$passRate = if ($script:TestResults.Count -gt 0) {
    [math]::Round(($passCount / $script:TestResults.Count) * 100, 1)
} else { 0 }

Write-AuditLog "AUDIT" "========================================="
Write-AuditLog "AUDIT" "AUDIT COMPLETE"
Write-AuditLog "AUDIT" "========================================="
Write-AuditLog "INFO" "Total Tests: $($script:TestResults.Count)"
Write-AuditLog "SUCCESS" "Passed: $passCount"
Write-AuditLog "ERROR" "Failed: $failCount"
Write-AuditLog "INFO" "Pass Rate: $passRate%"
Write-AuditLog "INFO" "Total Duration: ${totalDuration}s"
Write-AuditLog "INFO" "Compliance Issues: $($complianceFindings.Count)"
Write-AuditLog "INFO" "Compliance Report: $complianceReport"
Write-AuditLog "INFO" "Audit Log: $($auditReports.LogPath)"
Write-AuditLog "INFO" "CSV Report: $($auditReports.CSVPath)"

if ($failCount -eq 0 -and $complianceFindings.Count -eq 0) {
    Write-AuditLog "SUCCESS" "✅ ALL TESTS PASSED - NO COMPLIANCE ISSUES"
    exit 0
} else {
    Write-AuditLog "WARNING" "⚠️ REVIEW REQUIRED - See reports for details"
    exit 1
}
