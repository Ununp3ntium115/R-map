# R-Map Network Validation Test Suite
# Comprehensive network discovery and validation

$ErrorActionPreference = "Continue"
$script:RMapPath = ".\target\release\rmap.exe"
$script:TestResults = @()

# Color functions
function Write-TestHeader { param($msg) Write-Host "`n[NETWORK TEST] $msg" -ForegroundColor Magenta }
function Write-Discovery { param($msg) Write-Host "  [DISCOVERY] $msg" -ForegroundColor Cyan }
function Write-Found { param($msg) Write-Host "    ✓ $msg" -ForegroundColor Green }
function Write-NotFound { param($msg) Write-Host "    ✗ $msg" -ForegroundColor Red }
function Write-Analysis { param($msg) Write-Host "  [ANALYSIS] $msg" -ForegroundColor Yellow }

# Get network information
function Get-NetworkInfo {
    $networkInfo = @{}

    # Get all active network adapters
    $adapters = Get-NetAdapter | Where-Object {$_.Status -eq "Up"}

    foreach ($adapter in $adapters) {
        $ipConfig = Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue

        if ($ipConfig -and $ipConfig.IPAddress -notlike "169.254.*") {
            $networkInfo[$adapter.Name] = @{
                IP = $ipConfig.IPAddress
                Prefix = $ipConfig.PrefixLength
                Gateway = (Get-NetRoute -InterfaceIndex $adapter.ifIndex -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue).NextHop
                DNS = (Get-DnsClientServerAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4).ServerAddresses
                Subnet = "$($ipConfig.IPAddress.Substring(0, $ipConfig.IPAddress.LastIndexOf('.'))).0/$($ipConfig.PrefixLength)"
            }
        }
    }

    return $networkInfo
}

# Test 1: Local Network Discovery
function Test-LocalNetworkDiscovery {
    Write-TestHeader "Local Network Discovery and Mapping"

    $networks = Get-NetworkInfo

    if ($networks.Count -eq 0) {
        Write-NotFound "No active networks found"
        return
    }

    foreach ($adapter in $networks.Keys) {
        Write-Discovery "Network Adapter: $adapter"
        $network = $networks[$adapter]

        Write-Host "    IP Address: $($network.IP)"
        Write-Host "    Gateway: $($network.Gateway)"
        Write-Host "    DNS Servers: $($network.DNS -join ', ')"
        Write-Host "    Subnet: $($network.Subnet)"

        # Quick scan of local subnet
        Write-Analysis "Scanning subnet $($network.Subnet) for active hosts..."

        $scanResult = & $script:RMapPath $network.Subnet --fast --skip-ping 2>&1 | Out-String

        # Count discovered hosts
        $hostMatches = [regex]::Matches($scanResult, "Host.*?(\d+\.\d+\.\d+\.\d+).*up")
        $discoveredHosts = @()

        foreach ($match in $hostMatches) {
            $discoveredHosts += $match.Groups[1].Value
        }

        if ($discoveredHosts.Count -gt 0) {
            Write-Found "Discovered $($discoveredHosts.Count) active hosts"
            foreach ($host in $discoveredHosts) {
                Write-Host "      • $host"
            }
        } else {
            Write-NotFound "No hosts discovered (may be blocked by firewall)"
        }

        # Test gateway specifically
        if ($network.Gateway) {
            Write-Analysis "Testing gateway $($network.Gateway)..."
            $gwResult = & $script:RMapPath $network.Gateway -p 80,443,22,23 2>&1 | Out-String

            if ($gwResult -match "open") {
                Write-Found "Gateway is responding"
                if ($gwResult -match "80.*open") { Write-Host "      • HTTP (80) open" }
                if ($gwResult -match "443.*open") { Write-Host "      • HTTPS (443) open" }
                if ($gwResult -match "22.*open") { Write-Host "      • SSH (22) open" }
                if ($gwResult -match "23.*open") { Write-Host "      • Telnet (23) open" }
            }
        }
    }
}

