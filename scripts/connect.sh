#!/bin/sh
# Connect Claude Code and Codex to AUniverse, or check that your token works.
# Run `scripts/connect.sh --help` for how to use it. Needs sh and curl: macOS, Linux and WSL.

set -u

# >>> generated:constants
SERVER_NAME='auniverse'
DEFAULT_URL='https://api.auniverse.space/mcp'
DEFAULT_ENV_VAR='AUNIVERSE_TOKEN'
AUTH_HEADER='Authorization'
AUTH_SCHEME='Bearer'
TOKEN_PREFIX='aun_pat_'
TOKEN_PATTERN='^aun_pat_[A-Za-z0-9]{43}$'
TOKEN_PAGE='https://auniverse.space/user-profile/connections'
STATUS_NOTE='The connector isn'\''t switched on in production yet. Until it is, https://api.auniverse.space/mcp answers that the connector "isn'\''t available on this server right now", and Profile → MCP can'\''t create tokens.'
PLUGIN_REPO='CosmosRobotLab/AUniverse-mcp-connector'
PLUGIN_MARKETPLACE='auniverse'
PLUGIN_REF='auniverse@auniverse'
# <<< generated:constants

usage() {
  cat <<EOF
Connect Claude Code and Codex to AUniverse, or check that your token works.

  scripts/connect.sh --check   test your token against the AUniverse server
  scripts/connect.sh claude    Claude Code: install the plugin and give it your token
  scripts/connect.sh codex     Codex: add the server; it reads your token from \$$DEFAULT_ENV_VAR
  scripts/connect.sh all       both

Options:
  --manual           Claude Code: add the server by hand (it reads \$$DEFAULT_ENV_VAR) instead of
                     the plugin
  --replace          replace an existing AUniverse setup (a server entry, the plugin, or the
                     plugin's saved token) instead of keeping it. A saved plugin token that the
                     server refuses is replaced anyway, by one that passed the check
  --no-check         skip the token check
  --url URL          a different server (AUniverse developers: staging or local); implies --manual
  --name NAME        the server's name in your client (default: $SERVER_NAME, or $SERVER_NAME-dev
                     with --url)
  --env-var NAME     the variable that holds the token (default: $DEFAULT_ENV_VAR)
  --marketplace SRC  where to get the Claude Code plugin: owner/repo or a local checkout
                     (default: $PLUGIN_REPO)

The token comes from \$$DEFAULT_ENV_VAR (or the --env-var variable), or the script asks for it.
It goes only to the AUniverse server for the check and, for the plugin, to Claude Code, which
saves it with its own credentials. The script never prints it.

--check exits with 0 when the token works, 1 when the server refuses it, 2 when the server
can't be used right now, and 3 when the URL isn't an AUniverse MCP server. Setting up exits
with 0 when everything was set up, and 1 otherwise.

Setting up the Claude Code plugin needs Claude Code $MIN_CLAUDE or later.

On Windows without WSL, follow docs/claude-code.md or docs/codex.md instead.
EOF
}

CLIENTS=""
CHECK_ONLY=0
MANUAL=0
REPLACE=0
DO_CHECK=1
URL="$DEFAULT_URL"
NAME=""
ENV_VAR="$DEFAULT_ENV_VAR"
CUSTOM_URL=0
MARKETPLACE="$PLUGIN_REPO"

# The first Claude Code with `claude plugin configure`, which saves the plugin's token.
MIN_CLAUDE='2.1.285'

say() { printf '%s\n' "$*"; }
warn() { printf '! %s\n' "$*" >&2; }
die() { printf 'x %s\n' "$*" >&2; exit 1; }

for arg in "$@"; do
  case "$arg" in
    *"$TOKEN_PREFIX"*) die "Don't put the token on the command line: it stays in your shell history. Set \$$DEFAULT_ENV_VAR, or leave it out and paste it when the script asks." ;;
  esac
done

while [ $# -gt 0 ]; do
  case "$1" in
    claude|codex) CLIENTS="$CLIENTS $1" ;;
    all) CLIENTS=" claude codex" ;;
    --check) CHECK_ONLY=1 ;;
    --manual) MANUAL=1 ;;
    --replace) REPLACE=1 ;;
    --no-check) DO_CHECK=0 ;;
    --url) [ $# -ge 2 ] || die "--url needs a URL"; URL="${2%/}"; CUSTOM_URL=1; shift ;;
    --name) [ $# -ge 2 ] || die "--name needs a name"; NAME="$2"; shift ;;
    --env-var) [ $# -ge 2 ] || die "--env-var needs a variable name"; ENV_VAR="$2"; shift ;;
    --marketplace) [ $# -ge 2 ] || die "--marketplace needs owner/repo or a path"; MARKETPLACE="$2"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "Unknown argument: $1" ;;
  esac
  shift
done

[ -n "$CLIENTS" ] || [ "$CHECK_ONLY" -eq 1 ] || { usage >&2; exit 1; }
case "$ENV_VAR" in
  *[!A-Za-z0-9_]*|[0-9]*|"") die "--env-var must be a variable name, like $DEFAULT_ENV_VAR" ;;
