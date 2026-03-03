# Kimi Status Bar for VS Code

A VS Code extension that displays Kimi CLI usage details in your status bar.

## Installation

```bash
cd vscode-kimi-statusbar
./install.sh
# Restart VS Code
```

## Finding the Settings

### Method 1: Command Palette
1. Press `Ctrl+Shift+P` (or `Cmd+Shift+P` on Mac)
2. Type "Preferences: Open Settings (UI)"
3. In the search box at the top, type "kimi"

### Method 2: Direct Settings File
1. Press `Ctrl+,` (or `Cmd+,` on Mac)
2. Click the icon to open Settings (JSON) in the top-right
3. Add Kimi settings:

```json
{
  "kimiStatusbar.enabled": true,
  "kimiStatusbar.refreshInterval": 30,
  "kimiStatusbar.showIcon": true,
  "kimi.apiKey": "your-api-key-here",
  "kimi.model": "kimi-k2",
  "kimi.baseUrl": "https://api.moonshot.cn/v1"
}
```

## Available Settings

### Status Bar Settings
| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `kimiStatusbar.enabled` | boolean | `true` | Enable/disable the status bar widget |
| `kimiStatusbar.refreshInterval` | number | `30` | Auto-refresh interval in seconds (5-3600) |
| `kimiStatusbar.showIcon` | boolean | `true` | Show sparkle icon in status bar |

### API Settings
| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| `kimi.apiKey` | string | `""` | Your Kimi API key |
| `kimi.model` | string | `"kimi-latest"` | Model to use (kimi-latest, kimi-k2, etc.) |
| `kimi.baseUrl` | string | `"https://api.moonshot.cn/v1"` | API base URL |

## Commands

Press `Ctrl+Shift+P` and type:
- **Kimi: Show Usage Details** - Display detailed statistics
- **Kimi: Refresh Stats** - Manually refresh usage data
- **Kimi: Open Settings** - Open extension settings

## Troubleshooting

**Settings not showing?**
- Make sure the extension is installed: Check the Extensions view (Ctrl+Shift+X)
- Restart VS Code after installation
- Try the Development Host: Press F5 in the extension folder

**Status bar not appearing?**
- Check that `kimiStatusbar.enabled` is set to `true`
- Look at the right side of the status bar (it may be hidden by other items)
- Try clicking the status bar area to see all items
