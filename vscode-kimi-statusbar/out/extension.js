"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.activate = activate;
exports.deactivate = deactivate;
const vscode = __importStar(require("vscode"));
const fs = __importStar(require("fs"));
const path = __importStar(require("path"));
const os = __importStar(require("os"));
let statusBarItem;
let refreshInterval;
function activate(context) {
    // Create status bar item
    statusBarItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Right, 100);
    statusBarItem.command = 'kimiStatusbar.showDetails';
    // Register commands
    context.subscriptions.push(vscode.commands.registerCommand('kimiStatusbar.showDetails', showDetails), vscode.commands.registerCommand('kimiStatusbar.refresh', refreshStats), vscode.commands.registerCommand('kimiStatusbar.openSettings', openSettings));
    // Watch for configuration changes
    context.subscriptions.push(vscode.workspace.onDidChangeConfiguration(e => {
        if (e.affectsConfiguration('kimiStatusbar')) {
            updateConfiguration();
        }
    }));
    // Initial setup
    updateConfiguration();
    // Add to subscriptions for cleanup
    context.subscriptions.push(statusBarItem);
}
function updateConfiguration() {
    const config = vscode.workspace.getConfiguration('kimiStatusbar');
    const enabled = config.get('enabled', true);
    const intervalSeconds = config.get('refreshInterval', 30);
    // Clear existing interval
    if (refreshInterval) {
        clearInterval(refreshInterval);
        refreshInterval = undefined;
    }
    if (enabled) {
        statusBarItem.show();
        refreshStats();
        // Set up auto-refresh
        refreshInterval = setInterval(refreshStats, intervalSeconds * 1000);
    }
    else {
        statusBarItem.hide();
    }
}
async function refreshStats() {
    const sbConfig = vscode.workspace.getConfiguration('kimiStatusbar');
    const showIcon = sbConfig.get('showIcon', true);
    try {
        const stats = await getKimiStats();
        const kimiConfig = getKimiConfig();
        // Build status bar text
        const parts = [];
        if (showIcon) {
            parts.push('$(sparkle)'); // VS Code sparkle icon
        }
        parts.push('Kimi');
        // Show model name if configured (always show this)
        if (kimiConfig.model) {
            parts.push(`$(server) ${kimiConfig.model}`);
        }
        // Show today's token usage if available
        if (stats.todayTokens > 0) {
            parts.push(`$(symbol-numeric) ${formatNumber(stats.todayTokens)}t`);
        }
        // Show context size if editor is open
        if (stats.contextSize > 0) {
            parts.push(`$(file-code) ${formatNumber(stats.contextSize)}c`);
        }
        // Show connection status
        if (kimiConfig.apiKey) {
            parts.push('$(check)');
        }
        else {
            parts.push('$(warning)');
        }
        statusBarItem.text = parts.join(' ');
        statusBarItem.tooltip = buildTooltip(stats, kimiConfig);
        // Set color based on usage
        if (!kimiConfig.apiKey) {
            statusBarItem.backgroundColor = new vscode.ThemeColor('statusBarItem.warningBackground');
        }
        else {
            statusBarItem.backgroundColor = undefined;
        }
    }
    catch (error) {
        statusBarItem.text = showIcon ? '$(sparkle) Kimi $(x)' : 'Kimi $(x)';
        statusBarItem.tooltip = `Error: ${error}. Click to retry.`;
        statusBarItem.backgroundColor = new vscode.ThemeColor('statusBarItem.errorBackground');
    }
}
function buildTooltip(stats, kimiConfig) {
    const lines = ['Kimi CLI Usage Details'];
    lines.push('─'.repeat(30));
    // Configuration info
    lines.push(`$(gear) Model: ${kimiConfig.model || 'Not configured'}`);
    lines.push(`$(key) API Key: ${kimiConfig.apiKey ? '✓ Configured' : '✗ Not configured'}`);
    lines.push(`$(globe) Base URL: ${kimiConfig.baseUrl || 'https://api.moonshot.cn/v1'}`);
    lines.push('');
    // Usage stats
    lines.push(`$(graph) Usage Statistics:`);
    lines.push(`  • Today's Requests: ${stats.todayRequests}`);
    lines.push(`  • Today's Tokens: ${formatNumber(stats.todayTokens)}`);
    lines.push(`  • Total Requests: ${stats.totalRequests}`);
    lines.push(`  • Total Tokens: ${formatNumber(stats.totalTokens)}`);
    lines.push(`  • Context Size: ${formatNumber(stats.contextSize)} tokens`);
    if (stats.lastUsed) {
        lines.push(`  • Last Used: ${stats.lastUsed.toLocaleString()}`);
    }
    lines.push('');
    lines.push('$(info) Click for more details');
    return lines.join('\n');
}
async function showDetails() {
    const stats = await getKimiStats();
    const kimiConfig = getKimiConfig();
    const items = [
        {
            label: '$(gear) Configuration',
            kind: vscode.QuickPickItemKind.Separator
        },
        {
            label: `Model: ${kimiConfig.model || 'Not configured'}`,
            description: 'Current model'
        },
        {
            label: `API Key: ${kimiConfig.apiKey ? '✓ Configured' : '✗ Not configured'}`,
            description: kimiConfig.apiKey ? 'Click to reconfigure' : 'Click to configure'
        },
        {
            label: `Base URL: ${kimiConfig.baseUrl || 'https://api.moonshot.cn/v1'}`,
            description: 'API endpoint'
        },
        {
            label: '$(graph) Usage Statistics',
            kind: vscode.QuickPickItemKind.Separator
        },
        {
            label: `Today's Requests: ${stats.todayRequests}`,
            description: 'Requests made today'
        },
        {
            label: `Today's Tokens: ${formatNumber(stats.todayTokens)}`,
            description: 'Tokens used today'
        },
        {
            label: `Total Requests: ${stats.totalRequests}`,
            description: 'All-time requests'
        },
        {
            label: `Total Tokens: ${formatNumber(stats.totalTokens)}`,
            description: 'All-time token usage'
        },
        {
            label: `Context Size: ${formatNumber(stats.contextSize)} tokens`,
            description: 'Current editor context window'
        },
        {
            label: '$(refresh) Actions',
            kind: vscode.QuickPickItemKind.Separator
        },
        {
            label: '$(refresh) Refresh Stats',
            description: 'Manually refresh usage statistics'
        },
        {
            label: '$(gear) Open Settings',
            description: 'Configure Kimi extension settings'
        },
        {
            label: '$(book) Open Kimi CLI Help',
            description: 'View Kimi CLI documentation'
        }
    ];
    const selected = await vscode.window.showQuickPick(items, {
        placeHolder: 'Select an action or view details',
        title: 'Kimi Usage Details'
    });
    if (selected) {
        if (selected.label.includes('Refresh Stats')) {
            refreshStats();
            vscode.window.showInformationMessage('Kimi stats refreshed!');
        }
        else if (selected.label.includes('Open Settings')) {
            openSettings();
        }
        else if (selected.label.includes('Kimi CLI Help')) {
            openKimiHelp();
        }
        else if (selected.label.includes('API Key')) {
            configureApiKey();
        }
    }
}
async function configureApiKey() {
    const apiKey = await vscode.window.showInputBox({
        prompt: 'Enter your Kimi API Key',
        password: true,
        ignoreFocusOut: true,
        placeHolder: 'sk-...'
    });
    if (apiKey) {
        // Store in VS Code secrets
        await vscode.workspace.getConfiguration('kimi').update('apiKey', apiKey, true);
        vscode.window.showInformationMessage('Kimi API Key saved!');
        refreshStats();
    }
}
function openSettings() {
    vscode.commands.executeCommand('workbench.action.openSettings', '@ext:kimi-cli.kimi-statusbar');
}
async function openKimiHelp() {
    // Try to find Kimi CLI skill documentation
    const skillPath = path.join(os.homedir(), '.local', 'share', 'uv', 'tools', 'kimi-cli', 'lib');
    // Search for SKILL.md files
    const terminal = vscode.window.createTerminal('Kimi Help');
    terminal.sendText('kimi --help');
    terminal.show();
}
function getKimiConfigPath() {
    const homeDir = os.homedir();
    return path.join(homeDir, '.config', 'kimi-cli', 'config.json');
}
function getKimiUsagePath() {
    const homeDir = os.homedir();
    return path.join(homeDir, '.local', 'share', 'kimi-cli', 'usage.json');
}
function getKimiConfig() {
    const config = {};
    // Try to read from VS Code settings first
    const vscodeConfig = vscode.workspace.getConfiguration('kimi');
    config.apiKey = vscodeConfig.get('apiKey');
    config.model = vscodeConfig.get('model');
    config.baseUrl = vscodeConfig.get('baseUrl');
    // Fall back to Kimi CLI config file
    if (!config.apiKey) {
        const configPath = getKimiConfigPath();
        if (fs.existsSync(configPath)) {
            try {
                const data = JSON.parse(fs.readFileSync(configPath, 'utf-8'));
                config.apiKey = data.api_key || data.apiKey;
                config.model = data.model;
                config.baseUrl = data.base_url || data.baseUrl;
            }
            catch (e) {
                // Ignore parse errors
            }
        }
    }
    // Check environment variable
    if (!config.apiKey) {
        config.apiKey = process.env.KIMI_API_KEY;
    }
    // Default values
    if (!config.model) {
        config.model = 'kimi-k2';
    }
    return config;
}
async function getKimiStats() {
    const stats = {
        totalRequests: 0,
        totalTokens: 0,
        todayRequests: 0,
        todayTokens: 0,
        lastUsed: null,
        contextSize: 0
    };
    // Try to read usage data from Kimi CLI
    const usagePath = getKimiUsagePath();
    if (fs.existsSync(usagePath)) {
        try {
            const data = JSON.parse(fs.readFileSync(usagePath, 'utf-8'));
            stats.totalRequests = data.total_requests || 0;
            stats.totalTokens = data.total_tokens || 0;
            // Get today's stats
            const today = new Date().toISOString().split('T')[0];
            if (data.daily && data.daily[today]) {
                stats.todayRequests = data.daily[today].requests || 0;
                stats.todayTokens = data.daily[today].tokens || 0;
            }
            if (data.last_used) {
                stats.lastUsed = new Date(data.last_used);
            }
        }
        catch (e) {
            // Ignore parse errors, use defaults
        }
    }
    // Try to get current context size from active editor
    const editor = vscode.window.activeTextEditor;
    if (editor) {
        const document = editor.document;
        const text = document.getText();
        // Rough estimation: ~4 characters per token
        stats.contextSize = Math.ceil(text.length / 4);
    }
    return stats;
}
function formatNumber(num) {
    if (num >= 1000000) {
        return (num / 1000000).toFixed(1) + 'M';
    }
    if (num >= 1000) {
        return (num / 1000).toFixed(1) + 'K';
    }
    return num.toString();
}
function deactivate() {
    if (refreshInterval) {
        clearInterval(refreshInterval);
    }
    if (statusBarItem) {
        statusBarItem.dispose();
    }
}
//# sourceMappingURL=extension.js.map