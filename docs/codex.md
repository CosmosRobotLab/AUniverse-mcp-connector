# Codex

Codex (the CLI, the IDE extension and the ChatGPT desktop app) reads the AUniverse server from `~/.codex/config.toml` and your token from the `AUNIVERSE_TOKEN` environment variable. The token stays out of Codex's config file; it lives in your shell profile, or in Codex's own `.env` file (see below), so don't publish those.

You need a personal access token first: on [auniverse.space](https://auniverse.space) open **Profile → MCP**, create a token, keep `poster:read` ticked, and copy it straight away (it is shown once). Creating one asks for your account password; if you signed up with Google or a passkey, add a password on the Security page first.

## Add the server

macOS and Linux. Put the `export` line in your shell profile (`~/.zshrc` or `~/.bashrc`) so every new terminal has it (on a computer you share with others, make that file private: `chmod 600 ~/.zshrc`), open a new terminal, then run the `codex mcp add` line once:

<!-- generated:add -->
```bash
export AUNIVERSE_TOKEN="aun_pat_..."
codex mcp add auniverse --url https://api.auniverse.space/mcp --bearer-token-env-var AUNIVERSE_TOKEN
```
<!-- /generated:add -->

Keep `--url`: without it Codex saves the address as a program to run, and the server never connects. There is no `--header` option in Codex; `--bearer-token-env-var` is what sends the token.

Windows PowerShell (then open a new terminal):

<!-- generated:add-powershell -->
```powershell
[Environment]::SetEnvironmentVariable('AUNIVERSE_TOKEN', 'aun_pat_...', 'User')
$env:AUNIVERSE_TOKEN = 'aun_pat_...'
codex mcp add auniverse --url https://api.auniverse.space/mcp --bearer-token-env-var AUNIVERSE_TOKEN
```
<!-- /generated:add-powershell -->

If you run Codex inside WSL, put the `export` line in WSL's `~/.bashrc` instead. WSL keeps its own `~/.codex`, separate from the Windows app's.

### Codex's background server

Codex runs MCP servers in a background server that it starts the first time you use it, and that keeps running after you quit Codex. That server reads `AUNIVERSE_TOKEN` when it starts, not when you open a new terminal. So whenever you set or change the variable while it is running (for example after creating a new token), restart it from a terminal that has the new value:

```bash
codex app-server daemon restart
```

Or start Codex with `codex --no-daemon`, which doesn't use it.

### Or edit the config file

`codex mcp add` writes these lines to `~/.codex/config.toml` (Windows: `%USERPROFILE%\.codex\config.toml`). You can paste them yourself instead, at the end of the file (settings below them would become part of them); they are also in [`templates/codex/config.toml`](../templates/codex/config.toml):

<!-- generated:config -->
```toml
[mcp_servers.auniverse]
url = "https://api.auniverse.space/mcp"
bearer_token_env_var = "AUNIVERSE_TOKEN"
```
<!-- /generated:config -->

The same lines in a project's `.codex/config.toml` share the setup with that project, but only once you trust the project: the CLI asks you to trust the folder, the apps show a warning, and `codex exec` skips the file without saying so.

### The IDE extension and the ChatGPT desktop app

They use the same `config.toml` as the CLI, but they don't see variables from your shell profile when you start them from the Dock, the Start menu or an app launcher. If the server fails there with "Environment variable AUNIVERSE_TOKEN … is not set", give the token to Codex itself: put this line in `~/.codex/.env`, which every part of Codex reads when it starts.

```bash
AUNIVERSE_TOKEN=aun_pat_...
```

Make the file readable only by you (`chmod 600 ~/.codex/.env`), then fully quit and reopen the app, and restart the background server as above. On Windows you can instead set the variable for your user account with the PowerShell line above.

A token in `~/.codex/.env` wins over the one in your shell, everywhere in Codex. So when you get a new token, replace it in that file too (or delete the line there), then restart the background server.

## Check it works

Start `codex` and type `/mcp`. Look for **auniverse: connected** with the number of tools; `/mcp verbose` lists them. Then ask: "Who am I on AUniverse?"

`codex mcp list` only shows what is in the config file. It doesn't contact the server, so it looks fine even when the token is wrong. To test the token itself, run [`scripts/connect.sh --check`](../scripts/connect.sh) from a copy of this repository.

<!-- generated:tool-names -->
Codex shows the calls as `auniverse.<tool>`, for example `auniverse.auniverse_whoami`. Settings for single tools in `config.toml` (`enabled_tools`, `disabled_tools`) take the bare name, such as `auniverse_whoami`.
<!-- /generated:tool-names -->

## Remove it

<!-- generated:remove -->
```bash
codex mcp remove auniverse
```
<!-- /generated:remove -->

To stop the token working everywhere, revoke it in **Profile → MCP**.

## Troubleshooting

| What you see | What it means | What to do |
|---|---|---|
| `Environment variable AUNIVERSE_TOKEN for MCP server 'auniverse' is not set` (or `is empty`) | The part of Codex that connects can't see the variable | Add the `export` line to your shell profile, then restart the [background server](#codexs-background-server) from a new terminal. For the desktop app or the IDE, use `~/.codex/.env` (see above) |
| "The auniverse MCP server is not logged in. Run `codex mcp login auniverse`", or `authentication required (0 tools)` in `/mcp` | The server refused the token (wrong, expired or revoked), or Codex is still using an old one, or the entry has no token setting at all | Create a new token in Profile → MCP, update `AUNIVERSE_TOKEN` (in `~/.codex/.env` too, if you put it there: that one wins), and restart the background server. If `codex mcp get auniverse` shows `bearer_token_env_var: -`, add the server again as above. Don't run `codex mcp login`: AUniverse has no sign-in flow for it yet, so it fails with "Registration failed … 404" |
| `auniverse: failed`, with "No such file or directory (os error 2)" | The server was saved without `--url`, as a program to run | Run `codex mcp remove auniverse`, then add it again with `--url` |
| `auniverse: failed`, with "unexpected server response: HTTP 503" and "isn't available on this server right now" | The connector is switched off on the server: before launch, that's expected (see the status at the top of the [README](../README.md)) | Try again later |
| `auniverse: failed`, with "error sending request for url" | The server can't be reached: before launch, that's expected (see the status at the top of the [README](../README.md)); otherwise it's down or your network blocks it | Check the README's status, then try again later or from another network |
| A call fails with only "Insufficient scope" | Your account allows that tool but this token lacks its scope. Codex doesn't show the server's message naming the scope | Ask "Who am I on AUniverse?" to see which scope each tool needs, then create a token with it |
| `429` or "Too many requests" | Too many requests in a minute | Wait for the number of seconds it gives |

This repository also contains a Claude Code plugin. It is for Claude Code only: Codex can read its files but connects without your token. Codex's `/import` from Claude Code brings over all your Claude Code plugins together, with one tick box for all of them. So either untick **Plugins** there, or import them and then add the server with `codex mcp add` as above: your own entry takes the plugin's place. A server you added to Claude Code by hand imports fine.

More in [troubleshooting.md](troubleshooting.md).
