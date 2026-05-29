#!/bin/bash
set -e

# Generate a persistent Foundry MCP token for Codex
TOKEN=$(curl -s -X POST http://localhost:4000/foundry/mcp/register \
  -H "Content-Type: application/json" \
  -d '{"client_name":"codex-foundry"}' | python3 -c "import sys,json; print(json.load(sys.stdin)['access_token'])")

if [ -z "$TOKEN" ]; then
  echo "Failed to generate MCP token. Ensure Foundry dev server is running on localhost:4000"
  exit 1
fi

# Get path to Foundry repo
FOUNDRY_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Register with Codex
codex mcp add foundry \
  --env BEARER_TOKEN="$TOKEN" \
  --env FOUNDRY_MCP_HOST=localhost \
  --env FOUNDRY_MCP_PORT=4000 \
  -- sh -c "cd '$FOUNDRY_ROOT' && mix foundry.mcp.stdio"

echo "✓ Codex MCP bridge configured"
echo "  Token: $TOKEN"
echo "  Run 'codex' from any project directory to use Foundry tools"
echo ""
echo "Note: Codex will run 'mix foundry.mcp.stdio' from $FOUNDRY_ROOT"
