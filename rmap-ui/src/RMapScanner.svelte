<script>
  import { onMount } from 'svelte';
  import { writable } from 'svelte/store';

  // State management
  let targets = '';
  let scanProfile = 'quick';
  let customPorts = '';
  let isScanning = false;
  let scanProgress = 0;
  let scanResults = [];
  let selectedHost = null;
  let logMessages = [];
  let scanHistory = [];

  // Scan profiles (similar to Zenmap)
  const scanProfiles = {
    quick: {
      name: 'Quick Scan',
      ports: '21,22,23,25,53,80,110,111,135,139,143,443,445,993,995,1723,3306,3389,5900,8080',
      description: 'Fast scan of most common ports',
      timeout: 3,
    },
    intense: {
      name: 'Intense Scan',
      ports: '1-1000',
      description: 'Comprehensive scan of first 1000 ports',
      timeout: 5,
      serviceDetection: true,
    },
    regular: {
      name: 'Regular Scan',
      ports: '1-65535',
      description: 'Complete port range scan',
      timeout: 5,
    },
    vulnerability: {
      name: 'Vulnerability Scan',
      ports: '21,22,23,25,53,69,79,80,110,111,135,139,143,161,389,443,445,512,513,514,1433,1521,3306,3389,5432,5900,5984,6379,8020,8080,8443,9200,27017',
      description: 'Scan for commonly vulnerable services',
      timeout: 5,
      serviceDetection: true,
    },
    custom: {
      name: 'Custom Scan',
      ports: '',
      description: 'User-defined port specification',
      timeout: 3,
    },
  };

  // WebSocket connection to MCP server
  let ws = null;

  onMount(() => {
    connectToMCPServer();
    loadScanHistory();
  });

  function connectToMCPServer() {
    ws = new WebSocket('ws://localhost:8080/rmap-mcp');

    ws.onopen = () => {
      addLog('Connected to R-Map MCP Server', 'success');
    };

    ws.onmessage = (event) => {
      const message = JSON.parse(event.data);
      handleMCPMessage(message);
    };

    ws.onerror = (error) => {
      addLog(`Connection error: ${error}`, 'error');
    };

    ws.onclose = () => {
      addLog('Disconnected from MCP Server', 'warning');
      // Attempt reconnection after 5 seconds
      setTimeout(connectToMCPServer, 5000);
    };
  }

  function handleMCPMessage(message) {
    switch (message.type) {
      case 'scan_progress':
        scanProgress = message.progress;
        break;
      case 'scan_result':
        processScanResult(message.result);
        break;
      case 'scan_complete':
        isScanning = false;
        scanProgress = 100;
        addLog('Scan completed successfully', 'success');
        saveScanToHistory();
        break;
      case 'scan_error':
        isScanning = false;
        addLog(`Scan error: ${message.error}`, 'error');
        break;
      case 'log':
        addLog(message.message, message.level);
        break;
    }
  }

  async function startScan() {
    if (!targets.trim()) {
      addLog('Please enter target hosts', 'error');
      return;
    }

    isScanning = true;
    scanProgress = 0;
    scanResults = [];
    selectedHost = null;

    const profile = scanProfiles[scanProfile];
    const ports = scanProfile === 'custom' ? customPorts : profile.ports;

    if (!ports) {
      addLog('Please specify ports to scan', 'error');
      isScanning = false;
      return;
    }

    addLog(`Starting ${profile.name} on ${targets}`, 'info');

    // Send scan request via MCP
    const scanRequest = {
      type: 'scan_request',
      tool: profile.serviceDetection ? 'service_detection' : 'scan_ports',
      arguments: {
        targets: targets.split(/[,\s]+/).filter(t => t),
        ports: ports,
        timeout: profile.timeout,
        outputFormat: 'json',
      },
    };

    if (ws && ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify(scanRequest));
    } else {
      // Fallback to REST API
      await executeScanViaAPI(scanRequest);
    }
  }

  async function executeScanViaAPI(request) {
    try {
      const response = await fetch('/api/rmap/scan', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(request.arguments),
      });

      if (response.ok) {
        const result = await response.json();
        processScanResult(result);
        isScanning = false;
        scanProgress = 100;
      } else {
        throw new Error(`Scan failed: ${response.statusText}`);
      }
    } catch (error) {
      addLog(`API error: ${error.message}`, 'error');
      isScanning = false;
    }
  }

  function processScanResult(result) {
    if (result.hosts) {
      scanResults = result.hosts.map(host => ({
        ...host,
        id: `${host.target}_${Date.now()}`,
        openPorts: host.ports.filter(p => p.state === 'open').length,
        closedPorts: host.ports.filter(p => p.state === 'closed').length,
      }));
    }
  }

  function stopScan() {
    if (ws && ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify({ type: 'stop_scan' }));
    }
    isScanning = false;
    addLog('Scan stopped by user', 'warning');
  }

  function selectHost(host) {
    selectedHost = host;
  }

  function addLog(message, level = 'info') {
    const timestamp = new Date().toLocaleTimeString();
    logMessages = [...logMessages, { timestamp, message, level }];

    // Keep only last 100 messages
    if (logMessages.length > 100) {
      logMessages = logMessages.slice(-100);
    }
  }

  function clearResults() {
    scanResults = [];
    selectedHost = null;
    logMessages = [];
    scanProgress = 0;
  }

  function exportResults() {
    const data = {
      scan_date: new Date().toISOString(),
      targets: targets,
      profile: scanProfiles[scanProfile].name,
      results: scanResults,
    };

    const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `rmap_scan_${Date.now()}.json`;
    a.click();
    URL.revokeObjectURL(url);
  }

  function saveScanToHistory() {
    const historyEntry = {
      id: Date.now(),
      date: new Date().toISOString(),
      targets: targets,
      profile: scanProfiles[scanProfile].name,
      hostsFound: scanResults.length,
      openPorts: scanResults.reduce((sum, host) => sum + host.openPorts, 0),
    };

    scanHistory = [historyEntry, ...scanHistory].slice(0, 10);
    localStorage.setItem('rmap_scan_history', JSON.stringify(scanHistory));
  }

  function loadScanHistory() {
    const saved = localStorage.getItem('rmap_scan_history');
    if (saved) {
      scanHistory = JSON.parse(saved);
    }
  }

  function getPortStateColor(state) {
    switch (state) {
      case 'open': return '#4ade80';
      case 'closed': return '#ef4444';
      case 'filtered': return '#fbbf24';
      default: return '#9ca3af';
    }
  }

  function getLogColor(level) {
    switch (level) {
      case 'success': return '#4ade80';
      case 'error': return '#ef4444';
      case 'warning': return '#fbbf24';
      case 'info': return '#60a5fa';
      default: return '#e5e7eb';
    }
  }
