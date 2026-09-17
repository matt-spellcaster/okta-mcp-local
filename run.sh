#!/bin/zsh
# Launcher for the Okta MCP server (https://github.com/okta/okta-mcp-server),
# used by Claude Code and Claude Desktop. Settings come from ./env; the private
# key is fetched from 1Password at startup and never written to disk.
set -e
DIR="${0:A:h}"
if [[ ! -r "$DIR/env" ]]; then
  echo "okta-mcp: missing $DIR/env (copy env.example and fill it in)" >&2
  exit 1
fi
set -a; source "$DIR/env"; set +a
if [[ -z "$OKTA_PRIVATE_KEY_REF" ]]; then
  echo "okta-mcp: OKTA_PRIVATE_KEY_REF is not set in $DIR/env" >&2
  exit 1
fi
if ! OKTA_PRIVATE_KEY="$(/opt/homebrew/bin/op read "$OKTA_PRIVATE_KEY_REF")"; then
  echo "okta-mcp: could not read the key from 1Password ($OKTA_PRIVATE_KEY_REF)" >&2
  exit 1
fi
export OKTA_PRIVATE_KEY
unset OKTA_PRIVATE_KEY_REF
# Pin the server and freeze its dependencies to what was on PyPI at this
# date, so upstream releases can't change what runs. Bump both together.
exec /opt/homebrew/bin/uvx --exclude-newer 2026-09-16T00:00:00Z okta-mcp-server@1.1.6
