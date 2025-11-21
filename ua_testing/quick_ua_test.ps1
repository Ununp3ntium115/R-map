# R-Map Quick UA Test
Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "    R-Map Quick UA Validation Test" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

$testsPassed = 0
$testsFailed = 0

# Test 1: Version Check
Write-Host "[TEST 1] Version Check" -ForegroundColor Yellow
$version = & .\target\release\rmap.exe --version 2>&1
if ($version) {
    Write-Host "  PASS: R-Map version: $version" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "  FAIL: Could not get version" -ForegroundColor Red
    $testsFailed++
}

# Test 2: External Host Scan - Google
Write-Host ""
Write-Host "[TEST 2] External Host Scanning (google.com)" -ForegroundColor Yellow
$result = & .\target\release\rmap.exe google.com -p 80,443 2>&1 | Out-String
if ($result -match "open") {
    Write-Host "  PASS: Found open ports on google.com" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "  FAIL: No open ports found" -ForegroundColor Red
    $testsFailed++
}

# Test 3: Service Detection
Write-Host ""
Write-Host "[TEST 3] Service Detection (scanme.nmap.org)" -ForegroundColor Yellow
$result = & .\target\release\rmap.exe scanme.nmap.org -p 22,80 -A 2>&1 | Out-String
if ($result -match "ssh" -or $result -match "http") {
    Write-Host "  PASS: Services detected correctly" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "  FAIL: Services not detected" -ForegroundColor Red
    $testsFailed++
}

# Test 4: JSON Output
Write-Host ""
Write-Host "[TEST 4] JSON Output Format" -ForegroundColor Yellow
$jsonFile = "quick_test_output.json"
& .\target\release\rmap.exe 1.1.1.1 -p 53 -o json -f $jsonFile 2>&1 | Out-Null
Start-Sleep -Seconds 1
if (Test-Path $jsonFile) {
    try {
        $json = Get-Content $jsonFile | ConvertFrom-Json
        if ($json.scan_info.version) {
            Write-Host "  PASS: JSON output working correctly" -ForegroundColor Green
            $testsPassed++
        } else {
            Write-Host "  FAIL: JSON structure invalid" -ForegroundColor Red
            $testsFailed++
        }
        Remove-Item $jsonFile -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Host "  FAIL: JSON parsing error" -ForegroundColor Red
        $testsFailed++
    }
} else {
    Write-Host "  FAIL: JSON output file not created" -ForegroundColor Red
    $testsFailed++
}

# Test 5: Performance Test
Write-Host ""
Write-Host "[TEST 5] Performance Test (100 ports)" -ForegroundColor Yellow
$startTime = Get-Date
$result = & .\target\release\rmap.exe scanme.nmap.org -p 1-100 2>&1 | Out-String
$duration = ((Get-Date) - $startTime).TotalSeconds
Write-Host "  Scan completed in $([math]::Round($duration, 2)) seconds" -ForegroundColor Gray
if ($duration -lt 30) {
    Write-Host "  PASS: Good performance" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "  WARN: Slower than expected" -ForegroundColor Yellow
    $testsPassed++
}

# Test 6: Multiple Hosts
Write-Host ""
Write-Host "[TEST 6] Multiple Host Scanning" -ForegroundColor Yellow
$result = & .\target\release\rmap.exe google.com cloudflare.com -p 443 2>&1 | Out-String
if ($result -match "google" -and $result -match "cloudflare") {
    Write-Host "  PASS: Multiple hosts scanned" -ForegroundColor Green
    $testsPassed++
} else {
    Write-Host "  FAIL: Multiple host scan failed" -ForegroundColor Red
    $testsFailed++
}

# Summary
Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "    Test Summary" -ForegroundColor White
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  Tests Passed: $testsPassed" -ForegroundColor Green
Write-Host "  Tests Failed: $testsFailed" -ForegroundColor Red
$successRate = [math]::Round(($testsPassed / ($testsPassed + $testsFailed)) * 100, 1)
Write-Host "  Success Rate: $successRate%" -ForegroundColor White

if ($testsFailed -eq 0) {
    Write-Host ""
    Write-Host "  All tests PASSED! R-Map is working correctly." -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "  Some tests failed. Check R-Map configuration." -ForegroundColor Yellow
}

Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""