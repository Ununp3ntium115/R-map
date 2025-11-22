/**
 * R-Map MCP Server for PYRO Platform Integration
 * Provides network scanning capabilities via Model Context Protocol
 */

import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  Tool,
} from '@modelcontextprotocol/sdk/types.js';
import { spawn, ChildProcess } from 'child_process';
import * as path from 'path';
import * as fs from 'fs/promises';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Path to R-Map executable
const RMAP_PATH = process.env.RMAP_PATH || path.join(__dirname, '../../../target/release/rmap.exe');

interface ScanResult {
  hosts: Array<{
    target: string;
    hostname?: string;
    ports: Array<{
      port: number;
      protocol: string;
      state: string;
      service?: string;
      version?: string;
    }>;
    scan_time: number;
  }>;
  scan_info: {
    version: string;
    total_hosts: number;
    scan_time: number;
  };
}

class RMapMCPServer {
  private server: Server;
  private activeScan: ChildProcess | null = null;

  constructor() {
    this.server = new Server(
      {
        name: 'rmap-scanner',
        version: '1.0.0',
      },
      {
        capabilities: {
          tools: {},
        },
      }
    );

    this.setupHandlers();
  }

  private setupHandlers() {
    // List available tools
    this.server.setRequestHandler(ListToolsRequestSchema, async () => ({
      tools: this.getTools(),
    }));

    // Handle tool calls
    this.server.setRequestHandler(CallToolRequestSchema, async (request) => {
      switch (request.params.name) {
        case 'scan_ports':
          return await this.scanPorts(request.params.arguments);
        case 'quick_scan':
          return await this.quickScan(request.params.arguments);
        case 'service_detection':
          return await this.serviceDetection(request.params.arguments);
        case 'network_discovery':
          return await this.networkDiscovery(request.params.arguments);
        case 'vulnerability_scan':
          return await this.vulnerabilityScan(request.params.arguments);
        case 'stop_scan':
          return await this.stopScan();
        default:
          throw new Error(`Unknown tool: ${request.params.name}`);
      }
    });
  }

  private getTools(): Tool[] {
    return [
      {
        name: 'scan_ports',
        description: 'Scan specific ports on target hosts',
        inputSchema: {
          type: 'object',
          properties: {
            targets: {
              type: 'array',
              items: { type: 'string' },
              description: 'Target hosts or networks',
            },
            ports: {
              type: 'string',
              description: 'Port specification (e.g., "22,80,443" or "1-1000")',
            },
            timeout: {
              type: 'number',
              description: 'Connection timeout in seconds',
              default: 3,
            },
            outputFormat: {
              type: 'string',
              enum: ['json', 'xml', 'normal'],
              default: 'json',
            },
          },
          required: ['targets', 'ports'],
        },
      },
      {
        name: 'quick_scan',
        description: 'Fast scan of top 100 ports',
        inputSchema: {
          type: 'object',
          properties: {
            targets: {
              type: 'array',
              items: { type: 'string' },
              description: 'Target hosts or networks',
            },
          },
          required: ['targets'],
        },
      },
      {
        name: 'service_detection',
        description: 'Scan with service/version detection',
        inputSchema: {
          type: 'object',
          properties: {
            targets: {
              type: 'array',
              items: { type: 'string' },
              description: 'Target hosts or networks',
            },
            ports: {
              type: 'string',
              description: 'Ports to scan',
            },
          },
          required: ['targets'],
        },
      },
      {
        name: 'network_discovery',
        description: 'Discover devices on a network',
        inputSchema: {
          type: 'object',
          properties: {
            network: {
              type: 'string',
              description: 'Network in CIDR notation (e.g., "192.168.1.0/24")',
            },
            quickMode: {
              type: 'boolean',
              description: 'Use quick discovery mode',
              default: true,
            },
          },
          required: ['network'],
        },
      },
      {
        name: 'vulnerability_scan',
        description: 'Scan for common vulnerabilities',
        inputSchema: {
          type: 'object',
          properties: {
            targets: {
              type: 'array',
              items: { type: 'string' },
              description: 'Target hosts',
            },
          },
          required: ['targets'],
        },
      },
      {
        name: 'stop_scan',
        description: 'Stop the currently running scan',
        inputSchema: {
          type: 'object',
          properties: {},
        },
      },
    ];
  }

  private async executeRMap(args: string[]): Promise<string> {
    return new Promise((resolve, reject) => {
      const scan = spawn(RMAP_PATH, args);
      this.activeScan = scan;

      let output = '';
      let error = '';

      scan.stdout.on('data', (data) => {
        output += data.toString();
      });

      scan.stderr.on('data', (data) => {
        error += data.toString();
      });

      scan.on('close', (code) => {
        this.activeScan = null;
        if (code === 0) {
          resolve(output);
        } else {
          reject(new Error(`Scan failed: ${error || output}`));
        }
      });

      scan.on('error', (err) => {
        this.activeScan = null;
        reject(err);
      });
    });
  }

