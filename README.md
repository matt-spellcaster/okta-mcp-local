# okta-mcp-local

A small wrapper script for running Okta's open source [okta-mcp-server](https://github.com/okta/okta-mcp-server)
on macOS for Claude Code and Claude Desktop. It uses Private Key JWT auth, and the private key stays in 1Password.

## How it works

`run.sh` loads non-secret settings from `env` (git-ignored). It gets the PEM private key with
`op read`, passes it to the server as `OKTA_PRIVATE_KEY`, and starts the pinned server version with `uvx`.
The key never lives in this repo or on disk.

## Security design

This setup assumes the machine or the repo could be exposed, and it limits what a leak could do.

### Credentials

- **Key-based client authentication, no shared secret.** The Okta app uses Private Key JWT. Each
  token request is signed with a private key, and Okta keeps only the public half. This setup has
  no client secret to leak.
- **The private key lives only in 1Password.** `run.sh` fetches it with `op read` each time the
  server starts, and 1Password may ask for approval. The key is never written to disk, never stored
  in Claude's config files, and never committed. Claude's config contains only the path to `run.sh`.
- **Settings are kept apart from secrets.** Org URL, client ID, key ID and scopes are in `env`,
  which is git-ignored and readable only by the owner (`chmod 600`). The repo contains only
  `env.example` with placeholders.

### Access control in Okta

- **Scopes are listed explicitly.** Only the scopes in `OKTA_SCOPES` are requested, and each must
  be granted to the app in Okta. The server turns off every tool whose scope is missing, so Claude
  only sees the operations it is allowed to perform.
- **Least-privilege admin role.** What the app can do is limited by both its granted scopes and
  its admin role. The app has a custom admin role that grants only the permissions these tools
  need, instead of a built-in role like Super Admin.
- **Network restriction.** The app accepts token requests, and use of its tokens, only from an
  allowlisted network zone. A stolen key or access token is useless from any other network. This
  was added mainly because the MCP server doesn't support DPoP, which would otherwise tie each
  token to a client-held key. Without DPoP, the network restriction limits where a stolen token
  can be used.
- **Human in the loop.** The server asks for confirmation before destructive operations, and Claude
  asks for approval before calling tools unless you tell it to always allow them.

### Supply chain

- **Pinned server version.** `run.sh` runs an exact release of `okta-mcp-server`, not the latest.
- **Frozen dependencies.** `uvx --exclude-newer` ignores any package published after a fixed date,
  so a new upstream release, including a malicious one, can't change what runs without a
  reviewed commit.

### Leak prevention in the repo

- **`.gitignore`** excludes `env`, key files (`*.pem`, `*.key`) and logs.
- **Pre-commit hook** (`.githooks/pre-commit`) refuses any commit that stages `env`, a key file, or
  text that looks like a private key.
- **GitHub secret scanning and push protection** are turned on for the repository.

### Known limitations

- **Tokens are bearer tokens.** The server doesn't support DPoP, so access tokens aren't tied to a
  client key. The network restriction (see above) and Okta's short token lifetime reduce this risk.
- **The key is in memory while the server runs.** It is held in the server process's environment,
  where other processes running as the same macOS user could read it.
- **Okta data goes to the model.** Anything Claude reads through these tools, such as user profiles
  or logs, becomes part of the conversation. Use a dev or test org, not production data.

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
   - Optional but recommended: on the app's **General** tab, limit token requests to a network zone
     that contains only your IP addresses.
4. Store the PEM in 1Password: create a **Secure Note**, for example "Okta developer MCP key" in a
   `dev` vault, paste the PEM into the note body, and delete the downloaded file.
5. Run `cp env.example env` and fill in `env`.
6. Register `run.sh` with Claude:
   - Claude Code: `claude mcp add --scope user okta -- "$PWD/run.sh"`
   - Claude Desktop: add the entry from `examples/claude-mcp-entry.json` to
     `~/Library/Application Support/Claude/claude_desktop_config.json`
7. Turn on the commit safety check. It blocks any commit that includes `env` or a private key:
   `git config core.hooksPath .githooks`
8. Restart Claude. 1Password may ask you to approve access when the server starts.

## Upgrading

`run.sh` pins the server version (`okta-mcp-server@X.Y.Z`). It also pins a dependency cutoff
(`--exclude-newer`), so packages published after that date are never used. To upgrade, change both:
set the version to the new release and the cutoff to a date after that release. Then run `./run.sh`
to test before you commit.
