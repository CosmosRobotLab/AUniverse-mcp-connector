// Tests for the generator: node --test scripts/sync.test.mjs
//
// They use the small fixed connector and catalogue below, so routine server changes (a renamed
// tool, going live, a new plugin name) don't break them. One test runs on the real files.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { deploymentProblems, describeChanges, generate, normaliseCatalog, staleProse } from './sync.mjs';
import { claudeAddCommand, claudeCode, codex, codexAddCommand } from './clients.mjs';

const connector = {
  version: '1.2.0',
  server: {
    name: 'campus',
    title: 'Campus',
    description: 'Campus events',
    status: 'early-access',
    status_note: "It isn't switched on yet.",
    transport: 'http',
    url: 'https://mcp.example.edu/mcp',
    site: 'https://example.edu',
    docs: 'https://example.edu/developers/mcp',
    catalog: 'https://example.edu/api/mcp/catalog',
    token_page: 'https://example.edu/tokens',
  },
  auth: { header: 'Authorization', scheme: 'Bearer', token_prefix: 'tok_', token_pattern: '^tok_[A-Za-z0-9]{8}$', env_var: 'CAMPUS_TOKEN' },
  plugin: { marketplace: 'campus-market', name: 'campus-plugin', repo: 'example/campus-connector' },
};

const readOnly = { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false };
const tool = (name, toolset, extra = {}) => ({
  name,
  title: `The ${name} tool`,
  description: `What ${name} does.`,
  toolset,
  action: `${toolset}.read`,
  required_scope: toolset === 'platform' ? null : 'events:read',
  min_level: 'user',
  annotations: readOnly,
  input_schema: { type: 'object', properties: { q: { type: 'string', description: 'Words to look for' } } },
  output_schema: { type: 'object' },
  ...extra,
});

const snapshot = {
  _snapshot: { synced_on: '2026-01-01', from: 'the tests' },
  server: {
    name: 'campus',
    version: '0.3.0',
    mcp_url: 'https://mcp.example.edu/mcp',
    docs_url: 'https://example.edu/developers/mcp',
    transport: 'streamable-http (stateless, JSON responses)',
    auth: 'Bearer personal access token (tok_…)',
    instructions: 'Campus events. Links look like https://example.edu/events/<id>.',
  },
  scopes: [{ scope: 'events:read', description: 'Read events', min_level: 'user' }],
  toolsets: [
    { key: 'platform', title: 'Platform', description: 'About you.', enabled: true, docs_url: 'https://example.edu/developers/mcp', tools: ['whoami'] },
    { key: 'events', title: 'Events', description: 'Find events.', enabled: true, docs_url: null, tools: ['event_search', 'event_get'] },
  ],
  tools: [tool('whoami', 'platform', { input_schema: { type: 'object', properties: {} } }), tool('event_search', 'events'), tool('event_get', 'events')],
  resources: [{ uri: 'campus://help', title: 'Help', description: 'How to use it', mime_type: 'text/markdown' }],
  prompts: [{ name: 'whats_on', title: "What's on", description: 'Events this week' }],
};

/** The snapshot as a local development server would serve it. */
function localCatalog(catalog = snapshot, conn = connector) {
  const copy = structuredClone(catalog);
  delete copy._snapshot;
  const swap = (text) => text.split(conn.server.docs).join('http://localhost:5173/developers/mcp').split(conn.server.site).join('http://localhost:5173');
  copy.server.mcp_url = 'http://localhost:8123/mcp';
  copy.server.docs_url = 'http://localhost:5173/developers/mcp';
  copy.server.instructions = swap(copy.server.instructions);
  copy.server.enabled = true;
  copy.toolsets = copy.toolsets.map((t) => ({ ...t, docs_url: t.docs_url && swap(t.docs_url) }));
  return copy;
}

const writer = (name = 'event_create') => tool(name, 'events', { annotations: { readOnlyHint: false, destructiveHint: false } });

test('the real connector.json and snapshot generate, and a local copy of the snapshot normalises back to it', () => {
  const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
  const realConnector = JSON.parse(readFileSync(join(ROOT, 'connector.json'), 'utf8'));
  const realSnapshot = JSON.parse(readFileSync(join(ROOT, 'catalog/auniverse-catalog.json'), 'utf8'));
  const { files } = generate(realConnector, realSnapshot, [claudeCode, codex]);
  assert.ok(files.size > 0);
  const normalised = normaliseCatalog(localCatalog(realSnapshot, realConnector), realConnector, 'http://localhost:8123/api/mcp/catalog');
  assert.deepEqual(describeChanges(realSnapshot, normalised), []);
});