esac
# Plain http:// would send the token unencrypted, so it is only for a server on this computer.
authority=${URL#*://}
authority=${authority%%/*}
case "$authority" in
  *@*) die "--url can't contain a user name or password (the part before @)." ;;
esac
case "$URL" in
  https://?*) ;;
  http://*)
    case "$authority" in
      localhost|127.0.0.1|'[::1]') ;;
      localhost:*|127.0.0.1:*|'[::1]':*)
        case "${authority##*:}" in
          ""|*[!0-9]*) die "$URL: the port after the colon should be a number, like http://localhost:8000/mcp." ;;
        esac ;;
      *) die "Use https:// for $URL: over http:// your token would travel unencrypted. (http:// is only for a server on this computer, like http://localhost:8000/mcp.)" ;;
    esac ;;
  *) die "--url must be a whole URL that starts with https://" ;;
esac
if [ "$CUSTOM_URL" -eq 1 ] && [ "$URL" != "$DEFAULT_URL" ]; then
  MANUAL=1
  [ -n "$NAME" ] || NAME="$SERVER_NAME-dev"
fi
[ -n "$NAME" ] || NAME="$SERVER_NAME"
case "$NAME" in
  -*|*[!A-Za-z0-9_-]*) die "--name may use letters, digits, - and _ only, and must start with a letter or digit" ;;
esac
case "$MARKETPLACE" in
  -*|"") die "--marketplace needs owner/repo or a path" ;;
esac

command -v curl >/dev/null 2>&1 || die "This script needs curl."

# Temporary files are removed however the script ends.
BODY=""
ERRS=""
NEUTRAL=""
# shellcheck disable=SC2317,SC2329 # called by the EXIT trap
cleanup() {
  [ -z "$BODY" ] || rm -f "$BODY"
  [ -z "$ERRS" ] || rm -f "$ERRS"
  [ -z "$NEUTRAL" ] || rmdir "$NEUTRAL" 2>/dev/null
}
trap cleanup EXIT
trap 'exit 130' INT TERM HUP QUIT

# ---------- the token ----------

TOKEN=$(eval "printf '%s' \"\${$ENV_VAR:-}\"")
TOKEN_FROM_ENV=1
if [ -z "$TOKEN" ]; then
  TOKEN_FROM_ENV=0
  [ -t 0 ] || die "Set $ENV_VAR to your token first (create one at $TOKEN_PAGE)."
  say "Paste your AUniverse personal access token (from $TOKEN_PAGE)."
  say "It won't be shown as you type or paste."
  printf 'Token: '
  # Put the terminal back however the read ends.
  trap 'stty echo 2>/dev/null; printf "\n"; exit 130' INT TERM HUP QUIT
  stty -echo 2>/dev/null
  IFS= read -r TOKEN || true
  stty echo 2>/dev/null
  trap 'exit 130' INT TERM HUP QUIT
  printf '\n'
  [ -n "$TOKEN" ] || die "No token given."
fi
CLEAN=$(printf '%s' "$TOKEN" | tr -d ' \r\n\t')
TOKEN_DIRTY=0
if [ "$TOKEN_FROM_ENV" -eq 1 ] && [ "$CLEAN" != "$TOKEN" ]; then
  TOKEN_DIRTY=1
fi
TOKEN=$CLEAN
if ! printf '%s' "$TOKEN" | grep -Eq "$TOKEN_PATTERN"; then
  case "$TOKEN" in
    "$TOKEN_PREFIX"*) die "That doesn't look like a whole token: $TOKEN_PREFIX followed by 43 letters and digits. Copy it again." ;;
    *) die "That isn't an AUniverse personal access token (they start with $TOKEN_PREFIX). The website's sign-in token doesn't work here." ;;
  esac
fi
if [ "$TOKEN_DIRTY" -eq 1 ]; then
  warn "\$$ENV_VAR has a space or a line break around the token. Codex sends it as it is and can't connect: fix the line that sets it (a file saved with Windows line endings does this)."
fi

# Codex reads this file when it starts, and its values win over the environment.
CODEX_DOTENV="${CODEX_HOME:-$HOME/.codex}/.env"

# The value $CODEX_DOTENV gives $ENV_VAR, without quotes; fails when it doesn't set it.
codex_dotenv_value() {
  [ -f "$CODEX_DOTENV" ] || return 1
  line=$(grep -E "^[[:space:]]*(export[[:space:]]+)?${ENV_VAR}[[:space:]]*=" "$CODEX_DOTENV" 2>/dev/null | tail -n 1)
  [ -n "$line" ] || return 1
  printf '%s' "${line#*=}" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'\$/\1/"
}

# ---------- the check ----------

# python3, unless it is the stand-in on a Mac without the developer tools, which only offers to install them.
have_python() {
  command -v python3 >/dev/null 2>&1 || return 1
  [ "$(uname -s)" != Darwin ] || [ "$(command -v python3)" != /usr/bin/python3 ] || xcode-select -p >/dev/null 2>&1
}

# Pretty-prints a whoami result with python3 or node, or just the level without either.
summarise() {
  if have_python; then
    python3 -I -c '
import json, sys
try:
    who = json.loads(sys.stdin.read())["result"]["structuredContent"]
except Exception:
    sys.exit(0)
tools = who.get("tools") or []
print("  Account level: %s" % (who.get("level_name") or who.get("level")))
print("  Token scopes:  %s" % (", ".join(who.get("effective_scopes") or []) or "none"))
cred = who.get("credential") or {}
if cred.get("expires_at"):
    print("  Token expires: %s" % cred["expires_at"][:10])
print("  Tools you can use: %s" % (", ".join(t["name"] for t in tools if t.get("status") == "available") or "none"))
needs = ["%s (needs %s)" % (t["name"], t.get("required_scope")) for t in tools if t.get("status") == "needs_scope"]
if needs:
    print("  Your level also allows these, with a token that has their scope: %s" % ", ".join(needs))
' 2>/dev/null
  elif command -v node >/dev/null 2>&1; then
    # shellcheck disable=SC2016
    node -e '
let s = ""; process.stdin.on("data", (d) => (s += d)).on("end", () => {
  let who; try { who = JSON.parse(s).result.structuredContent; } catch { return; }
  const tools = who.tools || [];
  console.log(`  Account level: ${who.level_name ?? who.level}`);
  console.log(`  Token scopes:  ${(who.effective_scopes || []).join(", ") || "none"}`);
  if (who.credential && who.credential.expires_at) console.log(`  Token expires: ${who.credential.expires_at.slice(0, 10)}`);
  console.log(`  Tools you can use: ${tools.filter((t) => t.status === "available").map((t) => t.name).join(", ") || "none"}`);
  const needs = tools.filter((t) => t.status === "needs_scope").map((t) => `${t.name} (needs ${t.required_scope})`);
  if (needs.length) console.log(`  Your level also allows these, with a token that has their scope: ${needs.join(", ")}`);
});' 2>/dev/null
  else
    { cat; echo; } | sed -n 's/.*"level_name": *"\([^"]*\)".*/  Account level: \1/p' | head -n 1
  fi
}

# The server's own message from an error body (a tool error inside a result, or a JSON-RPC error),
# without control characters, after ": "; nothing when there is none.
server_message() {
  m=$({ sed -n 's/.*\\"message\\": *\\"\([^\\]*\)\\".*/\1/p' "$1"; sed -n 's/.*"message": *"\([^"]*\)".*/\1/p' "$1"; } | head -n 1 | tr -d '\000-\037\177')
  [ -z "$m" ] || printf ': %s' "$m"
}

not_mcp() {
  warn "$URL answered with HTTP $1, which isn't how an AUniverse MCP server answers."
  warn "Check the URL: it should end in /mcp, like $DEFAULT_URL."
}

# 0: works. 1: the token or the account is the problem. 2: the server can't be used right now.
# 3: the URL isn't an AUniverse MCP server.
check_token() {
  say "Checking your token with $URL ..."
  BODY=$(mktemp) || die "Can't create a temporary file."
  ERRS=$(mktemp) || die "Can't create a temporary file."
  # -q (first) skips ~/.curlrc. The token reaches curl on stdin (-K -), so it never shows in the process list.
  status=$(printf 'header = "%s: %s %s"\n' "$AUTH_HEADER" "$AUTH_SCHEME" "$TOKEN" | curl -q -sS -o "$BODY" -w '%{http_code}' \
    --max-time 20 -X POST "$URL" \
    -K - \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json, text/event-stream' \
    -H 'MCP-Protocol-Version: 2025-06-18' \
    --data '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"auniverse_whoami","arguments":{}}}' 2>"$ERRS")
  curl_exit=$?

  if [ "$curl_exit" -ne 0 ]; then
    if [ -n "$status" ] && [ "$status" != 000 ]; then
      warn "$URL started to answer but didn't finish (curl exit $curl_exit). Try again."
      return 2
    fi
    why=$(sed -n 's/^curl: ([0-9]*) //p' "$ERRS" | head -n 1)
    warn "$URL didn't answer${why:+: $why}"
    case "$curl_exit" in
      35|51|58|59|60|77|80|83|90|91)
        warn "The secure connection failed. On a network that inspects traffic (some workplaces do), ask whoever runs it, or try another network." ;;
    esac
    if [ "$URL" = "$DEFAULT_URL" ]; then
      [ -z "$STATUS_NOTE" ] || warn "$STATUS_NOTE"
    else
      warn "Is the server running, and is the URL right?"
    fi
    return 2
  fi

  case "$status" in
    200)
      if grep -q '"user_id"' "$BODY" && ! grep -q '"isError": *true' "$BODY"; then
        say "✔ Your token works."
        summarise < "$BODY"
        return 0
      fi
      if grep -q '"jsonrpc"' "$BODY"; then
        warn "The server answered, but couldn't say who you are$(server_message "$BODY")"
        return 2
      fi
      not_mcp "200 but no JSON-RPC answer"
      return 3 ;;
    401)
      warn "The server refused the token$(server_message "$BODY")"
      if [ "$CUSTOM_URL" -eq 1 ]; then
        warn "It may be mistyped, expired or revoked, or made for a different server. Create a new one on the website of the server you're connecting to."
      else
        warn "It may be mistyped, expired or revoked, or your account may be suspended. Create a new one at $TOKEN_PAGE."
      fi
      return 1 ;;
    403)
      warn "The server refused the request$(server_message "$BODY")"
      return 1 ;;
    429)
      warn "The server asks you to wait$(server_message "$BODY")"
      return 2 ;;
    503)
      if grep -q 'MCP_DISABLED' "$BODY"; then
        warn "The AUniverse connector is switched off on this server right now."
      else
        warn "The server isn't available right now (HTTP 503). Try again later."
      fi
      if [ "$URL" = "$DEFAULT_URL" ] && [ -n "$STATUS_NOTE" ]; then warn "$STATUS_NOTE"; fi
      return 2 ;;
    5[0-9][0-9])
      warn "The server had a problem or couldn't be reached (HTTP $status). Try again later."
      if [ "$URL" = "$DEFAULT_URL" ] && [ -n "$STATUS_NOTE" ]; then warn "$STATUS_NOTE"; fi
      return 2 ;;
    *)
      not_mcp "$status"
      return 3 ;;
  esac
}