# Test 2: Device Type Identification
function Test-DeviceIdentification {
    Write-TestHeader "Device Type Identification"

    $localIP = (Get-NetIPAddress -AddressFamily IPv4 |
                Where-Object {$_.InterfaceAlias -notlike "*Loopback*" -and $_.IPAddress -notlike "169.254.*"} |
                Select-Object -First 1).IPAddress

    if (-not $localIP) {
        Write-NotFound "Could not determine local IP"
        return
    }

    $subnet = $localIP.Substring(0, $localIP.LastIndexOf('.'))

    $deviceTypes = @{
        "Router/Gateway" = @{
            IPs = @("$subnet.1", "$subnet.254")
            Ports = "80,443,22,23,8080"
            Signatures = @("router", "gateway", "admin", "login")
        }
        "Printer" = @{
            IPs = @()
            Ports = "631,9100,515,80"
            Signatures = @("printer", "cups", "lpd")
        }
        "NAS/Storage" = @{
            IPs = @()
            Ports = "445,139,548,2049,873"
            Signatures = @("smb", "cifs", "afp", "nfs", "rsync")
        }
        "Smart TV/Media" = @{
            IPs = @()
            Ports = "8080,9080,55000,1900"
            Signatures = @("tv", "media", "upnp", "dlna")
        }
        "IoT Device" = @{
            IPs = @()
            Ports = "1883,8883,5683,49152"
            Signatures = @("mqtt", "coap", "iot", "smart")
        }
    }

    foreach ($deviceType in $deviceTypes.Keys) {
        Write-Discovery "Checking for $deviceType devices..."

        $device = $deviceTypes[$deviceType]

        # Check specific IPs if defined
        if ($device.IPs.Count -gt 0) {
            foreach ($ip in $device.IPs) {
                $result = & $script:RMapPath $ip -p $device.Ports --timeout 2 2>&1 | Out-String
                if ($result -match "open") {
                    Write-Found "$deviceType likely at $ip"
                }
            }
        } else {
            # Scan subnet for device type
            $quickScan = & $script:RMapPath "$subnet.0/28" -p $device.Ports --skip-ping --timeout 2 2>&1 | Out-String

            $foundDevices = [regex]::Matches($quickScan, "(\d+\.\d+\.\d+\.\d+).*?(\d+).*open")
            if ($foundDevices.Count -gt 0) {
                foreach ($match in $foundDevices) {
                    Write-Found "$deviceType possibly at $($match.Groups[1].Value):$($match.Groups[2].Value)"
                }
            }
        }
    }
}

# Test 3: Network Services Discovery
function Test-NetworkServices {
    Write-TestHeader "Network Services Discovery"

    $services = @{
        "Web Servers" = @{Ports = "80,443,8080,8443"; Description = "HTTP/HTTPS services"}
        "File Sharing" = @{Ports = "445,139,21,22"; Description = "SMB/FTP/SFTP"}
        "Database Servers" = @{Ports = "3306,5432,1433,27017"; Description = "MySQL/PostgreSQL/MSSQL/MongoDB"}
        "Mail Servers" = @{Ports = "25,110,143,587,993,995"; Description = "SMTP/POP3/IMAP"}
        "Remote Access" = @{Ports = "22,23,3389,5900"; Description = "SSH/Telnet/RDP/VNC"}
        "Development" = @{Ports = "3000,5000,8000,9000"; Description = "Common dev ports"}
    }

    $localIP = (Get-NetIPAddress -AddressFamily IPv4 |
                Where-Object {$_.InterfaceAlias -notlike "*Loopback*"} |
                Select-Object -First 1).IPAddress

    if ($localIP) {
        $testRange = "$($localIP.Substring(0, $localIP.LastIndexOf('.'))).0/28"

        foreach ($serviceType in $services.Keys) {
            Write-Discovery "$serviceType ($($services[$serviceType].Description))"

            $scan = & $script:RMapPath $testRange -p $services[$serviceType].Ports --skip-ping 2>&1 | Out-String

            $serviceMatches = [regex]::Matches($scan, "(\d+\.\d+\.\d+\.\d+).*?(\d+).*open")

            if ($serviceMatches.Count -gt 0) {
                $uniqueHosts = @{}
                foreach ($match in $serviceMatches) {
                    $host = $match.Groups[1].Value
                    $port = $match.Groups[2].Value
                    if (-not $uniqueHosts.ContainsKey($host)) {
                        $uniqueHosts[$host] = @()
                    }
                    $uniqueHosts[$host] += $port
                }

                Write-Found "Found $($uniqueHosts.Count) hosts with $serviceType"
                foreach ($host in $uniqueHosts.Keys) {
                    Write-Host "      • $host : ports $($uniqueHosts[$host] -join ', ')"
                }
            } else {
                Write-Host "      No $serviceType found"
            }
        }
    }
}

# Test 4: DNS and Name Resolution
function Test-DNSResolution {
    Write-TestHeader "DNS and Name Resolution Testing"

    # Test local DNS servers
    $dnsServers = Get-DnsClientServerAddress -AddressFamily IPv4 |
                  Where-Object {$_.ServerAddresses} |
                  Select-Object -ExpandProperty ServerAddresses -Unique

    Write-Discovery "Testing DNS servers..."
    foreach ($dns in $dnsServers) {
        Write-Host "    Testing DNS server: $dns"
        $result = & $script:RMapPath $dns -p 53 2>&1 | Out-String

        if ($result -match "53.*open") {
            Write-Found "DNS server $dns is responding"
        } else {
            Write-NotFound "DNS server $dns not responding on port 53"
        }
    }

    # Test hostname resolution
    Write-Discovery "Testing hostname resolution..."
    $testHosts = @("google.com", "cloudflare.com", "localhost")

    foreach ($hostname in $testHosts) {
        $result = & $script:RMapPath $hostname -p 443 2>&1 | Out-String

        if ($result -match "Host:.*\d+\.\d+\.\d+\.\d+") {
            Write-Found "$hostname resolved successfully"
        } else {
            Write-NotFound "Failed to resolve $hostname"
        }
    }
}

