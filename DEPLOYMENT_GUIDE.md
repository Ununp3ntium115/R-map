# R-Map PYRO Platform Deployment Guide

## Table of Contents
1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Quick Start](#quick-start)
4. [Installation Methods](#installation-methods)
5. [Configuration](#configuration)
6. [Testing](#testing)
7. [Production Deployment](#production-deployment)
8. [Troubleshooting](#troubleshooting)
9. [API Reference](#api-reference)
10. [Security Considerations](#security-considerations)

## Overview

R-Map PYRO Platform Integration provides comprehensive network scanning capabilities for the PYRO Platform Ignition system. This deployment guide covers installation, configuration, and operation of all components.

### Components

| Component | Description | Port |
|-----------|------------|------|
| R-Map Core | Network scanner engine | N/A |
| API Server | REST API & WebSocket server | 8080 |
| MCP Server | Model Context Protocol server | 3000 |
| Demo UI | Web-based interface | 8081 |

## Prerequisites

### System Requirements
- **OS**: Windows 10/11, Linux (Ubuntu 20.04+), macOS 11+
- **RAM**: Minimum 4GB, Recommended 8GB
- **Storage**: 500MB for installation, 2GB for logs/data
- **Network**: Unrestricted outbound connections for scanning

### Software Requirements
- Node.js 16+ (LTS recommended)
- Python 3.8+ (for demo server)
- Git (for source installation)
- PowerShell 7+ (Windows) or Bash (Linux/macOS)

## Quick Start

### 1. Download Package
```bash
# Download the latest release
curl -L https://github.com/Ununp3ntium115/R-map/releases/latest/download/rmap-pyro-deployment.zip -o rmap-pyro.zip
unzip rmap-pyro.zip
cd rmap-pyro-deployment
```

### 2. Install Dependencies
```powershell
# Windows
.\install.ps1

# Linux/macOS
./install.sh
```

### 3. Start Services
```powershell
# Windows
.\scripts\start_pyro_integration.ps1

# Linux/macOS
./scripts/start_pyro_integration.sh
```

### 4. Access Interface
Open your browser to: http://localhost:8081

## Installation Methods

### Method 1: Pre-built Package

1. Download the deployment package
2. Extract to desired location
3. Run installation script
4. Start services

### Method 2: From Source

```bash
# Clone repository
git clone https://github.com/Ununp3ntium115/R-map.git
cd R-map

# Build R-Map
cargo build --release

# Install dependencies
cd rmap-api-server && npm install && cd ..
cd rmap-mcp-server && npm install && npm run build && cd ..

# Start services
powershell -ExecutionPolicy Bypass -File start_pyro_integration.ps1
```

### Method 3: Docker

```bash
# Using docker-compose
docker-compose up -d

# Or build and run manually
docker build -t rmap-pyro .
docker run -d \
  -p 8080:8080 \
  -p 3000:3000 \
  -p 8081:8081 \
  --name rmap-pyro \
  rmap-pyro
```

### Method 4: Kubernetes

```yaml
kubectl apply -f k8s/
kubectl get pods -n rmap-pyro
kubectl get services -n rmap-pyro
```

## Configuration

### Environment Variables

```bash
# API Server
export RMAP_PATH=/usr/local/bin/rmap  # Path to R-Map executable
export PORT=8080                       # API server port
export MAX_CONCURRENT_SCANS=10        # Maximum concurrent scans
export SCAN_TIMEOUT=300                # Default scan timeout (seconds)

# MCP Server
export MCP_PORT=3000                   # MCP server port
export MCP_LOG_LEVEL=info             # Logging level (debug|info|warn|error)

# Security
export API_KEY=your-secret-key        # API authentication key
export ENABLE_AUTH=true               # Enable authentication
export ALLOWED_ORIGINS=*              # CORS allowed origins
```

### Configuration Files

#### `config/api-server.json`
```json
{
  "server": {
    "port": 8080,
    "host": "0.0.0.0",
    "cors": {
      "enabled": true,
      "origins": ["*"]
    }
  },
  "rmap": {
    "executable": "./bin/rmap.exe",
    "defaultTimeout": 300,
    "maxConcurrent": 10
  },
  "security": {
    "authentication": false,
    "rateLimit": {
      "enabled": true,
      "maxRequests": 100,
      "windowMs": 60000
    }
  }
}
```

#### `config/mcp-server.json`
```json
{
  "server": {
    "port": 3000,
    "name": "rmap-mcp",
    "version": "1.0.0"
  },
  "tools": [
    "scan_ports",
    "quick_scan",
    "service_detection",
    "network_discovery",
    "vulnerability_scan"
  ]
}
```

## Testing

### Run Integration Tests
```powershell
# Full test suite
.\test_pyro_integration.ps1 -Verbose

# Specific target
.\test_pyro_integration.ps1 -Target "192.168.1.1"

# Custom endpoints
.\test_pyro_integration.ps1 -ApiServer "http://localhost:8080" -McpServer "http://localhost:3000"
```

### Manual Testing

#### Test API Health
```bash
curl http://localhost:8080/health
```

#### Test Scanning
```bash
# Basic scan
curl -X POST http://localhost:8080/api/scan \
  -H "Content-Type: application/json" \
  -d '{"targets":["scanme.nmap.org"],"ports":"80,443"}'

# Network discovery
curl -X POST http://localhost:8080/api/discover \
  -H "Content-Type: application/json" \
  -d '{"network":"192.168.1.0/24","quickMode":true}'
```

#### Test WebSocket
```javascript
const ws = new WebSocket('ws://localhost:8080');
ws.on('open', () => {
  ws.send(JSON.stringify({
    type: 'scan_request',
    tool: 'quick_scan',
    arguments: { targets: ['127.0.0.1'] }
  }));
});
```

## Production Deployment

### Security Hardening

1. **Enable Authentication**
```bash
export ENABLE_AUTH=true
export API_KEY=$(openssl rand -hex 32)
```

2. **Configure Firewall**
```bash
# Allow only necessary ports
ufw allow 8080/tcp
ufw allow 3000/tcp
ufw deny 8081/tcp  # Block demo UI in production
```

3. **Use HTTPS**
```nginx
server {
    listen 443 ssl;
    server_name rmap.example.com;

    ssl_certificate /etc/ssl/certs/rmap.crt;
    ssl_certificate_key /etc/ssl/private/rmap.key;

    location / {
        proxy_pass http://localhost:8080;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
    }
}
```

### Scaling

#### Horizontal Scaling
```yaml
# docker-compose.scale.yml
services:
  rmap-api:
    image: rmap-pyro:latest
    deploy:
      replicas: 3
    environment:
      - REDIS_HOST=redis

  redis:
    image: redis:alpine
    ports:
      - "6379:6379"
```

#### Load Balancing
```nginx
upstream rmap_backend {
    least_conn;
    server 127.0.0.1:8080;
    server 127.0.0.1:8081;
    server 127.0.0.1:8082;
}

server {
    location / {
        proxy_pass http://rmap_backend;
    }
}
```

### Monitoring

#### Prometheus Metrics
```yaml
# prometheus.yml
scrape_configs:
  - job_name: 'rmap'
    static_configs:
      - targets: ['localhost:8080']
    metrics_path: '/metrics'
```

#### Logging
```bash
# Configure centralized logging
export LOG_LEVEL=info
export LOG_FILE=/var/log/rmap/api.log
export LOG_MAX_SIZE=100M
export LOG_MAX_FILES=10
```

## Troubleshooting

### Common Issues

#### Port Already in Use
```bash
# Find process using port
netstat -tulpn | grep 8080

# Kill process
kill -9 <PID>
```

#### R-Map Not Found
```bash
# Set path explicitly
export RMAP_PATH=/path/to/rmap.exe

# Or create symlink
ln -s /path/to/rmap.exe /usr/local/bin/rmap
```

#### Permission Denied
```bash
# Grant execute permission
chmod +x rmap.exe
chmod +x scripts/*.sh

# Run with elevated privileges (for SYN scanning)
sudo ./start_pyro_integration.sh
```

#### Node Modules Issues
```bash
# Clean and reinstall
rm -rf node_modules package-lock.json
npm cache clean --force
npm install
```

### Debug Mode

Enable verbose logging:
```bash
export DEBUG=*
export LOG_LEVEL=debug
node server.js
```

### Health Checks

```bash
# Check all services
curl http://localhost:8080/health
curl http://localhost:3000/health
curl http://localhost:8081

# Check connectivity
nc -zv localhost 8080
nc -zv localhost 3000
```

## API Reference

### REST Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/health` | Health check |
| POST | `/api/scan` | Start new scan |
| GET | `/api/scan/:id` | Get scan status |
| POST | `/api/scan/:id/stop` | Stop scan |
| GET | `/api/history` | Get scan history |
| POST | `/api/discover` | Network discovery |
| POST | `/api/vulnerability` | Vulnerability scan |

### WebSocket Events

#### Client → Server
- `scan_request`: Start new scan
- `stop_scan`: Stop active scan
- `get_history`: Request scan history

#### Server → Client
- `scan_started`: Scan initiated
- `scan_progress`: Progress update
- `scan_result`: Partial results
- `scan_complete`: Scan finished
- `scan_error`: Error occurred

### MCP Tools

| Tool | Description | Parameters |
|------|-------------|------------|
| `scan_ports` | Scan specific ports | targets, ports, timeout |
| `quick_scan` | Fast scan top ports | targets |
| `service_detection` | Detect services | targets, ports |
| `network_discovery` | Discover devices | network, quickMode |
| `vulnerability_scan` | Find vulnerabilities | targets |

## Security Considerations

### Authentication

Implement API key authentication:
```javascript
// Client
const headers = {
  'Authorization': 'Bearer YOUR_API_KEY',
  'Content-Type': 'application/json'
};
```

### Rate Limiting

Configure rate limits:
```json
{
  "rateLimit": {
    "windowMs": 60000,
    "maxRequests": 100,
    "message": "Too many requests"
  }
}
```

### Input Validation

All inputs are validated:
- IP addresses: IPv4/IPv6 format
- Ports: 1-65535 range
- Networks: CIDR notation
- Timeouts: Reasonable limits

### Audit Logging

Enable comprehensive logging:
```bash
export AUDIT_LOG=/var/log/rmap/audit.log
export LOG_ALL_SCANS=true
export LOG_USER_AGENTS=true
```

## Support

- **GitHub Issues**: https://github.com/Ununp3ntium115/R-map/issues
- **Documentation**: https://github.com/Ununp3ntium115/R-map/wiki
- **PYRO Platform**: https://github.com/Ununp3ntium115/PYRO_Platform_Ignition

## License

R-Map PYRO Integration is licensed under the MIT License.

---

## Quick Reference Card

### Start All Services
```bash
./scripts/start_pyro_integration.ps1
```

### Stop All Services
```bash
# Press any key in the startup window
# Or manually:
Get-Process | Where-Object {$_.Name -like "*node*"} | Stop-Process
```

### Test Installation
```bash
./test_pyro_integration.ps1
```

### View Logs
```bash
tail -f logs/api-server.log
tail -f logs/mcp-server.log
```

### Common Scan Commands
```bash
# Quick scan
curl -X POST localhost:8080/api/scan -d '{"targets":["192.168.1.1"]}'

# Full scan
curl -X POST localhost:8080/api/scan -d '{"targets":["192.168.1.0/24"],"ports":"1-65535"}'

# Service detection
curl -X POST localhost:8080/api/vulnerability -d '{"targets":["192.168.1.1"]}'
```

---

**Version**: 1.0.0
**Last Updated**: November 2024
**Authors**: PYRO Platform Team