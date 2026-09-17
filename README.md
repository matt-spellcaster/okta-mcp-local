# okta-mcp-local

A small launcher for running Okta's open source [okta-mcp-server](https://github.com/okta/okta-mcp-server)
on macOS for Claude Code and Claude Desktop. It uses Private Key JWT auth, and the private key stays in 1Password.

## How it works

`run.sh` loads non-secret settings from `env` (git-ignored). It gets the PEM private key with
`op read`, passes it to the server as `OKTA_PRIVATE_KEY`, and starts the pinned server version with `uvx`.
The key never lives in this repo or on disk.

## Setup

1. Install the tools:
   ```bash
   brew install uv
   brew install --cask 1password-cli
   ```
2. In the 1Password app, open **Settings → Developer** and turn on **Integrate with 1Password CLI**.
3. In Okta, create an **API Services** app:
   - Under client authentication, choose **Public key / Private key** and turn off DPoP.
   - Grant Okta API scopes and assign an admin role.
   - Download the key as PEM and note its Key ID.
4. Store the PEM in 1Password: create a **Secure Note**, for example "Okta developer MCP key" in a
   `dev` vault, paste the PEM into the note body, and delete the downloaded file.
5. Run `cp env.example env` and fill in `env`.
6. Register `run.sh` with Claude:
   - Claude Code: `claude mcp add --scope user okta -- "$PWD/run.sh"`
   - Claude Desktop: add the entry from `examples/claude-mcp-entry.json` to
     `~/Library/Application Support/Claude/claude_desktop_config.json`
7. Restart Claude. 1Password may ask you to approve access when the server starts.
