# R-Map Integration with PYRO Platform Ignition

## Overview

R-Map serves as the **Network Discovery and Scanning Module** for the PYRO Platform Ignition system. It provides comprehensive network reconnaissance capabilities to identify hard and soft targets for deployment, evidence gathering, and security assessment.

## Architecture

```
PYRO Platform Ignition
│
├── R-Map MCP Server (Network Scanner)
│   ├── Port Scanning
│   ├── Service Detection
│   ├── Vulnerability Assessment
│   └── Target Discovery
│
├── R-Map Svelte UI
│   ├── Zenmap-like Interface
│   ├── Real-time Scanning
│   ├── Result Visualization
│   └── Export Capabilities
│
└── Integration Points
    ├── WebSocket Communication
    ├── REST API
    └── MCP Protocol
```

## Features

### 1. Network Discovery
- **Subnet Scanning**: Discover all devices on a network
- **Host Detection**: Identify live hosts
- **Device Fingerprinting**: Determine device types and OS

### 2. Port Scanning
- **TCP Connect Scans**: Standard port scanning
- **Service Detection**: Identify running services
- **Version Detection**: Determine service versions

### 3. Target Classification
- **Hard Targets**: Servers, routers, firewalls
- **Soft Targets**: Workstations, IoT devices, printers
- **Vulnerability Assessment**: Identify exposed services

### 4. Integration Capabilities
- **Real-time Updates**: WebSocket streaming of scan progress
- **Batch Operations**: Scan multiple networks simultaneously
- **Result Storage**: Save scan results for analysis

## Installation

### 1. R-Map Core
```bash
# Build R-Map
cd R-map
cargo build --release

# Verify installation
./target/release/rmap.exe --version
```

### 2. MCP Server
```bash
cd rmap-mcp-server
npm install
npm run build
npm start
```

### 3. Svelte UI
```bash
cd rmap-ui
npm install
npm run dev
```

## MCP Server API

### Available Tools

#### 1. `scan_ports`
Scan specific ports on target hosts.

**Parameters:**
- `targets`: Array of target hosts/networks
- `ports`: Port specification (e.g., "22,80,443" or "1-1000")
- `timeout`: Connection timeout in seconds (default: 3)
- `outputFormat`: "json" | "xml" | "normal"

**Example:**
```json
{
  "tool": "scan_ports",
  "arguments": {
    "targets": ["192.168.1.0/24"],
    "ports": "22,80,443",
    "timeout": 3,
    "outputFormat": "json"
  }
}
```

#### 2. `quick_scan`
Fast scan of top 20 most common ports.

**Parameters:**
- `targets`: Array of target hosts/networks

#### 3. `service_detection`
Scan with service/version detection enabled.

**Parameters:**
- `targets`: Array of target hosts/networks
- `ports`: Ports to scan (optional)

#### 4. `network_discovery`
Discover all devices on a network.

**Parameters:**
- `network`: Network in CIDR notation
- `quickMode`: Use fast discovery (default: true)

#### 5. `vulnerability_scan`
Scan for commonly vulnerable services.

**Parameters:**
- `targets`: Array of target hosts

## REST API Endpoints

### `POST /api/rmap/scan`
Execute a network scan.

**Request Body:**
```json
{
  "targets": ["192.168.1.1", "scanme.nmap.org"],
  "ports": "1-1000",
  "timeout": 5,
  "serviceDetection": true
}
```

**Response:**
```json
{
  "scan_id": "uuid",
  "status": "completed",
  "results": {
    "hosts": [...],
    "scan_info": {...}
  }
}
```

### `GET /api/rmap/scan/:id`
Get scan status and results.

### `POST /api/rmap/stop`
Stop active scan.

### `GET /api/rmap/history`
Get scan history.

## WebSocket Events

### Client → Server

#### `scan_request`
```json
{
  "type": "scan_request",
  "tool": "scan_ports",
  "arguments": {...}
}
```

#### `stop_scan`
```json
{
  "type": "stop_scan"
}
```

### Server → Client

#### `scan_progress`
```json
{
  "type": "scan_progress",
  "progress": 45,
  "current": "192.168.1.45",
  "total": 254
}
```

#### `scan_result`
```json
{
  "type": "scan_result",
  "result": {
    "hosts": [...],
    "scan_info": {...}
  }
}
```

#### `scan_complete`
```json
{
  "type": "scan_complete",
  "scan_id": "uuid",
  "duration": 120.5
}
```

## Integration with PYRO Platform

### 1. Service Discovery for Deployment