  private async scanPorts(args: any) {
    const { targets, ports, timeout = 3, outputFormat = 'json' } = args;

    const tempFile = path.join(__dirname, `../temp/scan_${Date.now()}.json`);
    await fs.mkdir(path.dirname(tempFile), { recursive: true });

    const rmapArgs = [
      ...targets,
      '-p', ports,
      '-t', timeout.toString(),
      '-o', outputFormat,
      '-f', tempFile,
    ];

    try {
      await this.executeRMap(rmapArgs);

      if (outputFormat === 'json') {
        const resultData = await fs.readFile(tempFile, 'utf-8');
        const result: ScanResult = JSON.parse(resultData);
        await fs.unlink(tempFile);

        return {
          content: [
            {
              type: 'text',
              text: JSON.stringify(result, null, 2),
            },
          ],
          isComplete: true,
        };
      } else {
        const resultData = await fs.readFile(tempFile, 'utf-8');
        await fs.unlink(tempFile);

        return {
          content: [
            {
              type: 'text',
              text: resultData,
            },
          ],
          isComplete: true,
        };
      }
    } catch (error) {
      return {
        content: [
          {
            type: 'text',
            text: `Scan error: ${error}`,
          },
        ],
        isComplete: true,
        isError: true,
      };
    }
  }

  private async quickScan(args: any) {
    const { targets } = args;

    return this.scanPorts({
      targets,
      ports: '21,22,23,25,53,80,110,111,135,139,143,443,445,993,995,1723,3306,3389,5900,8080',
      timeout: 3,
      outputFormat: 'json',
    });
  }

  private async serviceDetection(args: any) {
    const { targets, ports = '22,80,443,3306,5432,8080' } = args;

    const tempFile = path.join(__dirname, `../temp/service_${Date.now()}.json`);
    await fs.mkdir(path.dirname(tempFile), { recursive: true });

    const rmapArgs = [
      ...targets,
      '-p', ports,
      '-A', // Enable service detection
      '-o', 'json',
      '-f', tempFile,
    ];

    try {
      await this.executeRMap(rmapArgs);

      const resultData = await fs.readFile(tempFile, 'utf-8');
      const result: ScanResult = JSON.parse(resultData);
      await fs.unlink(tempFile);

      return {
        content: [
          {
            type: 'text',
            text: JSON.stringify(result, null, 2),
          },
        ],
        isComplete: true,
      };
    } catch (error) {
      return {
        content: [
          {
            type: 'text',
            text: `Service detection error: ${error}`,
          },
        ],
        isComplete: true,
        isError: true,
      };
    }
  }

  private async networkDiscovery(args: any) {
    const { network, quickMode = true } = args;

    const ports = quickMode ? '80,443,22,445' : '1-1000';

    return this.scanPorts({
      targets: [network],
      ports,
      timeout: 2,
      outputFormat: 'json',
    });
  }

  private async vulnerabilityScan(args: any) {
    const { targets } = args;

    // Common vulnerable service ports
    const vulnPorts = '21,22,23,25,53,69,79,80,110,111,135,139,143,161,389,443,445,512,513,514,1433,1521,3306,3389,5432,5900,5984,6379,8020,8080,8443,9200,27017';

    const result = await this.scanPorts({
      targets,
      ports: vulnPorts,
      timeout: 5,
      outputFormat: 'json',
    });

    // Parse and analyze for vulnerabilities
    try {
      const scanData = JSON.parse(result.content[0].text);
      const vulnerabilities = this.analyzeVulnerabilities(scanData);

      return {
        content: [
          {
            type: 'text',
            text: JSON.stringify({
              scan_results: scanData,
              vulnerability_analysis: vulnerabilities,
            }, null, 2),
          },
        ],
        isComplete: true,
      };
    } catch (error) {
      return result;
    }
  }

  private analyzeVulnerabilities(scanData: ScanResult): any[] {
    const vulnerabilities = [];

    for (const host of scanData.hosts) {
      for (const port of host.ports) {
        if (port.state === 'open') {
          // Check for vulnerable services
          if (port.port === 21) {
            vulnerabilities.push({
              host: host.target,
              port: port.port,
              service: 'FTP',
              risk: 'HIGH',
              issue: 'FTP transmits credentials in plaintext',
              recommendation: 'Use SFTP or FTPS instead',
            });
          }
          if (port.port === 23) {
            vulnerabilities.push({
              host: host.target,
              port: port.port,
              service: 'Telnet',
              risk: 'CRITICAL',
              issue: 'Telnet is unencrypted and insecure',
              recommendation: 'Disable Telnet and use SSH',
            });
          }
          if (port.port === 445) {
            vulnerabilities.push({
              host: host.target,
              port: port.port,
              service: 'SMB',
              risk: 'HIGH',
              issue: 'SMB exposed to network',
              recommendation: 'Restrict SMB access with firewall rules',
            });
          }
          if (port.port === 3389) {
            vulnerabilities.push({
              host: host.target,
              port: port.port,
              service: 'RDP',
              risk: 'HIGH',
              issue: 'Remote Desktop exposed',
              recommendation: 'Use VPN for RDP access',
            });
          }
          if (port.port === 3306) {
            vulnerabilities.push({
              host: host.target,
              port: port.port,
              service: 'MySQL',
              risk: 'MEDIUM',
              issue: 'Database port exposed',
              recommendation: 'Bind to localhost only',
            });
          }
        }
      }
    }

    return vulnerabilities;
  }

  private async stopScan() {
    if (this.activeScan) {
      this.activeScan.kill('SIGTERM');
      this.activeScan = null;
      return {
        content: [
          {
            type: 'text',
            text: 'Scan stopped successfully',
          },
        ],
        isComplete: true,
      };
    } else {
      return {
        content: [
          {
            type: 'text',
            text: 'No active scan to stop',
          },
        ],
        isComplete: true,
      };
    }
  }

  async start() {
    const transport = new StdioServerTransport();
    await this.server.connect(transport);
    console.error('R-Map MCP Server started');
  }
}

// Start the server
const server = new RMapMCPServer();
server.start().catch(console.error);