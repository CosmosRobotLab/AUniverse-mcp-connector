# Troubleshooting

First, ask your assistant: "Who am I on AUniverse?" If it answers, the connection works, and the answer lists your level and the tools you can use.

If it doesn't, the check script tells a token problem from a client setup problem: it sends your token straight to the server and says what the server thinks of it. It needs a copy of this repository and macOS, Linux or WSL (see the [README](../README.md#or-let-the-script-do-it)):

```bash
scripts/connect.sh --check
```

It tests the token in `$AUNIVERSE_TOKEN` (or one you paste). Two cases it can't see:

- **The Claude Code plugin** keeps its own copy of the token. Run `claude mcp list` instead: a 401 there means the server refuses the saved token. Give the plugin a new one as [claude-code.md](claude-code.md#plugin) describes, or with `scripts/connect.sh claude`.
- **Codex with `~/.codex/.env`.** A token in that file wins over the one in your shell, so make sure it is the one you checked. The script warns when the two differ.

On Windows without WSL, this PowerShell line does the same check:

<!-- generated:check-powershell -->
```powershell
(Invoke-RestMethod -Method Post https://api.auniverse.space/mcp -ContentType application/json -Headers @{ Authorization = "Bearer $env:AUNIVERSE_TOKEN"; Accept = 'application/json, text/event-stream' } -Body '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"auniverse_whoami","arguments":{}}}').result.structuredContent
```
<!-- /generated:check-powershell -->

If it lists your `level_name` and `effective_scopes`, the token works. An error that mentions 401 means the server refuses the token; for any other error, see the table below.

Client-specific messages are in [claude-code.md](claude-code.md#troubleshooting) and [codex.md](codex.md#troubleshooting).

## What the server answers

Refusals before a tool runs come back as HTTP errors with a JSON-RPC error body: `error.message` says what to do and `error.data.code` is a stable code. Errors from a tool itself come back as a normal result with `isError: true` and `{"error": {"code", "message"}}`.

| Answer | Meaning | What to do |
|---|---|---|
| HTTP 401, `UNAUTHORIZED` (JSON-RPC `-32010`) | No token was sent, or an empty one | Check that your client sends `Authorization: Bearer aun_pat_...`: the variable is set, isn't empty, and the client can see it |
| HTTP 401, `INVALID_TOKEN`, "Not an AUniverse personal access token" | What arrived isn't a whole token. Usually the variable isn't set, so the client sent `${AUNIVERSE_TOKEN}` itself; or the token was cut short when copied; or it's the website's sign-in token | Set the variable (or the plugin's token), copying the whole `aun_pat_` token again |
| HTTP 401, `INVALID_TOKEN`, any other message | The token isn't valid. For your privacy the server doesn't say whether it was mistyped, expired or revoked, or the account was suspended | Create a new token in Profile → MCP |
| HTTP 403 `INSUFFICIENT_SCOPE` (`-32011`) | Your level allows the tool, resource or prompt, but this token lacks the scope | Create a token with the scopes in `error.data.scopes_to_request` |
| HTTP 429 `RATE_LIMITED` (`-32012`) | Over 60 requests in a minute (for you, across all your tokens) | Wait for the `Retry-After` seconds |
| HTTP 503 `MCP_DISABLED` or `MCP_UNAVAILABLE` (`-32013`) | The connector is switched off on this server, is still starting, or a server-side safety check is holding it back | Try again later |
| HTTP 405 on a GET | Normal: the server answers POST only and never streams | Nothing to fix; clients cope with it |
| Tool error `FORBIDDEN` | Your account level doesn't allow this tool | Nothing to fix: it isn't for your role |
| Tool error `NOT_FOUND` | The poster doesn't exist, or isn't visible to you | Check the id; private posters are only visible to their owner |
| Tool error `INVALID_ARGUMENTS`, `INVALID_SORT`, `INVALID_NEAR`, `UNKNOWN_BOARD`, `UNKNOWN_CAMPUS`, `INVALID_CURSOR` | Something in the request is off | The assistant usually retries with fixed input; the message says what |
| Tool error `UNKNOWN_TOOL`, `INTERNAL_ERROR` | No such tool, or a fault on AUniverse's side | Check the tool list; otherwise try again later |

## Common situations

**The client says the sign-in failed, or offers an "Authenticate" or "login" button.** AUniverse doesn't have that sign-in yet, so this always means the token didn't arrive or wasn't accepted. Check the variable, or create a new token. Don't use the client's login command: it fails.

**It worked yesterday.** Tokens expire (90 days unless you chose otherwise). Changing or resetting your password revokes the tokens created before it, and so does a suspension, a ban or deleting the account; an admin can also revoke a token that is misused. Create a new one and give it to your assistant: for the Claude Code plugin see [claude-code.md](claude-code.md#plugin), or run `scripts/connect.sh claude`; otherwise update the variable. In Codex, if you put the token in `~/.codex/.env`, replace it there too (that file wins over your shell), then restart the [background server](codex.md#codexs-background-server).

**It works in a terminal but not in the app or the editor.** Apps started from the Dock, Start menu or an app launcher often don't see variables from your shell profile. In Claude Code, switch to the plugin (removing the hand-added entry first); in Codex, put the token in `~/.codex/.env`. Or start the editor from a terminal.

**`https://api.auniverse.space/mcp` answers that the connector "isn't available on this server right now".** The connector has been switched off on the server for a while, for example for maintenance. Try again later.

**Your assistant can't see a tool from the [tool list](tools.md).** Each tool is only shown to the account levels that may use it. Ask "Who am I on AUniverse?" to see your level and the tools available to you.

Still stuck? Open an issue in this repository with the client, what you ran and the message you got. Never paste your token, there or in a chat with your assistant.