CHECKED=0
check_result=0
if [ "$DO_CHECK" -eq 1 ] || [ "$CHECK_ONLY" -eq 1 ]; then
  check_token
  check_result=$?
  CHECKED=1
fi
if [ "$CHECK_ONLY" -eq 1 ]; then
  if dotenv=$(codex_dotenv_value) && [ "$dotenv" != "$TOKEN" ]; then
    warn "Codex doesn't use this token: $CODEX_DOTENV sets \$$ENV_VAR to a different one, which wins over your shell's."
  fi
  exit "$check_result"
fi
case "$check_result" in
  1) die "Not setting anything up with a token the server refuses." ;;
  3) die "Not setting anything up with that URL." ;;
  2) warn "Setting up anyway: it will start working once the server answers." ;;
esac


# ---------- talking to the clients ----------

# Client commands run from an empty folder of their own, so a project's settings in the current
# folder don't change what they see or do.
NEUTRAL=$(mktemp -d) || die "Can't create a temporary folder."

# shellcheck disable=SC2317,SC2329 # called through quietly
in_neutral() { (cd "$NEUTRAL" && "$@"); }

# Runs a client command with its output hidden, feeding it QUIET_INPUT. When it fails, CMD_ERR
# holds the first line of its explanation (never a line with a token in it).
QUIET_INPUT=""
CMD_ERR=""
quietly() {
  CMD_ERR=$(printf '%s' "$QUIET_INPUT" | "$@" 2>&1 >/dev/null)
  quiet_status=$?
  QUIET_INPUT=""
  CMD_ERR=$(printf '%s\n' "$CMD_ERR" | tr -d '\000-\010\013-\037\177' | awk -v tp="$TOKEN_PREFIX" '
    index($0, tp) || /^WARNING:/ { next }
    /^Stack backtrace/ { exit }
    /^[ \t]*$/ { next }
    first == "" { first = $0; next }
    /^Caused by:/ { cause = 1; next }
    cause { sub(/^ *[0-9]+: */, ""); first = first " (" $0 ")"; exit }
    END { print first }')
  return "$quiet_status"
}
show_err() { [ -z "$CMD_ERR" ] || printf '    %s\n' "$CMD_ERR" >&2; }

# Claude Code and Codex pretty-print their --json answers, one key per line, and the readers
# below expect that. When an answer can't be read they say so ("?" or "unknown") instead of
# guessing, and the script then leaves things as they are.

# Where the marketplace named $PLUGIN_MARKETPLACE comes from (repo, path or url); nothing when
# there is none; "?" when Claude Code's answer can't be read.
marketplace_source() {
  list=$(in_neutral claude plugin marketplace list --json 2>/dev/null) || { echo '?'; return 0; }
  case "$list" in '['*) ;; *) echo '?'; return 0 ;; esac
  printf '%s\n' "$list" | grep -q "\"name\": *\"$PLUGIN_MARKETPLACE\"" || return 0
  src=$(printf '%s\n' "$list" | awk -v want="$PLUGIN_MARKETPLACE" '
    /^  \{/ { name = ""; src = "" }
    /^    "name": / { name = $0; sub(/^    "name": "/, "", name); sub(/",?$/, "", name) }
    /^    "(repo|path|url)": / { src = $0; sub(/^    "[a-z]+": "/, "", src); sub(/",?$/, "", src) }
    /^  \}/ { if (name == want) print src }' | head -n 1)
  printf '%s\n' "${src:-?}"
}

