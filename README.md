# okta-mcp-local

**Connecting an AI assistant to Okta, with the same controls as any other privileged integration.**

AI assistants that can call admin APIs are a new kind of privileged access, and auditors will ask
how they're governed. This repo runs Okta's open source
[okta-mcp-server](https://github.com/okta/okta-mcp-server) for Claude Code and Claude Desktop on
macOS. It treats the assistant like a service account: no secret on disk, least-privilege access,
restricted network, a pinned supply chain, and a human approving each action.

- **No shared secret:** Private Key JWT, with the key kept in 1Password and fetched only when the
  server starts.
- **Least privilege in two layers:** explicit API scopes, plus a custom admin role (and read-only
  Report Administrator for logs) instead of Super Administrator.
- **Stolen credentials don't work elsewhere:** tokens are only issued to, and accepted from, an
  allowlisted network.
- **Pinned supply chain:** an exact server version, and dependencies frozen to a publish date.
- **Leak prevention:** a pre-commit hook, git-ignored settings, and GitHub push protection.

## How it works

```
Claude ──stdio──▶ run.sh ──op read──▶ 1Password (you approve)
                    │
                    └─▶ okta-mcp-server (pinned) ──signed JWT──▶ Okta
                                                   (scopes + admin role + network zone)
```

`run.sh` loads non-secret settings from `env` (git-ignored), reads the PEM key from 1Password, and
starts the pinned server with `uvx`. Claude talks to the server over stdin/stdout, so nothing
listens on the network, and Claude's config contains only the path to `run.sh`.

## Controls

| Safeguard | Risk it addresses | SOC 2 | ISO 27001:2022 |
|---|---|---|---|
| Private Key JWT; key only in 1Password | Leaked client secret | CC6.1 | A.5.17 |
| Explicit scopes; a custom admin role plus read-only Report Administrator | Over-privileged assistant | CC6.3 | A.8.2 |
| Network zone on token requests and token use | Stolen key or token used elsewhere | CC6.6 | A.8.20 |
| Pinned server and frozen dependencies | Malicious or breaking upstream release | CC8.1 | A.8.19 |
| Pre-commit hook, `.gitignore`, push protection | Secrets committed to git | CC6.1 | A.8.12 |
| Human approval in Claude; confirmation for destructive tools | Unintended changes | CC6.1 | A.8.2 |
| Okta system log of the app's admin actions | Unreviewed changes | CC7.2 | A.8.15 |

## Security design

The setup assumes the machine or repo could be exposed, and limits what a leak could do.

**Credentials**
- Okta keeps only the public key, so there's no client secret to leak.
- The private key is never written to disk, stored in Claude's config, or committed. 1Password can
  require approval each time the server starts.
- Org URL, client ID, key ID and scopes are in `env`, which is git-ignored and owner-readable only.

**Access in Okta**
- The server requests only the scopes in `OKTA_SCOPES` and hides every tool whose scope is
  missing, so the assistant only sees operations it can perform. The scopes *granted* to the app
  in Okta should match that list. The companion
  [okta-access-review](https://github.com/matt-spellcaster/okta-access-review) tool reports
  service apps whose granted write scopes or admin roles go beyond that (check AR-10).
- Okta allows a call only if both the token's scopes and the app's admin role permit it. The app
  uses a custom role limited to users, groups and viewing apps. That role doesn't cover the system
  log, so the app also has the built-in, view-only **Report Administrator** role for the log tools.
- The server doesn't support DPoP, which would bind tokens to a client key. The network zone is the
  compensating control: a stolen key or token is useless outside the allowlisted network.

**Supply chain**
- `run.sh` runs an exact release of `okta-mcp-server`, and `uvx --exclude-newer` ignores any package
  published after a fixed date, so an upstream release can't change what runs without a reviewed
  commit.

## Known risks

| Risk | Mitigation |
|---|---|
| Tokens are bearer tokens (no DPoP support upstream) | Network zone, short token lifetime |
| The key is in the server's memory while it runs, readable by other processes as the same user | Run only when needed; 1Password approval on start |
| Okta data sent to the model becomes part of the conversation | Use a dev or test org, not production data |
| A confused or manipulated assistant could misuse its tools | Least-privilege scopes and role, human approval, Okta audit log |

## Setup

1. Install the tools: `brew install uv` and `brew install --cask 1password-cli`. In 1Password,
   turn on **Settings → Developer → Integrate with 1Password CLI**.
2. In Okta, create an **API Services** app:
   - client authentication **Public key / Private key** (DPoP off, since the server doesn't support it)
   - grant only the scopes you'll list in `OKTA_SCOPES`. The default set is read access to users,
     groups, apps, logs and policies, plus `okta.users.manage` and `okta.groups.manage`, which
     enables 28 of the server's 112 tools (in version 1.1.6). Branding, domain, template, device,
     app and policy changes stay off.
   - assign a custom admin role with permissions for users and groups, plus viewing apps, and the
     built-in **Report Administrator** role. Without it, the log tools fail with
     `E0000006 You do not have permission`, even though `okta.logs.read` is granted.
   - under **General**, restrict token requests to a network zone with your IP addresses
3. Save the PEM in a 1Password Secure Note, e.g. "Okta developer MCP key" in `dev`, then delete the
   downloaded file.
4. Run `cp env.example env`, fill it in, and run `git config core.hooksPath .githooks`.
5. Register `run.sh` with Claude:
   - Claude Code: `claude mcp add --scope user okta -- "$PWD/run.sh"`
   - Claude Desktop: add the entry from `examples/claude-mcp-entry.json` to
     `~/Library/Application Support/Claude/claude_desktop_config.json`
6. Restart Claude and approve the 1Password prompt when the server starts.

## Upgrading

`run.sh` pins both the server version (`okta-mcp-server@X.Y.Z`) and a dependency cutoff date
(`--exclude-newer`). To upgrade, change both: the new version, and a cutoff after its release date.
Run `./run.sh` to test before committing.

## Related

[okta-access-review](https://github.com/matt-spellcaster/okta-access-review) is a read-only CLI for
periodic Okta access reviews, with SOC 2 and ISO 27001 control mapping and audit-ready evidence.
It uses the same credential handling, plus DPoP.
