# R-Map PYRO Platform Deployment Package Builder
# Creates a deployable package with all necessary components

param(
    [string]$OutputDir = ".\rmap-pyro-deployment",
    [switch]$IncludeSource,
    [switch]$CreateZip
)

Write-Host "===================================================" -ForegroundColor Cyan
Write-Host "    R-Map PYRO Deployment Package Builder" -ForegroundColor Cyan
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host ""

$ErrorActionPreference = "Stop"

# Create output directory
if (Test-Path $OutputDir) {
    Write-Host "Cleaning existing output directory..." -ForegroundColor Yellow
    Remove-Item $OutputDir -Recurse -Force
}

New-Item -Path $OutputDir -ItemType Directory | Out-Null
Write-Host "[OK] Created output directory: $OutputDir" -ForegroundColor Green

# Function to copy with progress
function Copy-WithProgress {
    param(
        [string]$Source,
        [string]$Destination,
        [string]$Description
    )

    Write-Host "  Copying $Description..." -NoNewline
    Copy-Item -Path $Source -Destination $Destination -Recurse -Force
    Write-Host " Done" -ForegroundColor Green
}

Write-Host ""
Write-Host "Building deployment package..." -ForegroundColor Cyan
Write-Host ""

# 1. Copy R-Map executable
Write-Host "1. Packaging R-Map Core" -ForegroundColor Yellow
$rmapExe = Join-Path $PSScriptRoot "target\release\rmap.exe"
if (Test-Path $rmapExe) {
    $binDir = Join-Path $OutputDir "bin"
    New-Item -Path $binDir -ItemType Directory | Out-Null
    Copy-Item -Path $rmapExe -Destination $binDir
    Write-Host "  [OK] R-Map executable copied" -ForegroundColor Green
} else {
    Write-Host "  [ERROR] R-Map executable not found!" -ForegroundColor Red
    exit 1
}

# 2. Copy API Server
Write-Host ""
Write-Host "2. Packaging API Server" -ForegroundColor Yellow
$apiDir = Join-Path $OutputDir "rmap-api-server"
Copy-WithProgress -Source "rmap-api-server" -Destination $apiDir -Description "API server files"

# Remove node_modules and rebuild on target
if (Test-Path "$apiDir\node_modules") {
    Remove-Item "$apiDir\node_modules" -Recurse -Force
}

# 3. Copy MCP Server
Write-Host ""
Write-Host "3. Packaging MCP Server" -ForegroundColor Yellow
$mcpDir = Join-Path $OutputDir "rmap-mcp-server"
Copy-WithProgress -Source "rmap-mcp-server" -Destination $mcpDir -Description "MCP server files"

# Remove node_modules
if (Test-Path "$mcpDir\node_modules") {
    Remove-Item "$mcpDir\node_modules" -Recurse -Force
}

# 4. Copy Demo UI
Write-Host ""
Write-Host "4. Packaging Demo UI" -ForegroundColor Yellow
$demoDir = Join-Path $OutputDir "demo"
Copy-WithProgress -Source "demo" -Destination $demoDir -Description "Demo UI files"

# 5. Copy Svelte UI Component
Write-Host ""
Write-Host "5. Packaging Svelte UI Component" -ForegroundColor Yellow
$uiDir = Join-Path $OutputDir "rmap-ui"
New-Item -Path $uiDir -ItemType Directory | Out-Null
New-Item -Path "$uiDir\src" -ItemType Directory | Out-Null
Copy-Item -Path "rmap-ui\src\RMapScanner.svelte" -Destination "$uiDir\src\"
Copy-Item -Path "rmap-ui\README.md" -Destination $uiDir -ErrorAction SilentlyContinue
Write-Host "  [OK] Svelte component copied" -ForegroundColor Green

# 6. Copy Scripts and Documentation
Write-Host ""
Write-Host "6. Packaging Scripts and Documentation" -ForegroundColor Yellow