# Succeeds when marketplace source $1, as Claude Code lists it, is the one in $MARKETPLACE.
same_marketplace() {
  [ "$1" != "$MARKETPLACE" ] || return 0
  if [ -d "$MARKETPLACE" ]; then
    for p in "$(cd "$MARKETPLACE" && pwd)" "$(cd "$MARKETPLACE" && pwd -P)"; do
      [ "$1" != "$p" ] || return 0
    done
    return 1
  fi
  # GitHub: owner/repo, or its https URL; GitHub ignores case.
  a=$(printf '%s' "$1" | sed -e 's#^https://github\.com/##' -e 's#\.git$##' -e 's#/$##' | tr '[:upper:]' '[:lower:]')
  b=$(printf '%s' "$MARKETPLACE" | sed -e 's#^https://github\.com/##' -e 's#\.git$##' -e 's#/$##' | tr '[:upper:]' '[:lower:]')
  case "$a" in /*|.*|"") return 1 ;; esac
  [ "$a" = "$b" ]
}

# The plugin as `claude plugin list --json` shows it from folder $1: PLUGIN_STATE ("enabled",
# "disabled", "absent" or "unknown") and PLUGIN_URL, the URL its server connects to ("-" if unknown).
plugin_info() {
  PLUGIN_STATE=unknown
  PLUGIN_URL=-
  list=$( (cd "$1" && claude plugin list --json) 2>/dev/null) || return 0
  case "$list" in '['*) ;; *) return 0 ;; esac
  if ! printf '%s\n' "$list" | grep -qF "\"$PLUGIN_REF\""; then
    PLUGIN_STATE=absent
    return 0
  fi
  info=$(printf '%s\n' "$list" | awk -v want="$PLUGIN_REF" -v server="$SERVER_NAME" '
    function value(line) { sub(/^ *"[A-Za-z_]+": /, "", line); sub(/,$/, "", line); gsub(/"/, "", line); return line }
    /^  \{/ { id = ""; on = ""; url = ""; inserver = 0 }
    /^    "id": / { id = value($0) }
    /^    "enabled": / { on = value($0) }
    index($0, "      \"" server "\": {") == 1 { inserver = 1 }
    inserver && /^        "url": / { url = value($0) }
    /^      \}/ { inserver = 0 }
    /^  \}/ {
      if (id != want) next
      if (on == "true") state = "enabled"; else if (on == "false" && state != "enabled") state = "disabled"
      if (url != "") u = url
    }
    END { print (state == "" ? "unknown" : state), (u == "" ? "-" : u) }')
  PLUGIN_STATE=${info%% *}
  PLUGIN_URL=${info#* }
}

# "saved", "unsaved" or "unknown": whether the plugin has a token saved.
plugin_token_state() {
  out=$(in_neutral claude plugin configure "$PLUGIN_REF" --json 2>/dev/null) || { echo unknown; return 0; }
  flat=$(printf '%s' "$out" | tr -d ' \t\r\n')
  unset_keys=$(printf '%s' "$flat" | sed -n 's/.*"unconfigured":\[\([^]]*\)\].*/[\1]/p')
  set_keys=$(printf '%s' "$flat" | sed -n 's/.*[,{]"configured":\[\([^]]*\)\].*/[\1]/p')
  case "$unset_keys" in
    "") echo unknown ;;
    *'"token"'*) echo unsaved ;;
    *) case "$set_keys" in *'"token"'*) echo saved ;; *) echo unknown ;; esac ;;
  esac
}

