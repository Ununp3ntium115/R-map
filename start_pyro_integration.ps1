# R-Map PYRO Platform Integration Startup Script
# This script starts all components required for the R-Map integration

param(
    [switch]$DebugMode,
    [switch]$NoBrowser,
    [int]$ApiPort = 8080,
    [int]$McpPort = 3000,
    [int]$DemoPort = 8081
)

Write-Host "===================================================" -ForegroundColor Cyan
Write-Host "    R-Map PYRO Platform Integration Launcher" -ForegroundColor Cyan
Write-Host "===================================================" -ForegroundColor Cyan
Write-Host ""

# Check if R-Map executable exists
$rmapPath = Join-Path $PSScriptRoot "target\release\rmap.exe"
if (-not (Test-Path $rmapPath)) {
    Write-Host "[ERROR] R-Map executable not found at: $rmapPath" -ForegroundColor Red
    Write-Host "Please build R-Map first with: cargo build --release" -ForegroundColor Yellow
    exit 1
}

Write-Host "[OK] R-Map executable found" -ForegroundColor Green

# Function to start a server in a new window
function Start-Server {
    param(
        [string]$Name,
        [string]$Path,
        [string]$Command,
        [int]$Port
    )

    Write-Host "Starting $Name on port $Port..." -ForegroundColor Yellow

    $scriptBlock = @"
cd '$Path'
Write-Host '===================================================' -ForegroundColor Cyan
Write-Host '    $Name' -ForegroundColor Cyan
Write-Host '    Port: $Port' -ForegroundColor Cyan
Write-Host '===================================================' -ForegroundColor Cyan
$Command
"@

    Start-Process powershell -ArgumentList "-NoExit", "-Command", $scriptBlock -WindowStyle Normal
}

# Kill existing processes on our ports
Write-Host ""
Write-Host "Checking for existing processes..." -ForegroundColor Yellow
$portsToCheck = @($ApiPort, $McpPort, $DemoPort)
foreach ($port in $portsToCheck) {
    $process = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($process) {
        Write-Host "  Port $port is in use, attempting to free it..." -ForegroundColor Yellow
        Stop-Process -Id $process.OwningProcess -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
    }
}

Write-Host ""
Write-Host "Starting services..." -ForegroundColor Cyan
Write-Host ""

# Start API Server (REST + WebSocket)
$apiPath = Join-Path $PSScriptRoot "rmap-api-server"
if (Test-Path $apiPath) {
    $env:PORT = $ApiPort
    $env:RMAP_PATH = $rmapPath
    Start-Server -Name "R-Map API Server" -Path $apiPath -Command "node server.js" -Port $ApiPort
    Write-Host "[STARTED] API Server on http://localhost:$ApiPort" -ForegroundColor Green
} else {
    Write-Host "[WARNING] API Server not found at: $apiPath" -ForegroundColor Yellow
}

Start-Sleep -Seconds 2

# Start MCP Server
$mcpPath = Join-Path $PSScriptRoot "rmap-mcp-server"
if (Test-Path $mcpPath) {
    $env:PORT = $McpPort
    $env:RMAP_PATH = $rmapPath
    Start-Server -Name "R-Map MCP Server" -Path $mcpPath -Command "npm start" -Port $McpPort
    Write-Host "[STARTED] MCP Server on http://localhost:$McpPort" -ForegroundColor Green
} else {
    Write-Host "[WARNING] MCP Server not found at: $mcpPath" -ForegroundColor Yellow
}

Start-Sleep -Seconds 2

# Start Demo Web Server
$demoPath = Join-Path $PSScriptRoot "demo"
if (Test-Path $demoPath) {
    Start-Server -Name "R-Map Demo Interface" -Path $demoPath -Command "python -m http.server $DemoPort" -Port $DemoPort
    Write-Host "[STARTED] Demo Interface on http://localhost:$DemoPort" -ForegroundColor Green
} else {
    Write-Host "[WARNING] Demo not found at: $demoPath" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "===================================================" -ForegroundColor Green
Write-Host "    All services started successfully!" -ForegroundColor Green
Write-Host "===================================================" -ForegroundColor Green
Write-Host ""
Write-Host "Service URLs:" -ForegroundColor Cyan
Write-Host "  API Server:   http://localhost:$ApiPort" -ForegroundColor White
Write-Host "  MCP Server:   http://localhost:$McpPort" -ForegroundColor White
Write-Host "  Demo UI:      http://localhost:$DemoPort" -ForegroundColor White
Write-Host ""
Write-Host "API Endpoints:" -ForegroundColor Cyan
Write-Host "  Health:       http://localhost:$ApiPort/health" -ForegroundColor White
Write-Host "  Scan:         http://localhost:$ApiPort/api/scan" -ForegroundColor White
Write-Host "  History:      http://localhost:$ApiPort/api/history" -ForegroundColor White
Write-Host "  WebSocket:    ws://localhost:$ApiPort" -ForegroundColor White
Write-Host ""

# Open browser unless specified not to
if (-not $NoBrowser) {
    Start-Sleep -Seconds 3
    Write-Host "Opening demo interface in browser..." -ForegroundColor Cyan
    Start-Process "http://localhost:$DemoPort"
}

Write-Host "Press any key to stop all services..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

Write-Host ""
Write-Host "Stopping all services..." -ForegroundColor Yellow

# Find and kill processes on our ports
foreach ($port in $portsToCheck) {
    $process = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($process) {
        Stop-Process -Id $process.OwningProcess -Force -ErrorAction SilentlyContinue
        Write-Host "  Stopped service on port $port" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "All services stopped. Goodbye!" -ForegroundColor Cyan