# R-Map Scenario-Based Testing Suite
# Real-world application scenarios for R-Map

$ErrorActionPreference = "Continue"
$script:RMapPath = ".\target\release\rmap.exe"

# Ensure test results directory exists
if (-not (Test-Path "ua_test_results")) {
    New-Item -ItemType Directory -Path "ua_test_results" -Force | Out-Null
}

# Color functions
function Write-Scenario { param($msg) Write-Host "`n[SCENARIO] $msg" -ForegroundColor Cyan -BackgroundColor Black }
function Write-Step { param($msg) Write-Host "  → $msg" -ForegroundColor Yellow }
function Write-Result { param($msg) Write-Host "  ✓ $msg" -ForegroundColor Green }
function Write-Finding { param($msg) Write-Host "  • $msg" -ForegroundColor White }

# ==============================================================================
# SCENARIO 1: Corporate Network Security Audit
# ==============================================================================
function Test-SecurityAuditScenario {
    Write-Scenario "Corporate Network Security Audit"
    Write-Host "  Simulating a security audit to identify vulnerable services" -ForegroundColor Gray

    Write-Step "Phase 1: Identifying high-risk services..."

    # Test for commonly exploited services
    $riskyPorts = @{
        "21" = "FTP (often unencrypted)"
        "23" = "Telnet (unencrypted)"
        "135" = "Windows RPC"
        "139" = "NetBIOS"
        "445" = "SMB/CIFS"
        "1433" = "MS SQL Server"
        "3306" = "MySQL"
        "3389" = "RDP"
        "5900" = "VNC"
    }

    $target = "scanme.nmap.org"  # Safe test target
    Write-Step "Scanning $target for risky services..."

    $scanCmd = "$script:RMapPath $target -p $(($riskyPorts.Keys) -join ',') -sV -o ua_test_results\security_audit.json --format json"
    $result = Invoke-Expression $scanCmd 2>&1 | Out-String

    foreach ($port in $riskyPorts.Keys) {
        if ($result -match "$port.*open") {
            Write-Finding "Port $port ($($riskyPorts[$port])) is OPEN - Security Risk!"
        }
    }

    Write-Step "Phase 2: Checking for anonymous access..."
    # Test specific anonymous access patterns
    $anonCheck = "$script:RMapPath $target -p 21,445 -sV"
    $anonResult = Invoke-Expression $anonCheck 2>&1 | Out-String

    if ($anonResult -match "21.*open") {
        Write-Finding "FTP service detected - Check for anonymous login"
    }

    Write-Result "Security audit scenario completed"
    Write-Host "  Report saved to: ua_test_results\security_audit.json" -ForegroundColor Gray
}

# ==============================================================================
# SCENARIO 2: Home Network Device Discovery
# ==============================================================================
function Test-HomeNetworkScenario {
    Write-Scenario "Home Network Device Discovery"
    Write-Host "  Discovering and identifying devices on home network" -ForegroundColor Gray

    # Get local network info
    $localIP = (Get-NetIPAddress -AddressFamily IPv4 |
                Where-Object {$_.InterfaceAlias -notlike "*Loopback*" -and $_.IPAddress -notlike "169.254.*"} |
                Select-Object -First 1).IPAddress
    $subnet = $localIP.Substring(0, $localIP.LastIndexOf('.')) + ".0/24"

    Write-Step "Scanning home network: $subnet"

    # Quick discovery scan
    $discoveryCmd = "$script:RMapPath $subnet --fast --skip-ping -o ua_test_results\home_network.json --format json"
    Write-Step "Running discovery scan (this may take 1-2 minutes)..."
    $devices = Invoke-Expression $discoveryCmd 2>&1 | Out-String

    # Count discovered devices
    $deviceCount = ([regex]::Matches($devices, "Host.*up")).Count
    Write-Finding "Found $deviceCount active devices on network"

    Write-Step "Identifying common device types..."

    # Check for common home devices
    $commonDevices = @{
        "Router" = @($localIP.Substring(0, $localIP.LastIndexOf('.')) + ".1", "80,443,22,23")
        "Smart TV" = @("", "8080,9080,55000")
        "Printer" = @("", "631,9100,515")
        "NAS/Media" = @("", "445,139,22,80")
    }

    foreach ($deviceType in $commonDevices.Keys) {
        if ($commonDevices[$deviceType][0]) {
            $checkCmd = "$script:RMapPath $($commonDevices[$deviceType][0]) -p $($commonDevices[$deviceType][1])"
            $checkResult = Invoke-Expression $checkCmd 2>&1 | Out-String
            if ($checkResult -match "open") {
                Write-Finding "$deviceType likely detected"
            }
        }
    }

    Write-Result "Home network discovery completed"
    Write-Host "  Report saved to: ua_test_results\home_network.json" -ForegroundColor Gray
}