# Scripts
$scriptsDir = Join-Path $OutputDir "scripts"
New-Item -Path $scriptsDir -ItemType Directory | Out-Null
Copy-Item -Path "start_pyro_integration.ps1" -Destination $scriptsDir
Copy-Item -Path "test_pyro_integration.ps1" -Destination $scriptsDir
Write-Host "  [OK] Scripts copied" -ForegroundColor Green

# Documentation
Copy-Item -Path "PYRO_INTEGRATION.md" -Destination $OutputDir
Copy-Item -Path "README.md" -Destination $OutputDir -ErrorAction SilentlyContinue
Write-Host "  [OK] Documentation copied" -ForegroundColor Green

# 7. Create installation script
Write-Host ""
Write-Host "7. Creating installation script" -ForegroundColor Yellow

$installScript = @'
# R-Map PYRO Platform Installation Script

Write-Host "===================================================" -ForegroundColor Cyan
Write-Host "    R-Map PYRO Platform Installer" -ForegroundColor Cyan
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host ""

$ErrorActionPreference = "Stop"

# Check Node.js installation
Write-Host "Checking prerequisites..." -ForegroundColor Yellow
try {
    $nodeVersion = node --version
    Write-Host "  [OK] Node.js $nodeVersion found" -ForegroundColor Green
} catch {
    Write-Host "  [ERROR] Node.js not found. Please install Node.js first." -ForegroundColor Red
    exit 1
}

# Install API server dependencies
Write-Host ""
Write-Host "Installing API server dependencies..." -ForegroundColor Yellow
Set-Location "rmap-api-server"
npm install
Set-Location ..
Write-Host "  [OK] API server ready" -ForegroundColor Green

# Install MCP server dependencies
Write-Host ""
Write-Host "Installing MCP server dependencies..." -ForegroundColor Yellow
Set-Location "rmap-mcp-server"
npm install
npm run build
Set-Location ..
Write-Host "  [OK] MCP server ready" -ForegroundColor Green

# Create temp directories
Write-Host ""
Write-Host "Creating temp directories..." -ForegroundColor Yellow
New-Item -Path "rmap-api-server\temp" -ItemType Directory -Force | Out-Null
New-Item -Path "rmap-mcp-server\temp" -ItemType Directory -Force | Out-Null
Write-Host "  [OK] Directories created" -ForegroundColor Green

Write-Host ""
Write-Host "===================================================" -ForegroundColor Green
Write-Host "    Installation Complete!" -ForegroundColor Green
Write-Host "===================================================" -ForegroundColor Green
Write-Host ""
Write-Host "To start the PYRO integration, run:" -ForegroundColor Cyan
Write-Host "  .\scripts\start_pyro_integration.ps1" -ForegroundColor White
Write-Host ""
Write-Host "To test the integration, run:" -ForegroundColor Cyan
Write-Host "  .\scripts\test_pyro_integration.ps1" -ForegroundColor White
'@

$installScript | Out-File -FilePath (Join-Path $OutputDir "install.ps1") -Encoding UTF8
Write-Host "  [OK] Installation script created" -ForegroundColor Green

# 8. Create Docker files
Write-Host ""
Write-Host "8. Creating Docker configuration" -ForegroundColor Yellow

$dockerfile = @'
FROM node:18-alpine

# Install R-Map dependencies
RUN apk add --no-cache libgcc libstdc++

# Create app directory
WORKDIR /app

# Copy R-Map binary
COPY bin/rmap.exe /usr/local/bin/rmap
RUN chmod +x /usr/local/bin/rmap

# Copy API server
COPY rmap-api-server /app/rmap-api-server
WORKDIR /app/rmap-api-server
RUN npm install --production

# Copy MCP server
COPY rmap-mcp-server /app/rmap-mcp-server
WORKDIR /app/rmap-mcp-server
RUN npm install --production && npm run build

# Copy demo
COPY demo /app/demo

# Expose ports
EXPOSE 8080 3000 8081

# Start script
COPY docker-start.sh /app/
RUN chmod +x /app/docker-start.sh

