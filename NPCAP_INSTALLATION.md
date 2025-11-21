# Npcap Installation Guide for R-Map on Windows

## Overview

R-Map requires Npcap for advanced scanning features on Windows:
- SYN stealth scanning
- UDP scanning
- OS fingerprinting
- ACK/FIN/NULL/Xmas scans

## Installation Steps

### Step 1: Install Npcap Runtime

1. Download Npcap installer from: https://npcap.com/dist/npcap-1.79.exe
2. Run the installer **as Administrator**
3. **IMPORTANT**: Check "Install Npcap in WinPcap API-compatible Mode"
4. Click Install and complete the installation

### Step 2: Install Npcap SDK

1. Download Npcap SDK from: https://npcap.com/dist/npcap-sdk-1.13.zip
2. Extract the ZIP file to: `C:\npcap-sdk\`
3. The directory structure should look like:
   ```
   C:\npcap-sdk\
   ├── Include\
   │   ├── pcap.h
   │   ├── pcap-bpf.h
   │   └── ...
   └── Lib\
       ├── x64\
       │   ├── Packet.lib
       │   └── wpcap.lib
       └── ...
   ```

### Step 3: Set Environment Variable

Add the Npcap SDK lib path to your environment:

```powershell
# PowerShell (Run as Administrator)
[Environment]::SetEnvironmentVariable("LIB", "$env:LIB;C:\npcap-sdk\Lib\x64", "Machine")

# Or manually:
# 1. Open System Properties > Environment Variables
# 2. Under System variables, find "LIB" (or create it)
# 3. Add: C:\npcap-sdk\Lib\x64
```

### Step 4: Restart Terminal

Close and reopen your terminal/IDE for environment changes to take effect.

### Step 5: Build R-Map

```bash
cargo clean
cargo build --release
```

## Verification

After installation, verify Npcap is working:

```bash
# Check for Npcap service
sc query npcap

# Test R-Map
target\release\rmap.exe --version
```

## Troubleshooting

### Error: "cannot open input file 'Packet.lib'"

**Solution**: The LIB environment variable is not set correctly. Verify:
```powershell
echo $env:LIB
# Should include: C:\npcap-sdk\Lib\x64
```

### Error: "Npcap service not running"

**Solution**: Start the Npcap service:
```powershell
# PowerShell (Run as Administrator)
Start-Service npcap
```

### Alternative: Use Pre-built Binary

If you just want to test without building, use the old binary (v0.1.0) which doesn't require Npcap:
```bash
target\release\rmap.exe scanme.nmap.org -p 80,443
```

Note: This version has limited features (TCP connect scan only).

## Features Requiring Npcap

| Feature | Requires Npcap |
|---------|---------------|
| TCP Connect Scan | ❌ No |
| SYN Stealth Scan | ✅ Yes |
| UDP Scan | ✅ Yes |
| OS Fingerprinting | ✅ Yes |
| ACK/FIN/NULL/Xmas | ✅ Yes |
| Service Detection | ❌ No |

## Links

- Npcap Homepage: https://npcap.com/
- Npcap Downloads: https://npcap.com/#download
- GitHub Issues: https://github.com/Ununp3ntium115/R-map/issues
