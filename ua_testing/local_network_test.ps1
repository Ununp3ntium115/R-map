# R-Map Local Network Discovery Test
Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "    Local Network Discovery Test" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# Get local network information
$networkAdapters = Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
    $_.InterfaceAlias -notlike "*Loopback*" -and
    $_.IPAddress -notlike "169.254.*"
} | Select-Object -First 1

if ($networkAdapters) {
    $localIP = $networkAdapters.IPAddress
    $prefix = $networkAdapters.PrefixLength

    Write-Host "Network Information:" -ForegroundColor Yellow
    Write-Host "  Your IP: $localIP/$prefix" -ForegroundColor White

    # Calculate gateway (usually .1)
    $ipParts = $localIP.Split('.')
    $gateway = "$($ipParts[0]).$($ipParts[1]).$($ipParts[2]).1"
    Write-Host "  Gateway: $gateway" -ForegroundColor White

    # Calculate small subnet for quick scan
    $testSubnet = "$($ipParts[0]).$($ipParts[1]).$($ipParts[2]).1/32"  # Just gateway
    Write-Host "  Test Target: $gateway" -ForegroundColor White
    Write-Host ""

    # Test 1: Gateway scan
    Write-Host "[1] Scanning Gateway ($gateway)" -ForegroundColor Yellow
    Write-Host "    Checking for web interface and management ports..." -ForegroundColor Gray
    $gatewayResult = & .\target\release\rmap.exe $gateway -p 80,443,8080,22,23 -t 2 2>&1 | Out-String

    if ($gatewayResult -match "open") {
        Write-Host "    FOUND: Gateway services detected!" -ForegroundColor Green
        # Show which ports are open
        $gatewayResult -split "`n" | Where-Object { $_ -match "open" } | ForEach-Object {
            Write-Host "    $_" -ForegroundColor Cyan
        }
    } else {
        Write-Host "    Gateway not responding or blocked" -ForegroundColor Yellow
    }

    # Test 2: Quick local scan for common devices
    Write-Host ""
    Write-Host "[2] Quick Device Discovery" -ForegroundColor Yellow

    # Test a few nearby IPs
    $nearbyIPs = @()
    for ($i = 1; $i -le 10; $i++) {
        $nearbyIPs += "$($ipParts[0]).$($ipParts[1]).$($ipParts[2]).$i"
    }

    Write-Host "    Scanning first 10 IPs in your subnet..." -ForegroundColor Gray
    $devicesFound = 0

    foreach ($ip in $nearbyIPs) {
        Write-Host "    Checking $ip..." -NoNewline -ForegroundColor DarkGray
        $quickScan = & .\target\release\rmap.exe $ip -p 445,80,22 -t 1 2>&1 | Out-String

        if ($quickScan -match "open") {
            Write-Host " DEVICE FOUND!" -ForegroundColor Green
            $devicesFound++

            # Identify device type based on open ports
            if ($quickScan -match "445.*open") {
                Write-Host "      Likely Windows PC (SMB/445 open)" -ForegroundColor Cyan
            }
            if ($quickScan -match "80.*open") {
                Write-Host "      Has web interface (HTTP/80 open)" -ForegroundColor Cyan
            }
            if ($quickScan -match "22.*open") {
                Write-Host "      SSH enabled (port 22 open)" -ForegroundColor Cyan
            }
        } else {
            Write-Host " no response" -ForegroundColor DarkGray
        }
    }

    Write-Host ""
    Write-Host "Summary:" -ForegroundColor Yellow
    Write-Host "  Devices found: $devicesFound" -ForegroundColor White

    # Test 3: Test well-known ports on localhost
    Write-Host ""
    Write-Host "[3] Local Services Check" -ForegroundColor Yellow
    Write-Host "    Checking services on this PC..." -ForegroundColor Gray

    $localScan = & .\target\release\rmap.exe 127.0.0.1 -p 135,445,3389,5000,8080 -t 1 2>&1 | Out-String

    if ($localScan -match "open") {
        Write-Host "    Local services detected:" -ForegroundColor Green
        if ($localScan -match "135.*open") {
            Write-Host "      RPC Endpoint Mapper (135)" -ForegroundColor Cyan
        }
        if ($localScan -match "445.*open") {
            Write-Host "      SMB/File Sharing (445)" -ForegroundColor Cyan
        }
        if ($localScan -match "3389.*open") {
            Write-Host "      Remote Desktop (3389)" -ForegroundColor Cyan
        }
    } else {
        Write-Host "    No local services detected" -ForegroundColor Yellow
    }

} else {
    Write-Host "ERROR: Could not determine network configuration" -ForegroundColor Red
}

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "    Network Discovery Test Complete!" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""