# AUniverse MCP connector

Connect your own AI assistant to [AUniverse](https://auniverse.space), the Adelaide University community app. Once connected, Claude Code or Codex can find what's on around campus, open a poster's details and look up the paper noticeboards for you. It acts as you, and it can never do more than you can on the website.

This repository is the client side: setup for **Claude Code** and **Codex**, the two assistants supported for now. The server it connects to is part of AUniverse itself, and this repository follows it.

<!-- generated:status -->
> **Status: live** at `https://api.auniverse.space/mcp`.
<!-- /generated:status -->

## What you can ask

- "What's on tonight near Hub Central?"
- "What's pinned on the Barr Smith Library board?"
- "Anything social at Magill this week?"
- "Show me the posters I've posted, drafts included."
- "Tell me more about the first one: when, where, and how many are going?"

Posting events, and turning photos of posters into events, come in later releases. They will always ask you before anything is published.

## 1. Get a token

1. Sign in at [auniverse.space](https://auniverse.space) and open **Profile → MCP**.
2. Create a token. Name it after where you'll use it (for example "Claude Code on my laptop"), keep `poster:read` ticked, and re-enter your password.
3. Copy it straight away: it is shown once. It starts with `aun_pat_`. Keep it like a password: don't paste it into a chat with your assistant, and don't publish the file you keep it in (on a computer you share with others, make that file private: `chmod 600 ~/.zshrc`).

Signed up with Google or a passkey? Add a password on the Security page first; creating a token asks for it. Changing or resetting your password later revokes the tokens you created before. Accounts with limited access can't create tokens.

After you create a token, the page also shows a `claude mcp add` command with your token inside it. Skip it and follow step 2 instead: that command saves the token itself in `~/.claude.json`, and it would hide the Claude Code plugin. If you already ran it, undo it with `claude mcp remove auniverse --scope user`.

## 2. Connect your assistant

### Claude Code

Install the plugin, which saves your token with Claude Code's own credentials (in the macOS keychain on a Mac; elsewhere in `~/.claude/.credentials.json`, a file only you can read):

<!-- generated:claude-code-plugin -->
```bash
claude plugin marketplace add CosmosRobotLab/AUniverse-mcp-connector
claude plugin install auniverse@auniverse
```
<!-- /generated:claude-code-plugin -->

Then start `claude`, run `/plugin`, open **Installed → auniverse → Configure options**, paste your token, and restart Claude Code.

Or add the server by hand, with the token in an environment variable (put the `export` line in your shell profile rather than typing it, so it stays out of your shell history):

<!-- generated:claude-code-manual -->
```bash
export AUNIVERSE_TOKEN="aun_pat_..."
claude mcp add --transport http --scope user auniverse https://api.auniverse.space/mcp --header 'Authorization: Bearer ${AUNIVERSE_TOKEN}'
```
<!-- /generated:claude-code-manual -->

Use one way, not both: a server added by hand hides the plugin's. Windows, project setup, updates and troubleshooting: [docs/claude-code.md](docs/claude-code.md).

### Codex

Put the `export` line in your shell profile, open a new terminal, then add the server:

<!-- generated:codex -->
```bash
export AUNIVERSE_TOKEN="aun_pat_..."
codex mcp add auniverse --url https://api.auniverse.space/mcp --bearer-token-env-var AUNIVERSE_TOKEN
```
<!-- /generated:codex -->

Codex keeps a background server running after you quit it, with the environment it started with. If you used Codex before setting the variable, run `codex app-server daemon restart` from a terminal that has it. Windows, the IDE extension, the desktop app and troubleshooting: [docs/codex.md](docs/codex.md).

### Or let the script do it

On macOS, Linux or WSL, from a copy of this repository:

```bash
git clone https://github.com/CosmosRobotLab/AUniverse-mcp-connector.git
cd AUniverse-mcp-connector
scripts/connect.sh all        # or: claude, or: codex
```

It checks your token with the server first, then sets up whichever assistants you have. It leaves an existing setup alone and tells you, unless you add `--replace`; when your token expires, run it again with the new one. For Claude Code it needs version 2.1.285 or later (`claude update`). Run `scripts/connect.sh --help` for the options.

## 3. Check it works

Ask your assistant: "Who am I on AUniverse?" It should answer with your account level and the tools you can use.

To test the token on its own, from a copy of this repository: `scripts/connect.sh --check`. With the Claude Code plugin, `claude mcp list` shows whether the token it saved works.

## What it can do

<!-- generated:tools -->
| Tool | What it does | Who |
|---|---|---|
| `auniverse_whoami` | Who am I on AUniverse | anyone with a token |
| `poster_search` | Search posters | all members |
| `poster_get` | Get a poster | all members |
| `poster_list_tags` | List poster tags | all members |
| `poster_list_boards` | List noticeboards | all members |
| `poster_board_registry` | Noticeboard registry (admins) | admins |
<!-- /generated:tools -->

Your assistant only sees the tools your account level allows. Every tool, with its arguments, is in [docs/tools.md](docs/tools.md), and the official guide is at [auniverse.space/developers/mcp](https://auniverse.space/developers/mcp).

## Good to know

- **It acts as you.** Your account is checked on every call: if it is suspended or your level changes, your tokens follow at once.
- **Scopes.** A token only carries the scopes you ticked. If your level allows a tool but the token lacks its scope, the server refuses the call and names the scope; create a new token with it. (Claude Code lists the scopes after "Insufficient scope"; Codex shows only "Insufficient scope", so ask "Who am I on AUniverse?" to see which scope each tool needs.)
- **Nothing happens behind your back.** Today every tool only reads. Tools that post or change things will always ask you first in the chat.
- **Poster text is other people's writing.** The server marks it as untrusted and tells your assistant to show it, never to follow instructions inside it.
- **Revoke any time** in Profile → MCP: the token stops working at once.
- **Limits:** 60 requests a minute for each person, across all your tokens and assistants. Tokens last 90 days unless you choose otherwise (at most 365), and you can have 20 at a time. You can try to create a token 10 times an hour, mistyped passwords included.
- **Privacy:** each call is logged with who, which tool, the outcome and how long it took. The arguments (what you searched for) are kept only as a keyed fingerprint, not as text. Site admins can see your tokens' names, scopes and when they were last used, and can revoke one if it is misused; they never see the token itself. Your AI provider handles what the tools return under its own terms.
- **Other assistants:** claude.ai, Claude Desktop and phones will connect with an AUniverse sign-in instead of a token, later. This connector covers Claude Code and Codex.

Something not working? See [docs/troubleshooting.md](docs/troubleshooting.md).

## Keeping up to date

When AUniverse changes its server, this repository changes with it. With the Claude Code plugin you get the change from `claude plugin update` (see [docs/claude-code.md](docs/claude-code.md#updates)). If you set things up by hand and something stops working, check here for changed steps. Maintainers: see [MAINTAINING.md](MAINTAINING.md).
