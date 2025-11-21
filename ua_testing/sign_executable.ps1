# R-Map Executable Signing Script
# Signs the R-Map executable with PGP/GPG for authenticity verification

param(
    [string]$ExePath = ".\target\release\rmap.exe",
    [string]$KeyFile = ".\staff@pyrodifr.com_0x2CE97943_SECRET.asc",
    [string]$OutputDir = ".\signed_release"
)

$ErrorActionPreference = "Stop"

# Color functions
function Write-Step { param($msg) Write-Host "[STEP] $msg" -ForegroundColor Cyan }
function Write-Success { param($msg) Write-Host "[✓] $msg" -ForegroundColor Green }
function Write-Error { param($msg) Write-Host "[✗] $msg" -ForegroundColor Red }
function Write-Info { param($msg) Write-Host "[i] $msg" -ForegroundColor Yellow }

Write-Host ""
Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Magenta
Write-Host "     R-Map Executable Signing Process" -ForegroundColor Magenta
Write-Host "     PGP Certificate: 0x2CE97943" -ForegroundColor Magenta
Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Magenta
Write-Host ""

# Check if GPG is installed
Write-Step "Checking for GPG installation..."
$gpgPath = Get-Command gpg -ErrorAction SilentlyContinue
if (-not $gpgPath) {
    Write-Error "GPG is not installed or not in PATH"
    Write-Info "Please install GPG4Win from: https://www.gpg4win.org/"
    exit 1
}
Write-Success "GPG found at: $($gpgPath.Source)"

# Check if executable exists
Write-Step "Checking for R-Map executable..."
if (-not (Test-Path $ExePath)) {
    Write-Error "R-Map executable not found at: $ExePath"
    Write-Info "Please build R-Map first with: cargo build --release"
    exit 1
}
Write-Success "Found executable: $ExePath"

# Check if key file exists
Write-Step "Checking for PGP key file..."
if (-not (Test-Path $KeyFile)) {
    Write-Error "PGP key file not found at: $KeyFile"
    exit 1
}
Write-Success "Found key file: $KeyFile"

# Import the PGP key
Write-Step "Importing PGP key..."
try {
    $importResult = & gpg --import $KeyFile 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Success "PGP key imported successfully"
    } else {
        Write-Info "Key might already be imported"
    }
} catch {
    Write-Error "Failed to import key: $_"
    exit 1
}

# Get key fingerprint
Write-Step "Verifying key fingerprint..."
$keyInfo = & gpg --list-secret-keys --keyid-format LONG 2>&1 | Out-String
if ($keyInfo -match "2CE97943") {
    Write-Success "Key 0x2CE97943 is available for signing"
} else {
    Write-Error "Key 0x2CE97943 not found in keyring"
    exit 1
}

# Create output directory
Write-Step "Creating signed release directory..."
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}
Write-Success "Output directory ready: $OutputDir"

# Copy executable to output directory
Write-Step "Copying executable to release directory..."
$exeName = Split-Path $ExePath -Leaf
$destExe = Join-Path $OutputDir $exeName
Copy-Item $ExePath $destExe -Force
Write-Success "Copied to: $destExe"

# Create detached signature
Write-Step "Creating detached signature..."
$sigFile = "$destExe.sig"
try {
    & gpg --detach-sign --armor --local-user 0x2CE97943 --output $sigFile $destExe
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Signature created: $sigFile"
    } else {
        Write-Error "Failed to create signature"
        exit 1
    }
} catch {
    Write-Error "Signing failed: $_"
    exit 1
}

# Create clearsigned message with checksums
Write-Step "Generating checksums..."
$sha256 = (Get-FileHash -Path $destExe -Algorithm SHA256).Hash
$sha512 = (Get-FileHash -Path $destExe -Algorithm SHA512).Hash
$md5 = (Get-FileHash -Path $destExe -Algorithm MD5).Hash
$fileSize = (Get-Item $destExe).Length

Write-Success "SHA256: $sha256"
Write-Success "SHA512: $sha512"

# Create checksums file
$checksumFile = Join-Path $OutputDir "checksums.txt"
@"
R-Map Executable Checksums
==========================
File: $exeName
Size: $fileSize bytes
Date: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")

SHA256: $sha256
SHA512: $sha512
MD5:    $md5

To verify the signature:
gpg --verify $exeName.sig $exeName

