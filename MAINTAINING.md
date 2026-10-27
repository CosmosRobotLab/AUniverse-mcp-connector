# Maintaining the connector

The AUniverse MCP server (in the main AUniverse repository, `backend/app/mcp` and the sub-app toolsets) is the source of truth. This repository repeats what clients need to know about it, so **every change to the server's connection details, tools, scopes, resources or prompts needs a matching change here**, ideally in the same week the server change merges.

Most of that is mechanical. `scripts/sync.mjs` regenerates the repeated facts it can from two files, and CI fails when anything generated is out of date, or when the prose still says every tool only reads or still talks about the time before launch after that stopped being true (see [Checks](#checks)). Nothing checks the rest of the prose, and the tables below say where it is.

| File | What it holds | Edited by |
|---|---|---|
| [`connector.json`](connector.json) | Client-side facts: server name, URLs, token format, the environment variable, status, plugin names, the connector `version` | Hand |
| [`catalog/auniverse-catalog.json`](catalog/auniverse-catalog.json) | The server's own catalogue (`GET /api/mcp/catalog`): tools with their input and output schemas, scopes, resources, prompts, server instructions | `sync.mjs --from` |
| `docs/tools.md`, `templates/`, `.claude-plugin/`, `plugins/` | Tool reference, config templates, the Claude Code plugin and marketplace | `sync.mjs` (whole files) |
| `README.md`, `docs/claude-code.md`, `docs/codex.md`, `docs/troubleshooting.md`, `scripts/connect.sh` | Prose by hand; commands, tool tables, the status note and constants between `generated:` markers | Hand, plus `sync.mjs` between the markers |

## When the server changes

1. **Refresh the catalogue.** With the AUniverse dev stack running from the branch that has the change (see the main repository's `start-local-dev` skill), run:

   ```bash
   node scripts/sync.mjs --from http://localhost:<BACKEND_PORT>/api/mcp/catalog --label "AUniverse main @ <short commit>"
   ```

   Once the production server has the change, `--from https://auniverse.space/api/mcp/catalog` works too, and it also checks `connector.json` against production (whether the connector is switched on, its URL, the docs URL). Any deployment's catalogue is rewritten to the production URLs, so the snapshot doesn't depend on where it came from. Use a deployment with the default toolsets (`MCP_ENABLED_TOOLSETS` unset).

   If `server.auth` or `server.transport` changed (for example when OAuth sign-in ships), `sync.mjs` stops on purpose: rethink the client setups and the sign-in advice first (the "Dynamic Client Registration", "Authenticate" and "Don't run `codex mcp login`" rows in the docs), then run it again with `--accept-auth-change`.

2. **Read the list of changes it prints**, and do the hand edits it calls for:

   | Server change | Also update by hand |
   |---|---|
   | New or removed tool, or a tool's meaning changed | The "What you can ask" examples in `README.md` if they no longer fit; the troubleshooting tables if it brings new error codes |
   | A tool that writes (the list marks it "(writes)" or "(now writes)") | "Nothing happens behind your back" in `README.md` and the permission advice in `docs/claude-code.md` (the generated allowlists only ever include read-only tools). CI fails until neither says every tool only reads |
   | New toolset (a new sub-app) | `README.md` intro and examples |
   | Scope added or renamed | Token instructions in `README.md`, `docs/claude-code.md`, `docs/codex.md` |
   | `auniverse_whoami` renamed, or its output changed | `check_token` and `summarise` in `scripts/connect.sh`, which call it and read `user_id`, `level_name`, `effective_scopes`, `credential.expires_at` and `tools[].status`/`required_scope`; `CHECK_TOOL` in `scripts/sync.mjs` (the PowerShell check in `docs/troubleshooting.md` is generated from it). `sync.mjs` stops if the tool disappears |
   | Prompt or resource added, renamed or removed | Nothing: the prompt line in `docs/claude-code.md` and `docs/tools.md` are generated |
   | `server.instructions` changed | Usually nothing; check the README's promises still match |

3. **Facts that aren't in the catalogue** live in `connector.json` or in the prose. Check them against the server whenever you touch it:

   | Fact | Where the server defines it |
   |---|---|
   | `server.name` (`auniverse`) | `backend/app/mcp/server.py` `SERVER_NAME`; `frontend/src/features/developers/connectSnippets.ts` `MCP_SERVER_NAME` |
   | `server.title`, `server.description` | `backend/app/mcp/server.py` `SERVER_TITLE` and `description=` |
   | `server.url` | `services/server-side/prod-services/docker-compose.yml` `MCP_PUBLIC_URL` |
   | `other_servers.staging` | `services/server-side/staging-services/docker-compose.yml` `MCP_PUBLIC_URL` |
   | `other_servers.local` | `backend/app/mcp/config.py` (`http://localhost:{BACKEND_PORT or 8000}/mcp`) |
   | `server.status` and `status_note` | Production's catalogue, `server.enabled` (`sync.mjs --from https://auniverse.space/api/mcp/catalog` compares them). It is off while `MCP_ENABLED` is off, and also when the server's MCP settings are incomplete (`backend/app/mcp/config.py`, `server.py`). See [Going live](#going-live) |
   | `server.docs`, `server.catalog`, `server.token_page` | `MCP_DOCS_URL`; `backend/app/mcp/router.py`; the user center route `/user-profile/connections` |
   | `auth.header`, `auth.scheme` | `backend/app/mcp/gate.py` (`Authorization: Bearer`) |
   | `auth.token_prefix`, `auth.token_pattern` | `backend/app/mcp/auth/tokens.py` (`aun_pat_` plus 43 base62 characters) |
   | `auth.env_var` (`AUNIVERSE_TOKEN`) | `connectSnippets.ts` `TOKEN_ENV_VAR` |
   | The "What you can ask" examples in `README.md` | `frontend/src/features/developers/assistant/assistantContent.ts` `POSTER_ASKS` |
   | Limits, privacy and revocation in `README.md` and `docs/troubleshooting.md` | `backend/app/core/config.py` (`MCP_RATE_LIMIT_PER_MINUTE`, `MCP_PAT_*`), `backend/app/mcp/auth/service.py`, `backend/app/mcp/audit.py`, and the "Limits" and "Privacy and safety" sections of `frontend/public/developers/mcp/index.md` |
   | Error codes in `docs/troubleshooting.md` | Before a tool runs: `backend/app/mcp/gate.py`, `errors.py`, `auth/verifier.py`, and the switched-off answer in `server.py`. From tools: `backend/app/core/policy.py` (`FORBIDDEN`, `INSUFFICIENT_SCOPE`), `backend/app/mcp/registry.py` and `server.py` (`INVALID_ARGUMENTS`, `UNKNOWN_TOOL`, `INTERNAL_ERROR`), `backend/app/core/error_handler.py` (`NOT_FOUND`), `backend/app/modules/poster/search.py` (`INVALID_SORT`, `UNKNOWN_BOARD`, `INVALID_CURSOR`) and `backend/app/modules/noticeboards/service.py` (`INVALID_NEAR`, `UNKNOWN_CAMPUS`) |

   The website and the official guide repeat some of this for their own readers: `connectSnippets.ts` and `tokens/PersonalTokens.tsx` (the commands shown on the token page), `frontend/public/developers/mcp/index.md` and `frontend/public/llms.txt`. When they disagree with this repository, raise it in the AUniverse repository rather than copying them.

4. **Raise `version` in `connector.json`** whenever anything a user receives changes. Claude Code only offers a plugin update when the plugin's version goes up, and the plugin's version is this one. `sync.mjs` compares the plugin with the last commit and keeps saying so until the version is higher than that commit's, and CI fails on a push or pull request that changes the plugin without it.

5. Run `node scripts/sync.mjs`, then `node scripts/sync.mjs --check`, and open a pull request. Mention the server change it follows.

## Going live

When production switches the connector on:

1. Set `server.status` to `live` in `connector.json`, raise `version`, and run `node scripts/sync.mjs`. That updates the README's status line and the script's messages.
2. `sync.mjs` then lists the hand-written lines that still talk about the time before launch (the "before launch, that's expected" rows in `docs/claude-code.md`, `docs/codex.md` and `docs/troubleshooting.md`). Reword them to describe an outage, and run it again until it stops complaining.
3. Check with `node scripts/sync.mjs --check --from https://auniverse.space/api/mcp/catalog`.

## Renaming the server, the variable or the plugin

Changing `server.name`, `auth.env_var` or `plugin.name` in `connector.json` regenerates the commands, but the prose names them too. Search the hand-written files for the old name and replace it. If the plugin's name changes, `sync.mjs` lists the old plugin files to delete.

## Checks

CI ([`.github/workflows/check.yml`](.github/workflows/check.yml)) runs on every push and pull request:

- `node scripts/sync.mjs --check`: everything generated matches `connector.json` and the snapshot, no stray files are left in the generated directories, and the hand-written prose doesn't promise something the catalogue or `connector.json` has made untrue (every tool only reads; before launch).
- `--since` the pull request's base branch, or what the branch was before the push: the plugin didn't change without `version` going up.
- `node --test scripts/sync.test.mjs`: the generator's own tests. They use a small fixed connector and catalogue of their own, so a server change doesn't touch them; change them when you change how something is generated.
- ShellCheck on `scripts/connect.sh` (with the ShellCheck the runner has; the script passes 0.9 and 0.11), the script under `sh -n`, and that git keeps it executable.
- `claude plugin validate --strict` on the marketplace and every plugin in `plugins/`.

The generator needs Node 20 or later.

To compare with a live server, run the workflow by hand (**Actions → Check → Run workflow**) with a catalogue URL. It runs `node scripts/sync.mjs --check --from <url>` and fails if the server has changed since the snapshot, or, for production's catalogue, if `connector.json` disagrees with it. It never runs on a schedule, so nothing contacts AUniverse unless someone asks.

## Testing against staging or a local server

Tokens only work on the server they were created on, so use a separate name and variable for each:

```bash
export AUNIVERSE_DEV_TOKEN="aun_pat_..."   # created in your local web app's Profile → MCP
scripts/connect.sh --check --url http://localhost:<BACKEND_PORT>/mcp --env-var AUNIVERSE_DEV_TOKEN
scripts/connect.sh all --url http://localhost:<BACKEND_PORT>/mcp --env-var AUNIVERSE_DEV_TOKEN   # adds "auniverse-dev"
```

By hand:

```bash
claude mcp add --transport http --scope user auniverse-dev http://localhost:<BACKEND_PORT>/mcp --header 'Authorization: Bearer ${AUNIVERSE_DEV_TOKEN}'
codex mcp add auniverse-dev --url http://localhost:<BACKEND_PORT>/mcp --bearer-token-env-var AUNIVERSE_DEV_TOKEN
```

For staging, use `https://staging-api.auniverse.space/mcp` and a token from `staging.auniverse.space`. The script only accepts plain `http://` for a server on your own computer.

## Testing the plugin before it is merged

The plugin always points at production, so test it from a scratch copy pointed at your local server, and never commit that copy. If you added `auniverse-dev` by hand for the same local URL (above), remove it first (`claude mcp remove auniverse-dev -s user`): it would hide the plugin's server, and the script refuses until it is gone.

```bash
cp -R . /tmp/auniverse-connector-test && cd /tmp/auniverse-connector-test
# In connector.json, set server.url to http://localhost:<BACKEND_PORT>/mcp, then:
node scripts/sync.mjs
claude plugin validate --strict .
AUNIVERSE_TOKEN="$AUNIVERSE_DEV_TOKEN" scripts/connect.sh claude --marketplace "$PWD"
```

`sync.mjs` asks you to raise the version there; in a scratch copy you can ignore that. The copy's script and plugin both use the local URL. If you already have the `auniverse` marketplace from GitHub, add `--replace` to switch it to the copy. Afterwards, `claude plugin uninstall auniverse@auniverse` and `claude plugin marketplace remove auniverse`, then install it again the normal way.