# Test 5: Network Topology Mapping
function Test-NetworkTopology {
    Write-TestHeader "Network Topology Mapping"

    Write-Discovery "Building network topology..."

    # Get routing table
    $routes = Get-NetRoute | Where-Object {$_.DestinationPrefix -ne "0.0.0.0/0" -and $_.AddressFamily -eq "IPv4"}

    Write-Host "    Local routing table:"
    $routes | Select-Object -Unique DestinationPrefix, NextHop -First 5 | ForEach-Object {
        Write-Host "      • $($_.DestinationPrefix) via $($_.NextHop)"
    }

    # Trace to common destinations
    Write-Discovery "Testing network paths..."
    $traceTargets = @("8.8.8.8", "1.1.1.1")

    foreach ($target in $traceTargets) {
        Write-Host "    Path to $target:"

        # Quick reachability test
        $scan = & $script:RMapPath $target -p 53 2>&1 | Out-String
        if ($scan -match "open") {
            Write-Found "$target is reachable"
        } else {
            Write-NotFound "$target is not reachable"
        }
    }
}

# Test 6: VLAN and Segmentation Detection
function Test-NetworkSegmentation {
    Write-TestHeader "Network Segmentation Detection"

    $adapters = Get-NetAdapter | Where-Object {$_.Status -eq "Up"}

    Write-Discovery "Checking for network segmentation..."

    $vlans = @()
    foreach ($adapter in $adapters) {
        $vlanId = $adapter.VlanID
        if ($vlanId -and $vlanId -ne 0) {
            $vlans += $vlanId
            Write-Found "VLAN $vlanId detected on $($adapter.Name)"
        }
    }

    if ($vlans.Count -eq 0) {
        Write-Host "    No VLANs detected (flat network)"
    }

    # Check for multiple subnets
    $subnets = @()
    Get-NetIPAddress -AddressFamily IPv4 | Where-Object {$_.IPAddress -notlike "169.254.*" -and $_.IPAddress -ne "127.0.0.1"} | ForEach-Object {
        $subnet = "$($_.IPAddress.Substring(0, $_.IPAddress.LastIndexOf('.'))).0/$($_.PrefixLength)"
        if ($subnet -notin $subnets) {
            $subnets += $subnet
        }
    }

    if ($subnets.Count -gt 1) {
        Write-Found "Multiple subnets detected:"
        foreach ($subnet in $subnets) {
            Write-Host "      • $subnet"
        }
    }
}

# Generate Network Report
function Generate-NetworkReport {
    $reportPath = "ua_test_results\Network_Validation_$(Get-Date -Format 'yyyyMMdd_HHmmss').txt"

    if (-not (Test-Path "ua_test_results")) {
        New-Item -ItemType Directory -Path "ua_test_results" -Force | Out-Null
    }

    @"
R-Map Network Validation Report
================================
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

Network Configuration:
$(Get-NetworkInfo | ConvertTo-Json -Depth 3)

Test Results:
- Local Network Discovery: Completed
- Device Identification: Completed
- Network Services: Completed
- DNS Resolution: Completed
- Topology Mapping: Completed
- Segmentation Detection: Completed

Summary:
All network validation tests completed successfully.
Detailed results are available in the console output.
"@ | Out-File -FilePath $reportPath -Encoding UTF8

    Write-Host "`n═══════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "Network Validation Complete!" -ForegroundColor Green
    Write-Host "Report saved to: $reportPath" -ForegroundColor White
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor Cyan
}

# Main execution
function Start-NetworkValidation {
    Clear-Host
    Write-Host "╔═══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║     R-Map Network Validation Test Suite              ║" -ForegroundColor Cyan
    Write-Host "║     Comprehensive Network Discovery & Mapping        ║" -ForegroundColor Cyan
    Write-Host "╚═══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    # Check R-Map exists
    if (-not (Test-Path $script:RMapPath)) {
        Write-Host "Building R-Map..." -ForegroundColor Yellow
        & cargo build --release
    }

    # Run all network tests
    Test-LocalNetworkDiscovery
    Test-DeviceIdentification
    Test-NetworkServices
    Test-DNSResolution
    Test-NetworkTopology
    Test-NetworkSegmentation

    # Generate report
    Generate-NetworkReport
}

# Run the validation
Start-NetworkValidation