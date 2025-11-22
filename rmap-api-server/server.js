/**
 * R-Map REST API Server
 * Provides HTTP/WebSocket interface for PYRO Platform integration
 */

const express = require('express');
const cors = require('cors');
const WebSocket = require('ws');
const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs').promises;
const crypto = require('crypto');

const app = express();
const PORT = process.env.PORT || 8080;
const RMAP_PATH = process.env.RMAP_PATH || path.join(__dirname, '../target/release/rmap.exe');

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.static('public'));

// In-memory storage for active scans
const activeScans = new Map();
const scanHistory = [];

// WebSocket server
const wss = new WebSocket.Server({ noServer: true });

// Connected clients
const clients = new Set();

// Broadcast to all connected clients
function broadcast(data) {
  const message = JSON.stringify(data);
  clients.forEach(client => {
    if (client.readyState === WebSocket.OPEN) {
      client.send(message);
    }
  });
}

// Execute R-Map scan
async function executeScan(scanId, args) {
  return new Promise((resolve, reject) => {
    const scan = spawn(RMAP_PATH, args);
    const startTime = Date.now();

    let output = '';
    let error = '';
    let lastProgress = 0;

    // Store active scan
    activeScans.set(scanId, {
      process: scan,
      startTime,
      status: 'running',
      args
    });

    // Broadcast scan start
    broadcast({
      type: 'scan_started',
      scanId,
      timestamp: new Date().toISOString()
    });

    scan.stdout.on('data', (data) => {
      output += data.toString();

      // Parse progress if available
      const progressMatch = data.toString().match(/(\d+)%/);
      if (progressMatch) {
        const progress = parseInt(progressMatch[1]);
        if (progress > lastProgress) {
          lastProgress = progress;
          broadcast({
            type: 'scan_progress',
            scanId,
            progress
          });
        }
      }
    });

    scan.stderr.on('data', (data) => {
      error += data.toString();
      console.error(`Scan ${scanId} error:`, data.toString());
    });

    scan.on('close', (code) => {
      const endTime = Date.now();
      const duration = (endTime - startTime) / 1000;

      activeScans.delete(scanId);

      if (code === 0) {
        // Parse output if JSON
        let result = output;
        try {
          if (args.includes('json')) {
            const jsonMatch = output.match(/\{[\s\S]*\}/);
            if (jsonMatch) {
              result = JSON.parse(jsonMatch[0]);
            }
          }
        } catch (e) {
          console.error('Failed to parse JSON output:', e);
        }

        // Save to history
        const historyEntry = {
          scanId,
          timestamp: new Date(startTime).toISOString(),
          duration,
          args: args.join(' '),
          status: 'completed',
          resultSummary: typeof result === 'object' ?
            `${result.hosts?.length || 0} hosts found` :
            'Scan completed'
        };
        scanHistory.push(historyEntry);

        // Broadcast completion
        broadcast({
          type: 'scan_complete',
          scanId,
          duration,
          result
        });

        resolve({ success: true, result, duration });
      } else {
        const errorMsg = error || output || `Scan failed with code ${code}`;

        broadcast({
          type: 'scan_error',
          scanId,
          error: errorMsg
        });

        reject(new Error(errorMsg));
      }
    });

    scan.on('error', (err) => {
      activeScans.delete(scanId);
      broadcast({
        type: 'scan_error',
        scanId,
        error: err.message
      });
      reject(err);
    });
  });
}

// API Routes

// Health check
app.get('/health', (req, res) => {
  res.json({
    status: 'healthy',
    version: '1.0.0',
    rmap: RMAP_PATH,
    activeScans: activeScans.size,
    connectedClients: clients.size
  });
});

// Start a new scan
app.post('/api/scan', async (req, res) => {
  const {
    targets = [],
    ports = '1-1000',
    timeout = 3,
    serviceDetection = false,
    outputFormat = 'json'
  } = req.body;

  if (!targets.length) {
    return res.status(400).json({ error: 'No targets specified' });
  }

  const scanId = crypto.randomBytes(16).toString('hex');
  const tempFile = path.join(__dirname, 'temp', `scan_${scanId}.json`);

  // Ensure temp directory exists
  await fs.mkdir(path.dirname(tempFile), { recursive: true });

  // Build R-Map arguments
  const args = [
    ...targets,
    '-p', ports,
    '-t', timeout.toString(),
    '-o', outputFormat,
    '-f', tempFile
  ];

  if (serviceDetection) {
    args.push('-A');
  }

  try {
    // Execute scan asynchronously
    executeScan(scanId, args).catch(console.error);

    // Return scan ID immediately
    res.json({
      scanId,
      status: 'started',
      message: 'Scan initiated successfully'
    });
  } catch (error) {
    res.status(500).json({
      error: 'Failed to start scan',
      details: error.message
    });
  }
});

