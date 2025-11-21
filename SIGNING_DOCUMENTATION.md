# R-Map Executable Signing Documentation

## Overview
This document describes the process for signing the R-Map Windows executable with PGP/GPG to ensure authenticity and integrity.

## Certificate Information
- **Key ID:** 0x2CE97943
- **Email:** staff@pyrodifr.com
- **Key File:** staff@pyrodifr.com_0x2CE97943_SECRET.asc
- **Purpose:** Code signing for R-Map releases

## Prerequisites

### 1. Install GPG4Win
Download and install from: https://www.gpg4win.org/
- Includes Kleopatra GUI for key management
- Command-line GPG tools
- Windows integration

### 2. Import the Secret Key
```powershell
gpg --import staff@pyrodifr.com_0x2CE97943_SECRET.asc
```

### 3. Verify Key Import
```powershell
gpg --list-secret-keys --keyid-format LONG
```
Should show the key with ID 2CE97943

## Signing Process

### Automated Signing
Use the provided PowerShell script:
```powershell
.\sign_executable.ps1
```

This will:
1. Import the PGP key
2. Create a signed release directory
3. Generate detached signature (.sig file)
4. Calculate checksums (SHA256, SHA512, MD5)
5. Sign the checksums file
6. Create verification script
7. Package everything into a ZIP file

### Manual Signing
```powershell
# Sign the executable
gpg --detach-sign --armor --local-user 0x2CE97943 --output rmap.exe.sig rmap.exe

# Create checksums
$sha256 = (Get-FileHash -Path rmap.exe -Algorithm SHA256).Hash
Write-Host "SHA256: $sha256"

# Sign checksums file
gpg --clearsign --local-user 0x2CE97943 --output checksums.txt.asc checksums.txt
```

## Verification Process

### For End Users

#### Method 1: Using Verification Script
```powershell
.\verify_signature.ps1
```

#### Method 2: Manual Verification
```powershell
# Import public key (first time only)
gpg --keyserver keyserver.ubuntu.com --recv-keys 0x2CE97943

# Verify signature
gpg --verify rmap.exe.sig rmap.exe

# Verify checksum
Get-FileHash -Path rmap.exe -Algorithm SHA256
```

### Expected Output
```
gpg: Signature made [date] using RSA key ID 2CE97943
gpg: Good signature from "staff@pyrodifr.com"
```

## Distribution

### Release Package Contents
```
signed_release/
├── rmap.exe              # The executable
├── rmap.exe.sig          # Detached signature
├── checksums.txt         # Hash values
├── checksums.txt.asc     # Signed checksums
├── verify_signature.ps1  # Verification script
└── README.txt           # Instructions
```

### Publishing the Public Key

1. **Export public key:**
```powershell
gpg --armor --export 0x2CE97943 > rmap_public_key.asc
```

2. **Upload to keyservers:**
```powershell
gpg --keyserver keyserver.ubuntu.com --send-keys 0x2CE97943
gpg --keyserver keys.openpgp.org --send-keys 0x2CE97943
gpg --keyserver pgp.mit.edu --send-keys 0x2CE97943
```

3. **Include in repository:**
- Add `rmap_public_key.asc` to the repository
- Update README with verification instructions

## Security Best Practices

### Key Security
1. **Keep secret key secure**
   - Never commit the secret key to version control
   - Store offline backup in secure location
   - Use strong passphrase

2. **Key Rotation**
   - Consider annual key rotation
   - Maintain key expiration dates
   - Revoke compromised keys immediately

### Signing Security
1. **Build Environment**
   - Sign only on trusted, clean systems
   - Verify source integrity before building
   - Use reproducible builds when possible

2. **Verification**
   - Always verify your own signatures after signing
   - Test the verification process
   - Document the expected fingerprint

## Troubleshooting

### Common Issues

#### "No secret key"
```
gpg: no default secret key: No secret key
```
**Solution:** Import the secret key file

#### "Cannot open input file"
```
gpg: can't open 'rmap.exe': No such file or directory
```
**Solution:** Ensure you're in the correct directory

#### "Bad signature"
```
gpg: BAD signature from "staff@pyrodifr.com"
```
**Solution:** File has been modified after signing. Re-sign the current version.

## GitHub Release Integration

### Creating a Signed Release

1. **Build and sign:**
```powershell
cargo build --release
.\sign_executable.ps1
```

2. **Create GitHub release:**
```bash
gh release create v0.2.0 \
  --title "R-Map v0.2.0 - Signed Release" \
  --notes "PGP signed with key 0x2CE97943" \
  signed_release/rmap.exe \
  signed_release/rmap.exe.sig \
  signed_release/checksums.txt.asc
```

3. **Add verification instructions to release notes:**
```markdown
## Verification
This release is PGP signed. To verify:
1. Import key: `gpg --recv-keys 0x2CE97943`
2. Verify: `gpg --verify rmap.exe.sig rmap.exe`
```

## Trust and Web of Trust

### Building Trust
1. **Key signing parties** - Get your key signed by others
2. **Consistent use** - Sign all releases with same key
3. **Transparency** - Publish fingerprint widely
4. **Communication** - Announce key changes in advance

### Key Fingerprint
Publish the full fingerprint in multiple locations:
- README.md
- Website
- Social media profiles
- Email signatures

## Automation with CI/CD

### GitHub Actions Example
```yaml
name: Sign Release

on:
  release:
    types: [created]

jobs:
  sign:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v2

      - name: Import GPG key
        run: |
          echo "${{ secrets.GPG_PRIVATE_KEY }}" | gpg --import

      - name: Sign executable
        run: |
          gpg --detach-sign --armor \
            --local-user 0x2CE97943 \
            --output rmap.exe.sig \
            target/release/rmap.exe

      - name: Upload signature
        uses: actions/upload-release-asset@v1
        with:
          upload_url: ${{ github.event.release.upload_url }}
          asset_path: ./rmap.exe.sig
          asset_name: rmap.exe.sig
          asset_content_type: application/pgp-signature
```

## Compliance and Legal

### Export Compliance
- PGP signatures are generally not restricted
- Executable may have export restrictions
- Document compliance requirements

### License Compatibility
- Signing doesn't change license terms
- Include license file in signed releases
- Signatures confirm authenticity only

---

## Quick Reference

### Sign a file
```powershell
gpg --detach-sign --armor --local-user 0x2CE97943 file.exe
```

### Verify a signature
```powershell
gpg --verify file.exe.sig file.exe
```

### List keys
```powershell
gpg --list-keys              # Public keys
gpg --list-secret-keys       # Private keys
```

### Export public key
```powershell
gpg --armor --export 0x2CE97943 > public_key.asc
```

---

**Security Note:** Never share or commit your secret key file. The file `staff@pyrodifr.com_0x2CE97943_SECRET.asc` should be kept secure and never pushed to version control.