# Claude Code

Two ways to connect Claude Code to AUniverse. Pick one, not both: if Claude Code has a server added by hand for the same address as the plugin's, it uses that one and hides the plugin's, whatever its name.

| | Plugin (recommended) | Added by hand |
|---|---|---|
| Where the token lives | With Claude Code's own credentials: the macOS keychain on a Mac, elsewhere `~/.claude/.credentials.json` (a file only you can read) | An environment variable, `AUNIVERSE_TOKEN`, set in your shell profile |
| When AUniverse changes its connection details | `claude plugin update` brings the change | You run the command again |
| Works with Codex too | No, Codex needs the environment variable | Yes, the same variable |

You need a personal access token first: on [auniverse.space](https://auniverse.space) open **Profile → MCP**, create a token, keep `poster:read` ticked, and copy it straight away (it is shown once). Creating one asks for your account password; if you signed up with Google or a passkey, add a password on the Security page first.

The token page then shows a `claude mcp add` command with your token inside it. Don't run it: it saves the token itself in `~/.claude.json`, and it hides the plugin. If you already ran it, run `claude mcp remove auniverse --scope user` and carry on below.

## Plugin

<!-- generated:plugin -->
```bash
claude plugin marketplace add CosmosRobotLab/AUniverse-mcp-connector
claude plugin install auniverse@auniverse
```
<!-- /generated:plugin -->

Then give the plugin your token:

1. Start `claude`.
2. Run `/plugin`, open **Installed → auniverse → Configure options**, and paste the token.
3. Restart Claude Code.

If the token is already in `$AUNIVERSE_TOKEN`, you can skip the menu and pipe it in instead (it never appears in your shell history):

<!-- generated:plugin-configure-stdin -->
```bash
printf '{"token":"%s"}' "$AUNIVERSE_TOKEN" | claude plugin configure auniverse@auniverse --values-stdin
```
<!-- /generated:plugin-configure-stdin -->

`claude plugin configure` needs Claude Code 2.1.285 or later; if it says the command is unknown, run `claude update` or use the menu.

To give the plugin a new token later (tokens expire after 90 days unless you chose otherwise), do the same again: the menu, or the `printf` line once the variable holds the new token. [`scripts/connect.sh claude`](../scripts/connect.sh) does it too: it saves the new token when the server refuses the one the plugin has.

### Updates

Claude Code doesn't update plugins from other publishers on its own unless you turn that on. When this repository announces a change, or once in a while:

<!-- generated:plugin-update -->
```bash
claude plugin marketplace update auniverse
claude plugin update auniverse@auniverse
```
<!-- /generated:plugin-update -->

Then restart Claude Code. To have it happen by itself, open `/plugin`, go to **Marketplaces → auniverse**, and turn on auto-update.

## Added by hand

macOS and Linux. Put the `export` line in your shell profile (`~/.zshrc` or `~/.bashrc`) so every new terminal has it, open a new terminal, then run the `claude mcp add` line once:

<!-- generated:manual -->
```bash
export AUNIVERSE_TOKEN="aun_pat_..."
claude mcp add --transport http --scope user auniverse https://api.auniverse.space/mcp --header 'Authorization: Bearer ${AUNIVERSE_TOKEN}'
```
<!-- /generated:manual -->

Keep the single quotes around the header. They store `${AUNIVERSE_TOKEN}` itself, and Claude Code fills in the token each time it connects, so the token stays out of `~/.claude.json` (it lives in your shell profile instead: don't publish that file, and on a computer you share with others, make it private with `chmod 600 ~/.zshrc` or `~/.bashrc`). With double quotes your shell would paste the token into `~/.claude.json`, or paste nothing if the variable isn't set yet.

Windows PowerShell (single quotes matter here too):

<!-- generated:manual-powershell -->
```powershell
[Environment]::SetEnvironmentVariable('AUNIVERSE_TOKEN', 'aun_pat_...', 'User')
$env:AUNIVERSE_TOKEN = 'aun_pat_...'
claude mcp add --transport http --scope user auniverse https://api.auniverse.space/mcp --header 'Authorization: Bearer ${AUNIVERSE_TOKEN}'
```
<!-- /generated:manual-powershell -->

Windows Command Prompt (open a new window after `setx`):

<!-- generated:manual-cmd -->
```bat
setx AUNIVERSE_TOKEN aun_pat_...
claude mcp add --transport http --scope user auniverse https://api.auniverse.space/mcp --header "Authorization: Bearer ${AUNIVERSE_TOKEN}"
```
<!-- /generated:manual-cmd -->

Claude Code started from an app launcher or an IDE may not see variables from your shell profile. If it can't connect there but can in a terminal, switch to the plugin: first run `claude mcp remove auniverse --scope user`, because the hand-added entry would keep hiding the plugin, then follow [Plugin](#plugin).

### For one project only

A project can share the setup in a `.mcp.json` at its root (it is also in [`templates/claude-code/mcp.json`](../templates/claude-code/mcp.json)). It only works for people who set `AUNIVERSE_TOKEN` themselves, and never put the token itself in the file:

<!-- generated:project -->
```json
{
  "mcpServers": {
    "auniverse": {
      "type": "http",
      "url": "https://api.auniverse.space/mcp",
      "headers": {
        "Authorization": "Bearer ${AUNIVERSE_TOKEN}"
      }
    }
  }
}
```
<!-- /generated:project -->

The first time each person runs `claude` in that folder, Claude Code asks them to approve the server. If you use the plugin, decline it: once approved, it replaces the plugin's server in that project, and without the variable it can't connect.

## Check it works

```bash
claude mcp list
```

Look for `plugin:auniverse:auniverse` (or `auniverse`, if you added it by hand) with **✔ Connected**. Inside Claude Code, `/mcp` shows the same with the number of tools. Then ask: "Who am I on AUniverse?"

With the plugin, that list is the test of the token it saved: a 401 there means the server refuses it. For a token in `$AUNIVERSE_TOKEN`, [`scripts/connect.sh --check`](../scripts/connect.sh), from a copy of this repository, tests it directly against the server.

## Tool names and permissions

Claude Code shows the AUniverse tools under these names:

<!-- generated:tool-names -->
- Plugin: `mcp__plugin_auniverse_auniverse__<tool>`, for example `mcp__plugin_auniverse_auniverse__auniverse_whoami`
- Added by hand: `mcp__auniverse__<tool>`, for example `mcp__auniverse__auniverse_whoami`
<!-- /generated:tool-names -->

Depending on your permission mode, Claude Code asks before each tool call or lets auto mode decide, and in scripts (`claude -p`) it refuses tools you haven't allowed. Every AUniverse tool today only reads, so you may let them all run. The lists below name each tool rather than the whole server, so tools that can post or change things, when they arrive, will still ask first.

Add the entries to the `permissions.allow` list in `~/.claude/settings.json` (or a project's `.claude/settings.json`), and keep everything else in the file. Installing the plugin already wrote its settings there: replacing the file with the snippet would switch the plugin off. Or add them one at a time with `/permissions` inside Claude Code.

Plugin:

<!-- generated:permissions-plugin -->
```json
{
  "permissions": {
    "allow": [
      "mcp__plugin_auniverse_auniverse__auniverse_whoami",
      "mcp__plugin_auniverse_auniverse__poster_search",
      "mcp__plugin_auniverse_auniverse__poster_get",
      "mcp__plugin_auniverse_auniverse__poster_list_tags",
      "mcp__plugin_auniverse_auniverse__poster_list_boards",
      "mcp__plugin_auniverse_auniverse__poster_board_registry"
    ]
  }
}
```
<!-- /generated:permissions-plugin -->

Added by hand:

<!-- generated:permissions-manual -->
```json
{
  "permissions": {
    "allow": [
      "mcp__auniverse__auniverse_whoami",
      "mcp__auniverse__poster_search",
      "mcp__auniverse__poster_get",
      "mcp__auniverse__poster_list_tags",
      "mcp__auniverse__poster_list_boards",
      "mcp__auniverse__poster_board_registry"
    ]
  }
}
```
<!-- /generated:permissions-manual -->

<!-- generated:prompts -->
The server's prompt appears as a slash command: type `/` and look for **whats_on**.
<!-- /generated:prompts -->

## Remove it

<!-- generated:remove -->
```bash
claude plugin uninstall auniverse@auniverse
claude mcp remove auniverse --scope user
```
<!-- /generated:remove -->

Run the line for the way you installed it. To stop the token working everywhere, revoke it in **Profile → MCP**.

## Troubleshooting

| What you see | What it means | What to do |
|---|---|---|
| `Missing environment variables: AUNIVERSE_TOKEN` under "MCP config diagnostics" | Claude Code can't see the variable | Add the `export` line to your shell profile and open a new terminal. Or switch to the plugin: remove the hand-added entry first (`claude mcp remove auniverse --scope user`) |
| `Server rejected the configured Authorization header (HTTP 401)` with "Not an AUniverse personal access token" | Claude Code sent something that isn't a whole token. Usually the variable isn't set, so it sent `${AUNIVERSE_TOKEN}` itself; or the token was cut short when copied | Check for "Missing environment variables" in `claude mcp list`, then copy the token again |
| `Server rejected the configured Authorization header (HTTP 401)` with `INVALID_TOKEN` or "Sign in with an AUniverse personal access token" | The token is wrong, expired or revoked, or the variable is empty | Create a new one in Profile → MCP and update the variable or the plugin (see [Plugin](#plugin)). If `claude mcp get auniverse` shows `Authorization: Bearer` with nothing after it, the server was added with double quotes before the variable was set: remove it and add it again with the single-quoted command |
| `Dynamic Client Registration rejected (HTTP 404)`, or an **Authenticate** button in `/mcp` | No token was sent, so Claude Code tried a sign-in AUniverse doesn't offer yet | Add the server with the `--header` part, or configure the plugin's token |
| `Insufficient scope: required "…"` when a tool is called | Your account allows that tool but this token lacks its scope | Create a token with the scopes it lists |
| `429` | Too many requests in a minute | Wait for the number of seconds it gives |
| `HTTP 503` with "isn't available on this server right now" | The connector is switched off on the server: before launch, that's expected (see the status at the top of the [README](../README.md)) | Try again later |
| `ENOTFOUND` or `ECONNREFUSED` for `api.auniverse.space` | The server can't be reached: before launch, that's expected; otherwise it's down or your network blocks it | Check the README's status, then try again later or from another network |
| `already exists in user config` | You ran `claude mcp add` twice | Run `claude mcp remove auniverse --scope user`, then add it again |
| The plugin's server isn't listed at all | The plugin has no token yet, or a server added by hand for the same address hides it (`claude mcp list` then shows that one instead) | Configure the token (see Plugin above), or remove the hand-added entry with `claude mcp remove <its name> --scope user` |

More in [troubleshooting.md](troubleshooting.md).