test('a local catalogue normalises to the production snapshot', () => {
  const normalised = normaliseCatalog(localCatalog(), connector, 'http://localhost:8123/api/mcp/catalog');
  assert.equal(normalised._snapshot.from, 'a local development server');
  assert.equal(normalised.server.mcp_url, connector.server.url);
  assert.equal('enabled' in normalised.server, false);
  assert.deepEqual(describeChanges(snapshot, normalised), []);
  assert.doesNotMatch(JSON.stringify(normalised), /localhost/);
});

test('a catalogue that is not one is refused', () => {
  assert.throws(() => normaliseCatalog({ hello: 'world' }, connector, 'x.json'), /isn't an AUniverse MCP catalogue/);
});

test('changes are described tool by tool', () => {
  const after = structuredClone(snapshot);
  after.tools = after.tools.filter((t) => t.name !== 'event_get');
  after.tools.push(tool('event_list', 'events'));
  after.tools[1].input_schema = { ...after.tools[1].input_schema, required: ['q'] };
  after.scopes[0].min_level = 'moderator';
  const lines = describeChanges(snapshot, after);
  assert.ok(lines.includes('new tool: event_list'));
  assert.ok(lines.includes('tool removed: event_get'));
  assert.ok(lines.includes('tool event_search: input_schema changed'));
  assert.ok(lines.includes('scope events:read: min_level changed'));
});

test('a new order counts as a change, since the docs follow it', () => {
  const after = structuredClone(snapshot);
  after.tools.reverse();
  after.toolsets.reverse();
  assert.deepEqual(describeChanges(snapshot, after), ['toolsets reordered', 'tools reordered']);
});

test('tools that write are marked in the list of changes', () => {
  const after = structuredClone(snapshot);
  after.tools.push(writer());
  after.tools[1].annotations = { ...readOnly, readOnlyHint: false };
  const lines = describeChanges(snapshot, after);
  assert.ok(lines.includes('new tool: event_create (writes)'));
  assert.ok(lines.includes('tool event_search: annotations changed (now writes)'));
});

test('the Claude Code command keeps the token out of the config file', () => {
  const command = claudeAddCommand(connector);
  assert.equal(command, "claude mcp add --transport http --scope user campus https://mcp.example.edu/mcp --header 'Authorization: Bearer ${CAMPUS_TOKEN}'");
  // --header takes several values, so it must come after the name and URL.
  assert.ok(command.indexOf('--header') > command.indexOf(connector.server.url));
});

test('the Codex command always passes --url', () => {
  assert.equal(codexAddCommand(connector), 'codex mcp add campus --url https://mcp.example.edu/mcp --bearer-token-env-var CAMPUS_TOKEN');
});

test('the plugin keeps the token in user config and points at the server', () => {
  const { files } = generate(connector, snapshot, [claudeCode, codex]);
  const plugin = JSON.parse(files.get('plugins/campus-plugin/.claude-plugin/plugin.json'));
  assert.equal(plugin.name, 'campus-plugin');
  assert.equal(plugin.version, connector.version);
  assert.equal(plugin.userConfig.token.sensitive, true);
  assert.deepEqual(plugin.mcpServers.campus, {
    type: 'http',
    url: connector.server.url,
    headers: { Authorization: 'Bearer ${user_config.token}' },
  });
  const market = JSON.parse(files.get('.claude-plugin/marketplace.json'));
  assert.equal(market.name, 'campus-market');
});

test('permission allowlists only name read-only tools', () => {
  const withWriter = structuredClone(snapshot);
  withWriter.tools.push(writer());
  const { blocks } = generate(connector, withWriter, [claudeCode, codex]);
  const allow = blocks.get('docs/claude-code.md').get('permissions-manual');
  assert.match(allow, /mcp__campus__event_search/);
  assert.doesNotMatch(allow, /event_create/);
});

test('shell constants survive quotes, and go quiet once live', () => {
  const tricky = structuredClone(connector);
  tricky.server.status_note = "It isn't on yet; don't panic.";
  const constants = generate(tricky, snapshot, []).blocks.get('scripts/connect.sh').get('constants');
  assert.match(constants, /^STATUS_NOTE='It isn'\\''t on yet; don'\\''t panic\.'$/m);
  assert.match(constants, /^PLUGIN_REF='campus-plugin@campus-market'$/m);

  const live = structuredClone(connector);
  live.server.status = 'live';
  assert.match(generate(live, snapshot, []).blocks.get('scripts/connect.sh').get('constants'), /^STATUS_NOTE=''$/m);
});

test('catalogue text that could break the generated blocks is refused', () => {
  const marker = localCatalog();
  marker.tools[0].title = 'Who am I <!-- /generated:tools -->';
  assert.throws(() => normaliseCatalog(marker, connector, 'x.json'), /contains "<!--"/);

  const star = localCatalog();
  star.tools[1].name = '*';
  assert.throws(() => normaliseCatalog(star, connector, 'x.json'), /unusual name/);

  const empty = localCatalog();
  empty.tools = [];
  assert.throws(() => normaliseCatalog(empty, connector, 'x.json'), /lists no tools/);

  const noSchema = localCatalog();
  noSchema.tools[0].input_schema = null;
  assert.throws(() => normaliseCatalog(noSchema, connector, 'x.json'), /has no input_schema/);
});

test('a deployment URL that survives the rewriting is refused, wherever it is', () => {
  // The docs live elsewhere, so the staging site in the instructions can't be rewritten.
  const staging = localCatalog();
  staging.server.mcp_url = 'https://staging-mcp.example.edu/mcp';
  staging.server.docs_url = 'https://docs.staging.example/mcp';
  staging.server.instructions = 'Links look like https://staging.example.edu/events/<id>.';
  for (const source of ['saved.json', 'https://staging-api.example.edu/api/mcp/catalog', 'https://staging.example.edu/api/mcp/catalog']) {
    assert.throws(() => normaliseCatalog(staging, connector, source), /still mentions https:\/\/staging\.example\.edu \(in catalogue\.server\.instructions\)/);
  }

  const local = localCatalog();
  local.tools[1].description = 'Images come from http://localhost:9000/media.';
  assert.throws(() => normaliseCatalog(local, connector, 'saved.json'), /still mentions http:\/\/localhost:9000/);

  // Links to other sites are fine.
  const outside = localCatalog();
  outside.tools[1].description = 'Places come from https://www.openstreetmap.org.';
  assert.doesNotThrow(() => normaliseCatalog(outside, connector, 'http://localhost:8123/api/mcp/catalog'));
});

test("production's catalogue is checked against connector.json", () => {
  const prod = structuredClone(snapshot);
  const from = connector.server.catalog;
  prod.server.enabled = false;
  prod.server.mcp_url = null;
  assert.deepEqual(deploymentProblems(prod, connector, from), []);

  prod.server.enabled = true;
  prod.server.mcp_url = connector.server.url;
  assert.match(deploymentProblems(prod, connector, from).join(), /switched on, but connector.json's server.status is "early-access"/);

  const live = structuredClone(connector);
  live.server.status = 'live';
  assert.deepEqual(deploymentProblems(prod, live, from), []);
  prod.server.mcp_url = 'https://ai.example.edu/mcp';
  assert.match(deploymentProblems(prod, live, from).join(), /serves the connector at https:\/\/ai.example.edu\/mcp/);

  // Other deployments say nothing about production.
  assert.deepEqual(deploymentProblems(prod, connector, 'http://localhost:8000/api/mcp/catalog'), []);
  assert.deepEqual(deploymentProblems(prod, connector, 'saved.json'), []);
});

test('stale promises in the prose are caught, outside the generated blocks only', () => {
  const texts = new Map([
    ['README.md', 'Today every tool only reads.\n<!-- generated:status -->\nbefore launch\n<!-- /generated:status -->\n'],
    ['docs/codex.md', 'Before launch, that is expected.'],
  ]);
  assert.deepEqual(staleProse(connector, snapshot, texts), []);

  const withWriter = structuredClone(snapshot);
  withWriter.tools.push(writer());
  assert.match(staleProse(connector, withWriter, texts).join(), /event_create can change things, but README.md still say/);

  const live = structuredClone(connector);
  live.server.status = 'live';
  assert.match(staleProse(live, snapshot, texts).join(), /live, but docs\/codex.md still talk/);
});

test('the docs name the tools and prompts the way each client shows them', () => {
  const { blocks } = generate(connector, snapshot, [claudeCode, codex]);
  assert.match(blocks.get('docs/codex.md').get('tool-names'), /`campus\.whoami`/);
  assert.match(blocks.get('docs/claude-code.md').get('prompts'), /\*\*whats_on\*\*/);
});