// Get scan status
app.get('/api/scan/:id', async (req, res) => {
  const { id } = req.params;
  const scan = activeScans.get(id);

  if (scan) {
    res.json({
      scanId: id,
      status: scan.status,
      startTime: new Date(scan.startTime).toISOString(),
      duration: (Date.now() - scan.startTime) / 1000
    });
  } else {
    // Check history
    const historicalScan = scanHistory.find(s => s.scanId === id);
    if (historicalScan) {
      res.json(historicalScan);
    } else {
      res.status(404).json({ error: 'Scan not found' });
    }
  }
});

// Stop a scan
app.post('/api/scan/:id/stop', (req, res) => {
  const { id } = req.params;
  const scan = activeScans.get(id);

  if (scan && scan.process) {
    scan.process.kill('SIGTERM');
    activeScans.delete(id);

    broadcast({
      type: 'scan_stopped',
      scanId: id
    });

    res.json({
      scanId: id,
      status: 'stopped',
      message: 'Scan terminated successfully'
    });
  } else {
    res.status(404).json({ error: 'Active scan not found' });
  }
});

// Get scan history
app.get('/api/history', (req, res) => {
  const { limit = 10 } = req.query;
  const history = scanHistory.slice(-limit).reverse();
  res.json(history);
});

// Network discovery
app.post('/api/discover', async (req, res) => {
  const { network, quickMode = true } = req.body;

  if (!network) {
    return res.status(400).json({ error: 'Network not specified' });
  }

  const scanId = crypto.randomBytes(16).toString('hex');
  const ports = quickMode ? '22,80,443,445,3389' : '1-1000';

  const args = [
    network,
    '-p', ports,
    '-t', '2',
    '-o', 'json',
    '-f', `temp/discover_${scanId}.json`
  ];

  try {
    executeScan(scanId, args).catch(console.error);
    res.json({
      scanId,
      status: 'discovering',
      network,
      mode: quickMode ? 'quick' : 'full'
    });
  } catch (error) {
    res.status(500).json({
      error: 'Discovery failed',
      details: error.message
    });
  }
});

// Vulnerability scan
app.post('/api/vulnerability', async (req, res) => {
  const { targets = [] } = req.body;

  if (!targets.length) {
    return res.status(400).json({ error: 'No targets specified' });
  }

  const scanId = crypto.randomBytes(16).toString('hex');

  // Scan common vulnerable ports
  const vulnPorts = '21,22,23,25,53,69,79,80,110,111,135,139,143,161,389,443,445,512,513,514,1433,1521,3306,3389,5432,5900,5984,6379,8020,8080,8443,9200,27017';

  const args = [
    ...targets,
    '-p', vulnPorts,
    '-A', // Service detection
    '-t', '5',
    '-o', 'json',
    '-f', `temp/vuln_${scanId}.json`
  ];

  try {
    const scanPromise = executeScan(scanId, args);

    // Don't wait, return immediately
    scanPromise.then(({ result }) => {
      // Analyze for vulnerabilities
      const vulnerabilities = analyzeVulnerabilities(result);

      broadcast({
        type: 'vulnerability_analysis',
        scanId,
        vulnerabilities
      });
    }).catch(console.error);

    res.json({
      scanId,
      status: 'analyzing',
      message: 'Vulnerability scan started'
    });
  } catch (error) {
    res.status(500).json({
      error: 'Vulnerability scan failed',
      details: error.message
    });
  }
});

// Analyze scan results for vulnerabilities
function analyzeVulnerabilities(scanData) {
  const vulnerabilities = [];

  if (!scanData.hosts) return vulnerabilities;

  scanData.hosts.forEach(host => {
    host.ports?.forEach(port => {
      if (port.state === 'open') {
        // Check for known vulnerable services
        const vulnChecks = [
          { port: 21, service: 'FTP', risk: 'HIGH', issue: 'Unencrypted file transfer' },
          { port: 23, service: 'Telnet', risk: 'CRITICAL', issue: 'Unencrypted remote access' },
          { port: 139, service: 'NetBIOS', risk: 'HIGH', issue: 'Legacy protocol exposure' },
          { port: 445, service: 'SMB', risk: 'HIGH', issue: 'File sharing exposed' },
          { port: 3389, service: 'RDP', risk: 'HIGH', issue: 'Remote desktop exposed' },
          { port: 5900, service: 'VNC', risk: 'HIGH', issue: 'Remote desktop exposed' },
          { port: 3306, service: 'MySQL', risk: 'MEDIUM', issue: 'Database exposed' },
          { port: 5432, service: 'PostgreSQL', risk: 'MEDIUM', issue: 'Database exposed' },
          { port: 6379, service: 'Redis', risk: 'HIGH', issue: 'In-memory database exposed' },
          { port: 9200, service: 'Elasticsearch', risk: 'HIGH', issue: 'Search engine exposed' },
          { port: 27017, service: 'MongoDB', risk: 'HIGH', issue: 'NoSQL database exposed' }
        ];

        const vuln = vulnChecks.find(v => v.port === port.port);
        if (vuln) {
          vulnerabilities.push({
            host: host.target,
            port: port.port,
            service: vuln.service,
            risk: vuln.risk,
            issue: vuln.issue,
            version: port.version || 'Unknown',
            recommendation: getRecommendation(vuln.service)
          });
        }
      }
    });
  });

  return vulnerabilities;
}