# Succeeds when Claude Code reports that the server refuses the plugin's saved token.
plugin_token_refused() {
  in_neutral claude mcp get "plugin:${PLUGIN_REF%@*}:$SERVER_NAME" 2>/dev/null | grep -q 'HTTP 401'
}

# Servers added to Claude Code by hand (not by a plugin) for URL $1, as seen from folder $2,
# one name per line. Claude Code uses such an entry instead of a plugin's server for the same URL.
claude_entries_for_url() {
  (cd "$2" 2>/dev/null && claude mcp list 2>/dev/null) | awk -v url="$1" '
    { name = $1; sub(/:$/, "", name) }
    name !~ /^plugin:/ && ($2 == url || $2 == url "/") { print name }'
}

# The scope ("user", "local" or "project") in `claude mcp get` output on stdin; nothing when it
# can't be read.
scope_of() {
  awk '
    /^  Scope: User config/ { t = "user" }
    /^  Scope: Local config/ { t = "local" }
    /^  Scope: Project config/ { t = "project" }
    /claude mcp remove / {
      for (i = 1; i <= NF; i++) {
        if (($i == "-s" || $i == "--scope") && i < NF) { s = $(i + 1); break }
        if ($i ~ /^--scope=/) { s = substr($i, 9); break }
      }
    }
    END { if (s == "") s = t; if (s == "user" || s == "local" || s == "project") print s }'
}

# The scope of Claude Code entry $1, as seen from folder $2; nothing when it can't be read.
claude_entry_scope() {
  (cd "$2" 2>/dev/null && claude mcp get "$1" 2>/dev/null) | scope_of
}

# ---------- Claude Code ----------

# Finds servers added by hand for URL $1, in this folder and your home folder, that would hide the
# plugin's server. HIDING gets one "<folder> <scope> <name>" line for each one this script may
# remove; a project's shared .mcp.json is only reported.
HIDING=""
find_hiding_entries() {
  HIDING=""
  seen=" "
  last=""
  for dir in "$PWD" "$HOME"; do
    [ "$dir" != "$last" ] || continue
    last="$dir"
    for entry in $(claude_entries_for_url "$1" "$dir"); do
      scope=$(claude_entry_scope "$entry" "$dir")
      case "$scope" in
        project)
          warn "The project file $dir/.mcp.json adds '$entry' for this server. In that folder Claude Code uses it instead of the plugin: decline it there, or take it out of the file."
          continue ;;
        user)
          case "$seen" in *" $entry "*) continue ;; esac
          seen="$seen$entry " ;;
        local) ;;
        *)
          warn "'$entry', a server you added to Claude Code by hand for this URL, would hide the plugin's, and the script can't tell where it is saved."
          warn "Remove it yourself (claude mcp remove $entry, in $dir), then run this again."
          return 1 ;;
      esac
      HIDING="$HIDING$dir $scope $entry
"
    done
  done
  return 0
}

