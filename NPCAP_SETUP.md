# Npcap Setup for R-Map on Windows

## Build Error: Missing Packet.lib

R-Map requires Npcap (or WinPcap) to be installed on Windows for packet capture functionality.

### Error Message
```
LINK : fatal error LNK1181: cannot open input file 'Packet.lib'
```

### Solution

1. **Install Npcap:**
   - Download from: https://npcap.com/#download
   - During installation, select:
     - ✅ Install Npcap in WinPcap API-compatible Mode
     - ✅ Install Npcap SDK

2. **Set Environment Variables:**
   ```powershell
   # Add to your PowerShell profile or run before building:
   $env:LIB = "$env:LIB;C:\Windows\System32\Npcap"
   $env:INCLUDE = "$env:INCLUDE;C:\Windows\System32\Npcap\Include"
   ```

3. **Alternative: Use Pre-built Binary**
   If you have a pre-built rmap.exe from the release, you can use that instead of building from source.

### Testing Without Building

The UA test scripts can still be run if you have a pre-built rmap.exe in the target/release directory.

### Workaround for Testing

If you don't need packet capture features, you can test with basic TCP connect scanning which doesn't require Npcap.