```javascript
// Discover services on target network
const targets = await rmapClient.networkDiscovery('192.168.1.0/24');

// Filter deployment candidates
const deploymentTargets = targets.filter(host => {
  return host.ports.some(port =>
    port.state === 'open' &&
    [22, 3389, 5985].includes(port.port) // SSH, RDP, WinRM
  );
});
```

### 2. Evidence Gathering

```javascript
// Comprehensive scan for evidence collection
const evidence = await rmapClient.vulnerabilityScan(suspectHosts);

// Export results for reporting
await rmapClient.exportResults(evidence, 'evidence_report.json');
```

### 3. Security Assessment

```javascript
// Identify vulnerable services
const vulnerabilities = await rmapClient.vulnerabilityScan(networkRange);

// Generate security report
const report = generateSecurityReport(vulnerabilities);
```

## Svelte UI Integration

### Import Component

```svelte
<script>
  import RMapScanner from './RMapScanner.svelte';
</script>

<RMapScanner
  on:scanComplete={handleScanComplete}
  on:targetSelected={handleTargetSelected}
/>
```

### Handle Events

```javascript
function handleScanComplete(event) {
  const { results } = event.detail;
  // Process scan results
  console.log(`Found ${results.length} hosts`);
}

function handleTargetSelected(event) {
  const { host } = event.detail;
  // Deploy to selected target
  deployPackage(host.target);
}
```

## Security Considerations

### 1. Authentication
- Implement API key authentication for MCP server
- Use JWT tokens for session management
- Require authorization for scan operations

### 2. Rate Limiting
- Limit concurrent scans per user
- Implement scan quotas
- Throttle API requests

### 3. Input Validation
- Validate target specifications
- Sanitize port ranges
- Prevent SSRF attacks

### 4. Logging
- Log all scan operations
- Track user activities
- Monitor for abuse patterns

## Deployment

### Docker Deployment

```yaml
version: '3.8'
services:
  rmap-mcp:
    build: ./rmap-mcp-server
    ports:
      - "8080:8080"
    environment:
      - RMAP_PATH=/usr/local/bin/rmap
    volumes:
      - ./rmap:/usr/local/bin/rmap:ro

  rmap-ui:
    build: ./rmap-ui
    ports:
      - "3000:3000"
    depends_on:
      - rmap-mcp
```

### Kubernetes Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rmap-scanner
spec:
  replicas: 3
  selector:
    matchLabels:
      app: rmap-scanner
  template:
    metadata:
      labels:
        app: rmap-scanner
    spec:
      containers:
      - name: rmap-mcp
        image: pyro-platform/rmap-mcp:latest
        ports:
        - containerPort: 8080
```

## Monitoring

### Metrics
- Scans per minute
- Average scan duration
- Port discovery rate
- Service detection accuracy

### Alerts
- Failed scan threshold exceeded
- Unusual target patterns
- Resource exhaustion
- Security violations

## Use Cases

### 1. Network Inventory
- Discover all devices on corporate network
- Maintain asset database
- Track changes over time

### 2. Security Auditing
- Identify exposed services
- Find vulnerable systems
- Compliance checking

### 3. Deployment Targeting
- Find suitable hosts for package deployment
- Verify connectivity before deployment
- Validate service availability

### 4. Incident Response
- Quick network reconnaissance
- Identify compromised systems
- Track lateral movement

## Troubleshooting

### Common Issues

#### R-Map not found
```bash
# Set environment variable
export RMAP_PATH=/path/to/rmap
```

#### Permission denied
```bash
# Run with elevated privileges for SYN scanning
sudo npm start
```

#### Port already in use
```bash
# Change MCP server port
export MCP_PORT=8081
```

## Support

- **GitHub Issues**: https://github.com/Ununp3ntium115/R-map
- **PYRO Platform**: https://github.com/Ununp3ntium115/PYRO_Platform_Ignition
- **Documentation**: See `/docs` directory

---

## Quick Start Example

```javascript
// Initialize R-Map client
import { RMapClient } from '@pyro/rmap-client';

const rmap = new RMapClient({
  server: 'ws://localhost:8080',
  apiKey: process.env.RMAP_API_KEY
});

// Discover network
const targets = await rmap.discoverNetwork('192.168.1.0/24');

// Scan specific targets
const results = await rmap.scanPorts(
  targets.map(t => t.ip),
  '22,80,443,3389'
);

// Find deployment candidates
const deployable = results.filter(host =>
  host.hasService('ssh') || host.hasService('rdp')
);

// Deploy packages
for (const target of deployable) {
  await deployPackage(target);
}
```

---

**R-Map** is now fully integrated with **PYRO Platform Ignition** as the primary network scanning and discovery module, providing comprehensive reconnaissance capabilities for all platform operations.