# Removes what find_hiding_entries found.
remove_hiding_entries() {
  removed_all=0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    entry=${line##* }
    rest=${line% *}
    scope=${rest##* }
    dir=${rest% *}
    if (cd "$dir" && claude mcp remove "$entry" -s "$scope" >/dev/null 2>&1); then
      say "Removed '$entry', which you had added by hand ($scope scope): it would have hidden the plugin's server."
    else
      warn "Couldn't remove '$entry', which you had added by hand and which hides the plugin's server. Remove it with: claude mcp remove $entry -s $scope (in $dir)"
      removed_all=1
    fi
  done <<EOF
$HIDING
EOF
  return "$removed_all"
}

setup_claude_plugin() {
  if ! claude plugin configure --help 2>/dev/null | grep -q -- '--values-stdin'; then
    warn "Setting up the plugin from this script needs Claude Code $MIN_CLAUDE or later. Run: claude update"
    warn "Or install it in Claude Code itself, as docs/claude-code.md describes."
    return 1
  fi

  # Look first, change nothing yet: a server added by hand for the same URL would hide the plugin.
  find_hiding_entries "$DEFAULT_URL" || return 1
  if [ -n "$HIDING" ] && [ "$REPLACE" -eq 0 ]; then
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      rest=${line% *}
      warn "You already added '${line##* }' to Claude Code by hand (${rest##* } scope) for this server, and it would hide the plugin's."
    done <<EOF
$HIDING
EOF
    warn "Keeping it: if it works, you don't need the plugin. Run again with --replace to switch to the plugin."
    return 1
  fi

  existing=$(marketplace_source)
  case "$existing" in
    "")
      quietly in_neutral claude plugin marketplace add "$MARKETPLACE" \
        || { warn "Couldn't add the plugin marketplace $MARKETPLACE."; show_err; return 1; } ;;
    '?')
      warn "Couldn't read Claude Code's list of plugin marketplaces (claude plugin marketplace list --json)."
      return 1 ;;
    *)
      if same_marketplace "$existing"; then
        quietly in_neutral claude plugin marketplace update "$PLUGIN_MARKETPLACE" \
          || warn "Couldn't update the plugin marketplace; using the copy you have."
      elif [ "$REPLACE" -eq 1 ]; then
        # Adding it again under the same name points it at the new source, and leaves it as it was if that fails.
        quietly in_neutral claude plugin marketplace add "$MARKETPLACE" \
          || { warn "Couldn't switch the '$PLUGIN_MARKETPLACE' marketplace to $MARKETPLACE; it still comes from $existing."; show_err; return 1; }
        say "Switched the '$PLUGIN_MARKETPLACE' plugin marketplace to $MARKETPLACE."
      else
        warn "Your '$PLUGIN_MARKETPLACE' plugin marketplace comes from $existing, not $MARKETPLACE."
        warn "Keeping it. Run again with --replace to switch it."
        return 1
      fi ;;
  esac

  plugin_info "$NEUTRAL"
  installed=0
  case "$PLUGIN_STATE" in
    absent)
      quietly in_neutral claude plugin install "$PLUGIN_REF" --scope user \
        || { warn "Couldn't install $PLUGIN_REF."; show_err; return 1; }
      installed=1 ;;
    disabled)
      quietly in_neutral claude plugin update "$PLUGIN_REF" --scope user || true
      quietly in_neutral claude plugin enable "$PLUGIN_REF" --scope user \
        || { warn "$PLUGIN_REF is installed but switched off, and couldn't be switched on. Run /plugin in Claude Code to enable it."; show_err; return 1; } ;;
    enabled)
      quietly in_neutral claude plugin update "$PLUGIN_REF" --scope user || true ;;
    *)
      warn "Couldn't read Claude Code's list of plugins (claude plugin list --json)."
      return 1 ;;
  esac

  # The token goes only to a plugin that connects to the server it was just checked with.
  plugin_info "$NEUTRAL"
  if [ "$PLUGIN_URL" != "$DEFAULT_URL" ] && [ "$REPLACE" -eq 1 ] && [ "$installed" -eq 0 ]; then
    if quietly in_neutral claude plugin uninstall "$PLUGIN_REF" --scope user \
      && quietly in_neutral claude plugin install "$PLUGIN_REF" --scope user; then
      say "Installed $PLUGIN_REF again from $MARKETPLACE: the copy you had connected to $PLUGIN_URL."
      installed=1
      plugin_info "$NEUTRAL"
    else
      warn "Couldn't install $PLUGIN_REF again."
      show_err
      return 1
    fi
  fi
  if [ "$PLUGIN_STATE" != enabled ]; then
    warn "$PLUGIN_REF didn't end up installed and switched on. Run /plugin in Claude Code to check it."
    return 1
  fi
  if [ "$PLUGIN_URL" != "$DEFAULT_URL" ]; then
    if [ "$PLUGIN_URL" = - ]; then
      warn "Couldn't read which server the installed $PLUGIN_REF plugin connects to, so your token wasn't saved in it."
    else
      warn "The installed $PLUGIN_REF plugin connects to $PLUGIN_URL, not $DEFAULT_URL, so your token wasn't saved in it."
      warn "Run again with --replace to install it again from $MARKETPLACE."
    fi
    return 1
  fi

  save=1
  case "$(plugin_token_state)" in
    saved)
      if [ "$REPLACE" -eq 1 ]; then
        if [ "$CHECKED" -eq 1 ] && [ "$check_result" -ne 0 ]; then
          warn "Kept the token the plugin already has: the server couldn't confirm the new one works. Run again once it answers."
          return 1
        fi
      elif plugin_token_refused; then
        if [ "$CHECKED" -eq 1 ] && [ "$check_result" -eq 0 ]; then
          say "The server refuses the token saved in the plugin, so it will use the one you just checked instead."
        else
          warn "The server refuses the token saved in the plugin. Run again with --replace to save this one instead."
          return 1
        fi
      else
        save=0
      fi ;;
    unknown)
      if [ "$REPLACE" -eq 0 ]; then
        warn "Couldn't tell whether the $PLUGIN_REF plugin already has a token saved. Run again with --replace to save this one."
        return 1
      fi ;;
  esac
  if [ "$save" -eq 1 ]; then
    QUIET_INPUT=$(printf '{"token":"%s"}' "$TOKEN")
    quietly in_neutral claude plugin configure "$PLUGIN_REF" --values-stdin \
      || { warn "Couldn't save the token in the plugin. In Claude Code, run /plugin and configure $PLUGIN_REF."; show_err; return 1; }
  fi

  remove_hiding_entries || return 1

  if [ "$installed" -eq 1 ]; then
    say "✔ Installed the $PLUGIN_REF plugin and saved your token with Claude Code's credentials."
  elif [ "$save" -eq 1 ]; then
    say "✔ The $PLUGIN_REF plugin is installed; saved your token with Claude Code's credentials."
  else
    say "✔ The $PLUGIN_REF plugin is installed and already has a token saved; kept it (use --replace to save this one instead)."
  fi
  plugin_info "$PWD"
  if [ "$PLUGIN_STATE" = disabled ]; then
    warn "This folder's project settings switch the plugin off, so Claude Code doesn't use it here."
  fi
  say "  Restart Claude Code, run /mcp, and ask: \"Who am I on AUniverse?\""
  return 0
}