# ==============================================================================
# SCENARIO 3: Web Application Infrastructure Mapping
# ==============================================================================
function Test-WebInfrastructureScenario {
    Write-Scenario "Web Application Infrastructure Mapping"
    Write-Host "  Mapping web application infrastructure and services" -ForegroundColor Gray

    $webTargets = @("google.com", "github.com", "cloudflare.com")

    foreach ($target in $webTargets) {
        Write-Step "Mapping $target infrastructure..."

        # Standard web ports plus common alternatives
        $webPorts = "80,443,8080,8443,3000,5000,8000,8888"

        $scanCmd = "$script:RMapPath $target -p $webPorts -sV"
        $result = Invoke-Expression $scanCmd 2>&1 | Out-String

        # Analyze results
        if ($result -match "80.*open") {
            Write-Finding "$target has HTTP (port 80) - Likely redirects to HTTPS"
        }
        if ($result -match "443.*open") {
            Write-Finding "$target has HTTPS (port 443) - Standard secure web"
        }
        if ($result -match "8080.*open") {
            Write-Finding "$target has service on 8080 - Possible API or admin panel"
        }

        # Check for CDN/Load balancer signatures
        if ($result -match "cloudflare" -or $result -match "akamai" -or $result -match "fastly") {
            Write-Finding "$target is using CDN/DDoS protection"
        }
    }

    Write-Result "Web infrastructure mapping completed"
}

# ==============================================================================
# SCENARIO 4: Database Server Discovery
# ==============================================================================
function Test-DatabaseDiscoveryScenario {
    Write-Scenario "Database Server Discovery"
    Write-Host "  Identifying database servers and their versions" -ForegroundColor Gray

    $dbPorts = @{
        "3306" = "MySQL/MariaDB"
        "5432" = "PostgreSQL"
        "1433" = "MS SQL Server"
        "1521" = "Oracle"
        "27017" = "MongoDB"
        "6379" = "Redis"
        "5984" = "CouchDB"
        "9042" = "Cassandra"
    }

    Write-Step "Scanning for database services..."

    # Test against known servers (safe targets)
    $testTargets = @("scanme.nmap.org", "google.com")

    foreach ($target in $testTargets) {
        Write-Step "Checking $target for database services..."

        $dbScan = "$script:RMapPath $target -p $(($dbPorts.Keys) -join ',') -sV"
        $result = Invoke-Expression $dbScan 2>&1 | Out-String

        foreach ($port in $dbPorts.Keys) {
            if ($result -match "$port.*open") {
                Write-Finding "Found $($dbPorts[$port]) on port $port at $target"
            }
        }
    }

    Write-Result "Database discovery completed"
}

# ==============================================================================
# SCENARIO 5: Cloud Service Identification
# ==============================================================================
function Test-CloudServiceScenario {
    Write-Scenario "Cloud Service Provider Identification"
    Write-Host "  Identifying cloud providers and services" -ForegroundColor Gray

    $cloudTargets = @{
        "microsoft.com" = "Azure"
        "aws.amazon.com" = "AWS"
        "cloud.google.com" = "GCP"
    }

    foreach ($target in $cloudTargets.Keys) {
        Write-Step "Analyzing $target ($($cloudTargets[$target]))..."

        $cloudScan = "$script:RMapPath $target -p 443 -sV"
        $result = Invoke-Expression $cloudScan 2>&1 | Out-String

        if ($result -match "443.*open") {
            Write-Finding "$($cloudTargets[$target]) service endpoint confirmed"
        }

        # Check for cloud-specific signatures
        if ($result -match "microsoft" -or $result -match "azure") {
            Write-Finding "Azure infrastructure detected"
        }
        if ($result -match "amazon" -or $result -match "aws") {
            Write-Finding "AWS infrastructure detected"
        }
        if ($result -match "google") {
            Write-Finding "Google Cloud infrastructure detected"
        }
    }

    Write-Result "Cloud service identification completed"
}

# ==============================================================================
# SCENARIO 6: IoT Device Detection
# ==============================================================================
function Test-IoTDeviceScenario {
    Write-Scenario "IoT Device Detection"
    Write-Host "  Detecting Internet of Things devices" -ForegroundColor Gray

    $iotPorts = @{
        "1883" = "MQTT (IoT messaging)"
        "8883" = "MQTT over TLS"
        "5683" = "CoAP (IoT protocol)"
        "502" = "Modbus (Industrial)"
        "47808" = "BACnet (Building automation)"
        "10000" = "Webmin (Device management)"
        "49152" = "UPnP"
    }

    Write-Step "Scanning for IoT protocols and services..."

    # Scan local network for IoT devices
    $localIP = (Get-NetIPAddress -AddressFamily IPv4 |
                Where-Object {$_.InterfaceAlias -notlike "*Loopback*"} |
                Select-Object -First 1).IPAddress

    if ($localIP) {
        $iotRange = $localIP.Substring(0, $localIP.LastIndexOf('.')) + ".0/28"  # Small range for speed

        Write-Step "Checking local network segment: $iotRange"

        $iotScan = "$script:RMapPath $iotRange -p $(($iotPorts.Keys) -join ',') --skip-ping"
        $result = Invoke-Expression $iotScan 2>&1 | Out-String

        foreach ($port in $iotPorts.Keys) {
            if ($result -match "$port.*open") {
                Write-Finding "IoT Protocol detected: $($iotPorts[$port]) on port $port"
            }
        }
    }

    Write-Result "IoT device detection completed"
}

