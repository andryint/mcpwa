#!/bin/bash
# uninstall.sh

echo "=== Uninstalling mcpwa ==="

# Remove app
if [ -d "/Applications/mcpwa.app" ]; then
    rm -rf "/Applications/mcpwa.app"
    echo "✓ Removed mcpwa.app"
else
    echo "- mcpwa.app not found"
fi

# Remove from Claude Desktop config
CLAUDE_CONFIG="$HOME/Library/Application Support/Claude/claude_desktop_config.json"

if [ -f "$CLAUDE_CONFIG" ]; then
    /usr/bin/python3 << 'EOF'
import json
import os

config_path = os.path.expanduser("~/Library/Application Support/Claude/claude_desktop_config.json")

try:
    with open(config_path, 'r') as f:
        config = json.load(f)
    
    if 'mcpServers' in config and 'mcpwa' in config['mcpServers']:
        del config['mcpServers']['mcpwa']
        
        with open(config_path, 'w') as f:
            json.dump(config, f, indent=2)
        print("✓ Removed mcpwa from Claude Desktop config")
    else:
        print("- mcpwa not found in Claude config")
        
except Exception as e:
    print(f"- Could not update Claude config: {e}")
EOF
else
    echo "- Claude config not found"
fi

echo "=== Done ==="