setup_claude_manual() {
  # Single quotes on purpose: Claude Code stores ${VAR} and fills in the token when it connects.
  # shellcheck disable=SC2016
  header=$(printf '%s: %s ${%s}' "$AUTH_HEADER" "$AUTH_SCHEME" "$ENV_VAR")

  # Look first, change nothing yet. Seen from an empty folder, only entries for your user show.
  remove_plugin=0
  if [ "$URL" = "$DEFAULT_URL" ]; then
    plugin_info "$NEUTRAL"
    if [ "$PLUGIN_STATE" != absent ]; then
      if [ "$REPLACE" -eq 0 ]; then
        warn "The $PLUGIN_REF plugin is installed, and a server added by hand for the same URL would hide it."
        warn "Keeping the plugin. Run again without --manual to use it, or with --replace to uninstall it and add the server by hand."
        return 1
      fi
      remove_plugin=1
    fi
  fi

  others=""
  for entry in $(claude_entries_for_url "$URL" "$NEUTRAL"); do
    [ "$entry" = "$NAME" ] || others="$others $entry"
  done
  if [ -n "$others" ] && [ "$REPLACE" -eq 0 ]; then
    for entry in $others; do
      warn "Claude Code already has this server for your user, as '$entry'."
    done
    warn "Nothing to add: use that one. Run again with --replace to set it up as '$NAME' instead."
    return 1
  fi

  removed_old=0
  if current=$(in_neutral claude mcp get "$NAME" 2>/dev/null); then
    scope=$(printf '%s\n' "$current" | scope_of)
    if [ "$REPLACE" -eq 0 ]; then
      if [ "$scope" = user ] && printf '%s\n' "$current" | grep -qxF "  Type: http" \
        && printf '%s\n' "$current" | grep -qxF "  URL: $URL" && printf '%s\n' "$current" | grep -qxF "    $header"; then
        say "✔ Claude Code already has '$NAME' set up this way for your user; nothing to change."
        manual_followup
        return
      fi
      if printf '%s\n' "$current" | grep -qxF "  URL: $URL"; then
        warn "Claude Code already has a server called '$NAME' (${scope:-unknown} scope) for $URL, set up differently. If it doesn't read the token from \$$ENV_VAR, it may hold the token itself, in ~/.claude.json."
      else
        warn "Claude Code already has a server called '$NAME' (${scope:-unknown} scope), set up differently:"
      fi
      printf '%s\n' "$current" | grep -E '^  (Type|URL|Command):' >&2
      warn "Keeping it. Run again with --replace to set it up again."
      return 1
    fi
    if [ "$scope" != user ]; then
      warn "Couldn't tell where the existing '$NAME' is saved. Remove it yourself (claude mcp remove $NAME), then run this again."
      return 1
    fi
    quietly in_neutral claude mcp remove "$NAME" -s user \
      || { warn "Couldn't remove the existing '$NAME' entry."; show_err; return 1; }
    removed_old=1
  fi

  if ! quietly in_neutral claude mcp add --transport http --scope user "$NAME" "$URL" --header "$header"; then
    warn "claude mcp add failed."
    show_err
    if [ "$removed_old" -eq 1 ]; then
      warn "The old '$NAME' entry was removed. To add the server yourself:"
      warn "claude mcp add --transport http --scope user $NAME $URL --header '$header'"
    fi
    return 1
  fi
  say "✔ Added '$NAME' to Claude Code for your user. It reads the token from \$$ENV_VAR each time it connects."

  # Only now that the new entry is in place, take out what it replaces.
  failed_cleanup=0
  for entry in $others; do
    if quietly in_neutral claude mcp remove "$entry" -s user; then
      say "Removed '$entry', which pointed at the same server."
    else
      warn "Couldn't remove '$entry', which points at the same server: claude mcp remove $entry -s user"
      failed_cleanup=1
    fi
  done
  if [ "$remove_plugin" -eq 1 ]; then
    if quietly in_neutral claude plugin uninstall "$PLUGIN_REF" --scope user; then
      say "Uninstalled the $PLUGIN_REF plugin."
    else
      warn "Couldn't uninstall the $PLUGIN_REF plugin, which this entry now hides: run /plugin in Claude Code to remove it."
      show_err
      failed_cleanup=1
    fi
  fi
  manual_followup || failed_cleanup=1
  say "  Then restart Claude Code, run /mcp, and ask: \"Who am I on AUniverse?\""
  return "$failed_cleanup"
}

# What the hand-added entry still depends on.
manual_followup() {
  if [ "$PWD" != "$HOME" ] && [ "$(claude_entry_scope "$NAME" "$PWD")" != user ]; then
    warn "In this folder, another '$NAME' entry (local or project scope) is used instead."
  fi
  remind_env
}

setup_claude() {
  command -v claude >/dev/null 2>&1 || { warn "Claude Code (claude) isn't installed or isn't on your PATH; skipping it."; return 1; }
  say ""
  say "Claude Code"
  if [ "$MANUAL" -eq 1 ]; then setup_claude_manual; else setup_claude_plugin; fi
}

# ---------- Codex ----------