To verify checksums:
- Windows: Get-FileHash -Path $exeName -Algorithm SHA256
- Linux: sha256sum $exeName
"@ | Out-File -FilePath $checksumFile -Encoding UTF8

Write-Success "Checksums saved to: $checksumFile"

# Sign the checksums file
Write-Step "Signing checksums file..."
$checksumSig = "$checksumFile.asc"
& gpg --clearsign --local-user 0x2CE97943 --output $checksumSig $checksumFile
if ($LASTEXITCODE -eq 0) {
    Write-Success "Signed checksums: $checksumSig"
}

# Create verification script
Write-Step "Creating verification script..."
$verifyScript = Join-Path $OutputDir "verify_signature.ps1"
@'
# R-Map Signature Verification Script

param(
    [string]$ExePath = ".\rmap.exe",
    [string]$SigPath = ".\rmap.exe.sig"
)

Write-Host "Verifying R-Map signature..." -ForegroundColor Cyan

# Check if GPG is installed
if (-not (Get-Command gpg -ErrorAction SilentlyContinue)) {
    Write-Host "GPG is not installed. Please install GPG4Win." -ForegroundColor Red
    exit 1
}

# Import public key if needed
$keyId = "0x2CE97943"
$keyCheck = & gpg --list-keys $keyId 2>&1 | Out-String
if ($keyCheck -notmatch "2CE97943") {
    Write-Host "Public key not found. Please import from keyserver:" -ForegroundColor Yellow
    Write-Host "gpg --keyserver keyserver.ubuntu.com --recv-keys $keyId" -ForegroundColor White
}

# Verify signature
Write-Host "Verifying signature..." -ForegroundColor Cyan
& gpg --verify $SigPath $ExePath

if ($LASTEXITCODE -eq 0) {
    Write-Host "✓ Signature verification SUCCESSFUL" -ForegroundColor Green
    Write-Host "  The executable is authentic and has not been tampered with." -ForegroundColor Green
} else {
    Write-Host "✗ Signature verification FAILED" -ForegroundColor Red
    Write-Host "  The executable may have been modified or corrupted." -ForegroundColor Red
}

# Verify checksum
Write-Host "`nVerifying SHA256 checksum..." -ForegroundColor Cyan
$actualHash = (Get-FileHash -Path $ExePath -Algorithm SHA256).Hash
Write-Host "Calculated: $actualHash" -ForegroundColor White

# Read expected hash from checksums file if it exists
if (Test-Path ".\checksums.txt.asc") {
    Write-Host "Check against checksums.txt.asc for the expected value." -ForegroundColor Yellow
}
'@ | Out-File -FilePath $verifyScript -Encoding UTF8

Write-Success "Verification script created: $verifyScript"

# Generate release package
Write-Step "Creating release package..."
$releaseZip = Join-Path $OutputDir "rmap-signed-release.zip"
if (Test-Path $releaseZip) {
    Remove-Item $releaseZip -Force
}

Compress-Archive -Path "$OutputDir\*" -DestinationPath $releaseZip -CompressionLevel Optimal
Write-Success "Release package created: $releaseZip"

# Display summary
Write-Host ""
Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "     Signing Complete!" -ForegroundColor Green
Write-Host "════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Host "Signed Release Contents:" -ForegroundColor Cyan
Write-Host "  • $destExe (signed executable)" -ForegroundColor White
Write-Host "  • $sigFile (detached signature)" -ForegroundColor White
Write-Host "  • $checksumSig (signed checksums)" -ForegroundColor White
Write-Host "  • $verifyScript (verification script)" -ForegroundColor White
Write-Host "  • $releaseZip (complete package)" -ForegroundColor White
Write-Host ""
Write-Host "Distribution Instructions:" -ForegroundColor Yellow
Write-Host "1. Upload the entire $OutputDir directory" -ForegroundColor White
Write-Host "2. Users can verify with: .\verify_signature.ps1" -ForegroundColor White
Write-Host "3. Publish key to keyserver:" -ForegroundColor White
Write-Host "   gpg --keyserver keyserver.ubuntu.com --send-keys 0x2CE97943" -ForegroundColor White
Write-Host ""
Write-Host "Verification Command:" -ForegroundColor Cyan
Write-Host "  gpg --verify rmap.exe.sig rmap.exe" -ForegroundColor White
Write-Host ""