WORKDIR /app
CMD ["/app/docker-start.sh"]
'@

$dockerCompose = @'
version: '3.8'

services:
  rmap-pyro:
    build: .
    image: rmap-pyro:latest
    container_name: rmap-pyro-platform
    ports:
      - "8080:8080"  # API Server
      - "3000:3000"  # MCP Server
      - "8081:8081"  # Demo UI
    environment:
      - RMAP_PATH=/usr/local/bin/rmap
      - NODE_ENV=production
    volumes:
      - ./data:/app/data
      - ./logs:/app/logs
    restart: unless-stopped
    networks:
      - pyro-network

networks:
  pyro-network:
    driver: bridge
'@

$dockerStart = @'
#!/bin/sh

# Start API server in background
cd /app/rmap-api-server
PORT=8080 node server.js &

# Start MCP server in background
cd /app/rmap-mcp-server
PORT=3000 node dist/index.js &

# Start demo server
cd /app/demo
python3 -m http.server 8081
'@

$dockerfile | Out-File -FilePath (Join-Path $OutputDir "Dockerfile") -Encoding UTF8
$dockerCompose | Out-File -FilePath (Join-Path $OutputDir "docker-compose.yml") -Encoding UTF8
$dockerStart | Out-File -FilePath (Join-Path $OutputDir "docker-start.sh") -Encoding UTF8 -NoNewline
Write-Host "  [OK] Docker configuration created" -ForegroundColor Green

# 9. Create package metadata
Write-Host ""
Write-Host "9. Creating package metadata" -ForegroundColor Yellow

$metadata = @{
    Name = "R-Map PYRO Platform Integration"
    Version = "1.0.0"
    BuildDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Components = @(
        "R-Map Core Scanner v0.1.0-alpha",
        "REST API Server v1.0.0",
        "MCP Server v1.0.0",
        "WebSocket Server",
        "Demo UI",
        "Svelte Components"
    )
    Requirements = @(
        "Windows 10/11 or Linux",
        "Node.js 16+",
        "Python 3 (for demo server)",
        "4GB RAM minimum",
        "Network access for scanning"
    )
}

$metadata | ConvertTo-Json -Depth 3 | Out-File -FilePath (Join-Path $OutputDir "package.json") -Encoding UTF8
Write-Host "  [OK] Package metadata created" -ForegroundColor Green

# Calculate package size
$size = (Get-ChildItem -Path $OutputDir -Recurse | Measure-Object -Property Length -Sum).Sum / 1MB
$sizeStr = [math]::Round($size, 2)

Write-Host ""
Write-Host "===================================================" -ForegroundColor Green
Write-Host "    Deployment Package Complete!" -ForegroundColor Green
Write-Host "===================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Package Location: $OutputDir" -ForegroundColor Cyan
Write-Host "Package Size: $sizeStr MB" -ForegroundColor Cyan
Write-Host ""

# Create ZIP if requested
if ($CreateZip) {
    Write-Host "Creating ZIP archive..." -ForegroundColor Yellow
    $zipPath = "$OutputDir.zip"

    if (Test-Path $zipPath) {
        Remove-Item $zipPath -Force
    }

    Compress-Archive -Path $OutputDir -DestinationPath $zipPath -CompressionLevel Optimal
    $zipSize = [math]::Round((Get-Item $zipPath).Length / 1MB, 2)

    Write-Host "[OK] ZIP created: $zipPath ($zipSize MB)" -ForegroundColor Green
    Write-Host ""
}

Write-Host "Deployment Instructions:" -ForegroundColor Cyan
Write-Host "  1. Copy the package to target server" -ForegroundColor White
Write-Host "  2. Run: .\install.ps1" -ForegroundColor White
Write-Host "  3. Run: .\scripts\start_pyro_integration.ps1" -ForegroundColor White
Write-Host ""
Write-Host "Docker Deployment:" -ForegroundColor Cyan
Write-Host "  docker-compose up -d" -ForegroundColor White
Write-Host ""