# ==============================================================================
# SCENARIO 7: Development Environment Discovery
# ==============================================================================
function Test-DevEnvironmentScenario {
    Write-Scenario "Development Environment Discovery"
    Write-Host "  Identifying development and staging servers" -ForegroundColor Gray

    $devPorts = @{
        "3000" = "Node.js/React dev server"
        "4200" = "Angular dev server"
        "5000" = "Flask/Python dev server"
        "8000" = "Django/HTTP server"
        "8080" = "Tomcat/Jenkins"
        "9000" = "PHP-FPM/SonarQube"
        "5173" = "Vite dev server"
        "8081" = "Nexus Repository"
    }

    Write-Step "Scanning for development services..."

    # Check localhost and common dev targets
    $devTargets = @("localhost", "127.0.0.1")

    foreach ($target in $devTargets) {
        Write-Step "Checking $target for dev services..."

        $devScan = "$script:RMapPath $target -p $(($devPorts.Keys) -join ',')"
        $result = Invoke-Expression $devScan 2>&1 | Out-String

        foreach ($port in $devPorts.Keys) {
            if ($result -match "$port.*open") {
                Write-Finding "Development service found: $($devPorts[$port]) on port $port"
            }
        }
    }

    Write-Result "Development environment discovery completed"
}

# ==============================================================================
# SCENARIO 8: Compliance Scanning (PCI/HIPAA)
# ==============================================================================
function Test-ComplianceScenario {
    Write-Scenario "Compliance Scanning (PCI/HIPAA)"
    Write-Host "  Checking for compliance violations" -ForegroundColor Gray

    $complianceChecks = @{
        "Unencrypted Services" = @("21", "23", "80", "110", "143")
        "Default Ports" = @("8080", "8000", "3306", "5432")
        "Remote Access" = @("22", "3389", "5900")
        "File Sharing" = @("445", "139", "2049")
    }

    Write-Step "Running compliance checks..."

    $target = "scanme.nmap.org"

    foreach ($category in $complianceChecks.Keys) {
        Write-Step "Checking: $category"

        $ports = $complianceChecks[$category] -join ','
        $compScan = "$script:RMapPath $target -p $ports"
        $result = Invoke-Expression $compScan 2>&1 | Out-String

        foreach ($port in $complianceChecks[$category]) {
            if ($result -match "$port.*open") {
                Write-Finding "WARNING: $category - Port $port is open (potential compliance issue)"
            }
        }
    }

    Write-Result "Compliance scanning completed"
}

# ==============================================================================
# Main Test Runner
# ==============================================================================
function Start-ScenarioTests {
    Clear-Host
    Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║         R-Map Real-World Scenario Testing Suite             ║" -ForegroundColor Cyan
    Write-Host "║              Practical Application Tests                    ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    # Check R-Map exists
    if (-not (Test-Path $script:RMapPath)) {
        Write-Host "Building R-Map..." -ForegroundColor Yellow
        & cargo build --release
    }

    $scenarios = @(
        @{Name="Security Audit"; Function="Test-SecurityAuditScenario"},
        @{Name="Home Network Discovery"; Function="Test-HomeNetworkScenario"},
        @{Name="Web Infrastructure"; Function="Test-WebInfrastructureScenario"},
        @{Name="Database Discovery"; Function="Test-DatabaseDiscoveryScenario"},
        @{Name="Cloud Services"; Function="Test-CloudServiceScenario"},
        @{Name="IoT Devices"; Function="Test-IoTDeviceScenario"},
        @{Name="Dev Environment"; Function="Test-DevEnvironmentScenario"},
        @{Name="Compliance Check"; Function="Test-ComplianceScenario"}
    )

    Write-Host "Available Scenarios:" -ForegroundColor White
    for ($i = 0; $i -lt $scenarios.Count; $i++) {
        Write-Host "  [$($i+1)] $($scenarios[$i].Name)"
    }
    Write-Host "  [9] Run All Scenarios"
    Write-Host "  [0] Exit"
    Write-Host ""

    $choice = Read-Host "Select scenario to test"

    switch ($choice) {
        "0" { return }
        "9" {
            foreach ($scenario in $scenarios) {
                & $scenario.Function
                Start-Sleep -Seconds 2
            }
        }
        default {
            $index = [int]$choice - 1
            if ($index -ge 0 -and $index -lt $scenarios.Count) {
                & $scenarios[$index].Function
            } else {
                Write-Host "Invalid selection" -ForegroundColor Red
            }
        }
    }

    Write-Host "`n═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "Scenario testing complete. Results saved in ua_test_results\" -ForegroundColor Green
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Cyan
}

# Run the scenario tests
Start-ScenarioTests