# "<enabled> <transport type> <url> <bearer_token_env_var> <headers>" from `codex mcp get --json`
# on stdin ("-" for each one missing; <headers> is "headers" when the entry sends its own);
# nothing when it can't be read.
codex_entry() {
  awk '
    function value(line) { sub(/^ *"[a-z_]+": /, "", line); sub(/,$/, "", line); gsub(/"/, "", line); return line }
    /^  "enabled": / { enabled = value($0) }
    /^  "transport": / { seen = 1 }
    /^    "type": / { type = value($0) }
    /^    "url": / { url = value($0) }
    /^    "bearer_token_env_var": / { var = value($0) }
    /^    "(http_headers|env_http_headers|http_headers_helper)": / { if (value($0) != "null") headers = "headers" }
    END {
      if (!seen || (enabled != "true" && enabled != "false")) exit
      if (type == "" || type == "null") type = "-"
      if (url == "" || url == "null") url = "-"
      if (var == "" || var == "null") var = "-"
      print enabled, type, url, var, (headers == "" ? "-" : headers)
    }'
}

setup_codex() {
  command -v codex >/dev/null 2>&1 || { warn "Codex (codex) isn't installed or isn't on your PATH; skipping it."; return 1; }
  say ""
  say "Codex"
  want="true streamable_http $URL $ENV_VAR -"
  if json=$(in_neutral codex mcp get "$NAME" --json 2>/dev/null); then
    current=$(printf '%s\n' "$json" | codex_entry)
    if [ "$REPLACE" -eq 0 ]; then
      if [ "$current" = "$want" ]; then
        say "✔ Codex already has '$NAME' set up this way; nothing to change."
        codex_followup
        return
      fi
      if [ -z "$current" ]; then
        warn "Codex already has a server called '$NAME', and the script can't read how it is set up."
      else
        # shellcheck disable=SC2086
        set -- $current
        if [ "$2" != streamable_http ]; then
          warn "Codex already has a server called '$NAME', saved as a program to run instead of a URL, so it can't connect."
        elif [ "$3" != "$URL" ]; then
          warn "Codex already has a server called '$NAME', pointing at $3."
        elif [ "$4" = - ] && [ "$5" = headers ]; then
          warn "Codex already has a server called '$NAME' that sends headers of its own instead of reading the token from \$$ENV_VAR."
        elif [ "$4" = - ]; then
          warn "Codex already has a server called '$NAME' with no token setting (one imported from the Claude Code plugin, for example), so it can't sign in."
        elif [ "$4" != "$ENV_VAR" ]; then
          warn "Codex already has a server called '$NAME', reading the token from \$$4."
        elif [ "$1" != true ]; then
          warn "Codex already has '$NAME' set up this way, but switched off (enabled = false in its config.toml)."
        else
          warn "Codex already has a server called '$NAME', set up differently."
        fi
      fi
      warn "Keeping it. Run again with --replace to set it up again."
      return 1
    fi
    # One that comes from a Codex plugin isn't in config.toml, so this can fail; the new entry takes its place anyway.
    quietly in_neutral codex mcp remove "$NAME" || true
  fi
  quietly in_neutral codex mcp add "$NAME" --url "$URL" --bearer-token-env-var "$ENV_VAR" \
    || { warn "codex mcp add failed."; show_err; return 1; }
  say "✔ Added '$NAME' to Codex. It reads the token from \$$ENV_VAR when it starts."
  codex_followup || return 1
  say "  Then start Codex, run /mcp, and ask: \"Who am I on AUniverse?\""
  return 0
}

# What the Codex entry still depends on. Fails when something stops it working as set up.
codex_followup() {
  ok=0
  now=$(codex mcp get "$NAME" --json 2>/dev/null | codex_entry)
  if [ "$now" != "true streamable_http $URL $ENV_VAR -" ]; then
    warn "In this folder, a project's .codex/config.toml sets up '$NAME' differently, and Codex uses that one here."
  fi
  if dotenv=$(codex_dotenv_value); then
    if [ "$dotenv" != "$TOKEN" ]; then
      warn "$CODEX_DOTENV sets \$$ENV_VAR to a different token, and Codex uses that one instead of the one in your shell."
      warn "Put this token there too (or delete that line)."
      ok=1
    fi
  else
    remind_env
  fi
  if [ "$TOKEN_DIRTY" -eq 1 ]; then
    warn "Codex can't send \$$ENV_VAR as it is now: take out the space or line break around the token (see above)."
    ok=1
  fi
  remind_codex_daemon
  return "$ok"
}

# Codex runs MCP servers in a background server, which keeps the environment it started with.
remind_codex_daemon() {
  codex app-server daemon version 2>/dev/null | grep -q '"running"' || return 0
  say "  Codex's background server is already running, with the environment it started with. From a"
  say "  terminal that has \$$ENV_VAR, run: codex app-server daemon restart"
}

# The clients read the token from the environment, so it has to be there in every new terminal.
REMINDED=0
remind_env() {
  [ "$REMINDED" -eq 0 ] || return 0
  REMINDED=1
  for profile in "$HOME/.zshrc" "$HOME/.zprofile" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
    if [ -f "$profile" ] && grep -q "$ENV_VAR=" "$profile" 2>/dev/null; then
      return 0
    fi
  done
  if [ "$TOKEN_FROM_ENV" -eq 1 ]; then
    say "  \$$ENV_VAR is set in this terminal, but not in your shell profile, so new terminals won't have it."
  fi
  say "  Add this line to your shell profile (~/.zshrc on a Mac, ~/.bashrc on most Linux), with your token:"
  say "    export $ENV_VAR=\"$TOKEN_PREFIX...\""
  say "  then open a new terminal. Keep that file to yourself: don't publish it (in a dotfiles repository,"
  say "  say), and on a computer you share with others, make it private: chmod 600 ~/.zshrc (or ~/.bashrc)"
}

failed=0
for client in $CLIENTS; do
  case "$client" in
    claude) setup_claude || failed=1 ;;
    codex) setup_codex || failed=1 ;;
  esac
done
exit "$failed"