function getRecommendation(service) {
  const recommendations = {
    'FTP': 'Use SFTP or FTPS with encryption',
    'Telnet': 'Disable and use SSH instead',
    'NetBIOS': 'Disable if not required, use firewall rules',
    'SMB': 'Restrict access, use SMBv3 with encryption',
    'RDP': 'Use VPN, enable NLA, restrict access',
    'VNC': 'Use SSH tunneling or VPN',
    'MySQL': 'Bind to localhost, use SSL, strong passwords',
    'PostgreSQL': 'Use SSL, restrict pg_hba.conf',
    'Redis': 'Bind to localhost, require authentication',
    'Elasticsearch': 'Enable authentication, use TLS',
    'MongoDB': 'Enable authentication, bind to localhost'
  };
  return recommendations[service] || 'Review security configuration';
}

// WebSocket connection handling
app.server = app.listen(PORT, () => {
  console.log(`R-Map API Server running on port ${PORT}`);
  console.log(`WebSocket server ready for connections`);
  console.log(`R-Map path: ${RMAP_PATH}`);
});

app.server.on('upgrade', (request, socket, head) => {
  wss.handleUpgrade(request, socket, head, (ws) => {
    wss.emit('connection', ws, request);
  });
});

wss.on('connection', (ws) => {
  clients.add(ws);
  console.log(`New WebSocket client connected (total: ${clients.size})`);

  // Send welcome message
  ws.send(JSON.stringify({
    type: 'connected',
    message: 'Connected to R-Map API Server',
    timestamp: new Date().toISOString()
  }));

  // Handle messages from client
  ws.on('message', async (data) => {
    try {
      const message = JSON.parse(data.toString());
      handleWebSocketMessage(ws, message);
    } catch (error) {
      ws.send(JSON.stringify({
        type: 'error',
        message: 'Invalid message format',
        error: error.message
      }));
    }
  });

  ws.on('close', () => {
    clients.delete(ws);
    console.log(`Client disconnected (remaining: ${clients.size})`);
  });

  ws.on('error', (error) => {
    console.error('WebSocket error:', error);
    clients.delete(ws);
  });
});

// Handle WebSocket messages
async function handleWebSocketMessage(ws, message) {
  switch (message.type) {
    case 'scan_request':
      // Start scan via WebSocket
      const { targets, ports, timeout, serviceDetection } = message.arguments || {};

      if (!targets?.length) {
        ws.send(JSON.stringify({
          type: 'error',
          message: 'No targets specified'
        }));
        return;
      }

      const scanId = crypto.randomBytes(16).toString('hex');
      const tempFile = path.join(__dirname, 'temp', `ws_scan_${scanId}.json`);

      await fs.mkdir(path.dirname(tempFile), { recursive: true });

      const args = [
        ...targets,
        '-p', ports || '1-1000',
        '-t', (timeout || 3).toString(),
        '-o', 'json',
        '-f', tempFile
      ];

      if (serviceDetection) {
        args.push('-A');
      }

      executeScan(scanId, args)
        .then(({ result, duration }) => {
          ws.send(JSON.stringify({
            type: 'scan_result',
            scanId,
            result,
            duration
          }));
        })
        .catch(error => {
          ws.send(JSON.stringify({
            type: 'scan_error',
            scanId,
            error: error.message
          }));
        });

      ws.send(JSON.stringify({
        type: 'scan_started',
        scanId,
        message: 'Scan initiated'
      }));
      break;

    case 'stop_scan':
      const stopScanId = message.scanId;
      const scan = activeScans.get(stopScanId);

      if (scan && scan.process) {
        scan.process.kill('SIGTERM');
        activeScans.delete(stopScanId);

        ws.send(JSON.stringify({
          type: 'scan_stopped',
          scanId: stopScanId,
          message: 'Scan terminated'
        }));
      }
      break;

    case 'get_history':
      ws.send(JSON.stringify({
        type: 'history',
        data: scanHistory.slice(-10).reverse()
      }));
      break;

    default:
      ws.send(JSON.stringify({
        type: 'error',
        message: `Unknown message type: ${message.type}`
      }));
  }
}

// Cleanup on exit
process.on('SIGINT', () => {
  console.log('\nShutting down R-Map API Server...');

  // Kill all active scans
  activeScans.forEach((scan, id) => {
    if (scan.process) {
      scan.process.kill('SIGTERM');
    }
  });

  // Close WebSocket connections
  clients.forEach(client => {
    client.close();
  });

  process.exit(0);
});

module.exports = app;