</script>

<div class="rmap-scanner">
  <!-- Header -->
  <div class="header">
    <h1>🦀 R-Map Network Scanner</h1>
    <p class="subtitle">PYRO Platform Integration - Network Discovery Module</p>
  </div>

  <!-- Control Panel -->
  <div class="control-panel">
    <div class="scan-inputs">
      <div class="input-group">
        <label for="targets">Target(s):</label>
        <input
          id="targets"
          type="text"
          bind:value={targets}
          placeholder="e.g., 192.168.1.0/24, scanme.nmap.org, 10.0.0.1"
          disabled={isScanning}
        />
      </div>

      <div class="input-group">
        <label for="profile">Scan Profile:</label>
        <select id="profile" bind:value={scanProfile} disabled={isScanning}>
          {#each Object.entries(scanProfiles) as [key, profile]}
            <option value={key}>{profile.name}</option>
          {/each}
        </select>
      </div>

      {#if scanProfile === 'custom'}
        <div class="input-group">
          <label for="ports">Custom Ports:</label>
          <input
            id="ports"
            type="text"
            bind:value={customPorts}
            placeholder="e.g., 22,80,443 or 1-1000"
            disabled={isScanning}
          />
        </div>
      {/if}

      <div class="profile-info">
        <small>{scanProfiles[scanProfile].description}</small>
        {#if scanProfile !== 'custom'}
          <small>Ports: {scanProfiles[scanProfile].ports}</small>
        {/if}
      </div>
    </div>

    <div class="scan-controls">
      {#if !isScanning}
        <button class="btn-primary" on:click={startScan}>
          Start Scan
        </button>
      {:else}
        <button class="btn-danger" on:click={stopScan}>
          Stop Scan
        </button>
      {/if}
      <button class="btn-secondary" on:click={clearResults} disabled={isScanning}>
        Clear
      </button>
      <button class="btn-secondary" on:click={exportResults} disabled={scanResults.length === 0}>
        Export
      </button>
    </div>

    {#if isScanning}
      <div class="progress-bar">
        <div class="progress-fill" style="width: {scanProgress}%"></div>
        <span class="progress-text">{scanProgress}%</span>
      </div>
    {/if}
  </div>

  <!-- Results Section -->
  <div class="results-section">
    <!-- Host List -->
    <div class="host-list">
      <h3>Discovered Hosts ({scanResults.length})</h3>
      <div class="host-list-container">
        {#each scanResults as host}
          <div
            class="host-item"
            class:selected={selectedHost?.id === host.id}
            on:click={() => selectHost(host)}
          >
            <div class="host-info">
              <strong>{host.target}</strong>
              {#if host.hostname}
                <small>({host.hostname})</small>
              {/if}
            </div>
            <div class="host-stats">
              <span class="open-ports">{host.openPorts} open</span>
              <span class="closed-ports">{host.closedPorts} closed</span>
            </div>
          </div>
        {/each}
      </div>
    </div>

    <!-- Port Details -->
    <div class="port-details">
      <h3>Port Details</h3>
      {#if selectedHost}
        <div class="port-list">
          <table>
            <thead>
              <tr>
                <th>Port</th>
                <th>State</th>
                <th>Service</th>
                <th>Version</th>
              </tr>
            </thead>
            <tbody>
              {#each selectedHost.ports as port}
                <tr>
                  <td>{port.port}/{port.protocol}</td>
                  <td>
                    <span style="color: {getPortStateColor(port.state)}">
                      {port.state}
                    </span>
                  </td>
                  <td>{port.service || '-'}</td>
                  <td>{port.version || '-'}</td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
      {:else}
        <div class="no-selection">
          Select a host to view port details
        </div>
      {/if}
    </div>
  </div>

  <!-- Log Console -->
  <div class="log-console">
    <h3>Console Output</h3>
    <div class="log-container">
      {#each logMessages as log}
        <div class="log-entry">
          <span class="log-time">{log.timestamp}</span>
          <span class="log-message" style="color: {getLogColor(log.level)}">
            {log.message}
          </span>
        </div>
      {/each}
    </div>
  </div>

  <!-- Scan History -->
  <div class="scan-history">
    <h3>Recent Scans</h3>
    <div class="history-list">
      {#each scanHistory as entry}
        <div class="history-item">
          <span>{new Date(entry.date).toLocaleString()}</span>
          <span>{entry.targets}</span>
          <span>{entry.profile}</span>
          <span>{entry.hostsFound} hosts, {entry.openPorts} open ports</span>
        </div>
      {/each}
    </div>
  </div>
</div>

<style>
  .rmap-scanner {
    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
    background: #1a1a1a;
    color: #e5e7eb;
    padding: 20px;
    min-height: 100vh;
  }

  .header {
    text-align: center;
    margin-bottom: 30px;
    padding: 20px;
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    border-radius: 10px;
  }

  .header h1 {
    margin: 0;
    font-size: 2.5em;
    color: white;
  }

  .subtitle {
    margin: 5px 0 0 0;
    color: rgba(255, 255, 255, 0.9);
  }

  .control-panel {
    background: #2a2a2a;
    padding: 20px;
    border-radius: 8px;
    margin-bottom: 20px;
  }

  .scan-inputs {
    display: grid;
    gap: 15px;
    margin-bottom: 20px;
  }

  .input-group {
    display: flex;
    flex-direction: column;
    gap: 5px;
  }

  .input-group label {
    font-weight: 600;
    color: #9ca3af;
  }

  .input-group input,
  .input-group select {
    padding: 8px 12px;
    background: #1a1a1a;
    border: 1px solid #4a5568;
    border-radius: 4px;
    color: #e5e7eb;
    font-size: 14px;
  }

  .input-group input:focus,
  .input-group select:focus {
    outline: none;
    border-color: #667eea;
  }

  .profile-info {
    display: flex;
    flex-direction: column;
    gap: 5px;
    padding: 10px;
    background: #1a1a1a;
    border-radius: 4px;
    font-size: 12px;
    color: #9ca3af;
  }

  .scan-controls {
    display: flex;
    gap: 10px;
    margin-bottom: 15px;
  }

  .btn-primary,
  .btn-secondary,
  .btn-danger {
    padding: 10px 20px;
    border: none;
    border-radius: 4px;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.3s;
  }

  .btn-primary {
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    color: white;
  }

  .btn-secondary {
    background: #4a5568;
    color: #e5e7eb;
  }

  .btn-danger {
    background: #ef4444;
    color: white;
  }

  .btn-primary:hover,
  .btn-secondary:hover,
  .btn-danger:hover {
    opacity: 0.9;
    transform: translateY(-2px);
  }

  .btn-primary:disabled,
  .btn-secondary:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .progress-bar {
    position: relative;
    height: 30px;
    background: #1a1a1a;
    border-radius: 15px;
    overflow: hidden;
  }

  .progress-fill {
    position: absolute;
    top: 0;
    left: 0;
    height: 100%;
    background: linear-gradient(90deg, #667eea 0%, #764ba2 100%);
    transition: width 0.3s ease;
  }

  .progress-text {
    position: absolute;
    top: 50%;
    left: 50%;
    transform: translate(-50%, -50%);
    font-weight: 600;
    color: white;
    z-index: 1;
  }

  .results-section {
    display: grid;
    grid-template-columns: 1fr 2fr;
    gap: 20px;
    margin-bottom: 20px;
  }

  .host-list,
  .port-details {
    background: #2a2a2a;
    padding: 15px;
    border-radius: 8px;
  }

  .host-list h3,
  .port-details h3 {
    margin: 0 0 15px 0;
    color: #e5e7eb;
  }

  .host-list-container {
    max-height: 400px;
    overflow-y: auto;
  }

  .host-item {
    padding: 10px;
    margin-bottom: 5px;
    background: #1a1a1a;
    border-radius: 4px;
    cursor: pointer;
    transition: all 0.2s;
  }

  .host-item:hover {
    background: #374151;
  }

  .host-item.selected {
    background: #4a5568;
    border-left: 3px solid #667eea;
  }

  .host-info {
    margin-bottom: 5px;
  }

  .host-stats {
    display: flex;
    gap: 10px;
    font-size: 12px;
  }

  .open-ports {
    color: #4ade80;
  }

  .closed-ports {
    color: #ef4444;
  }

  .port-list {
    overflow-x: auto;
  }

  .port-list table {
    width: 100%;
    border-collapse: collapse;
  }

  .port-list th {
    background: #1a1a1a;
    padding: 10px;
    text-align: left;
    color: #9ca3af;
  }

  .port-list td {
    padding: 8px 10px;
    border-top: 1px solid #374151;
  }

  .no-selection {
    text-align: center;
    color: #6b7280;
    padding: 50px 20px;
  }

  .log-console,
  .scan-history {
    background: #2a2a2a;
    padding: 15px;
    border-radius: 8px;
    margin-bottom: 20px;
  }

  .log-console h3,
  .scan-history h3 {
    margin: 0 0 15px 0;
    color: #e5e7eb;
  }

  .log-container {
    max-height: 200px;
    overflow-y: auto;
    background: #1a1a1a;
    padding: 10px;
    border-radius: 4px;
    font-family: 'Courier New', monospace;
    font-size: 12px;
  }

  .log-entry {
    margin-bottom: 5px;
  }

  .log-time {
    color: #6b7280;
    margin-right: 10px;
  }

  .history-list {
    display: flex;
    flex-direction: column;
    gap: 5px;
  }

  .history-item {
    display: grid;
    grid-template-columns: 1.5fr 1fr 1fr 1.5fr;
    gap: 10px;
    padding: 8px;
    background: #1a1a1a;
    border-radius: 4px;
    font-size: 12px;
    color: #9ca3af;
  }

  /* Scrollbar styling */
  ::-webkit-scrollbar {
    width: 8px;
    height: 8px;
  }

  ::-webkit-scrollbar-track {
    background: #1a1a1a;
  }

  ::-webkit-scrollbar-thumb {
    background: #4a5568;
    border-radius: 4px;
  }

  ::-webkit-scrollbar-thumb:hover {
    background: #667eea;
  }
</style>