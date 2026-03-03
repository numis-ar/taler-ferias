#!/bin/bash
# Install script for Kimi Status Bar VS Code Extension

set -e

EXTENSION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VSCODE_EXT_DIR="$HOME/.vscode/extensions/kimi-cli.kimi-statusbar-1.0.0"

echo "Installing Kimi Status Bar Extension..."

# Compile TypeScript
echo "Compiling TypeScript..."
cd "$EXTENSION_DIR"
npm run compile

# Create extension directory
mkdir -p "$VSCODE_EXT_DIR"

# Copy files
cp -r "$EXTENSION_DIR/out" "$VSCODE_EXT_DIR/"
cp "$EXTENSION_DIR/package.json" "$VSCODE_EXT_DIR/"
cp "$EXTENSION_DIR/README.md" "$VSCODE_EXT_DIR/"

echo "Extension installed to: $VSCODE_EXT_DIR"
echo ""
echo "Please restart VS Code to activate the extension."
echo ""
echo "To test the extension without restarting:"
echo "  1. Open VS Code"
echo "  2. Press F5 to launch Extension Development Host"
