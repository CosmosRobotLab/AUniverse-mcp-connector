// Client setups generated from connector.json and the catalogue snapshot: Claude Code and Codex.
// Each function receives (connector, catalog, out) and declares its outputs with
// out.file(path, content) for whole files and out.block(path, name, content) for marked
// blocks inside hand-written Markdown or shell files.

const json = (value) => `${JSON.stringify(value, null, 2)}\n`;

const fence = (lang, body) => `\`\`\`${lang}\n${body.replace(/\n+$/, '')}\n\`\`\``;

function readOnlyTools(catalog) {
  return catalog.tools.filter((t) => t.annotations && t.annotations.readOnlyHint).map((t) => t.name);
}

// ---------- Claude Code ----------

export function claudeCodeNames(connector) {
  const { name } = connector.server;
  const plugin = connector.plugin.name;
  return {
    manualPrefix: `mcp__${name}__`,
    pluginPrefix: `mcp__plugin_${plugin}_${name}__`,
    pluginRef: `${plugin}@${connector.plugin.marketplace}`,
  };
}

/** The `claude mcp add` command. The single quotes keep ${VAR} for Claude Code to expand when it connects. */
export function claudeAddCommand(connector, { url = connector.server.url, name = connector.server.name, quote = "'" } = {}) {
  const header = `${connector.auth.header}: ${connector.auth.scheme} \${${connector.auth.env_var}}`;
  return `claude mcp add --transport http --scope user ${name} ${url} --header ${quote}${header}${quote}`;
}

export function claudeCode(connector, catalog, out) {
  const { server, auth, plugin } = connector;
  const names = claudeCodeNames(connector);
  const repoUrl = `https://github.com/${plugin.repo}`;
  const bearer = `${auth.scheme} \${${auth.env_var}}`;

  out.file(
    '.claude-plugin/marketplace.json',
    json({
      name: plugin.marketplace,
      owner: { name: plugin.repo.split('/')[0] },
      metadata: { description: `Connect Claude Code to ${server.title}` },
      plugins: [
        {
          name: plugin.name,
          source: `./plugins/${plugin.name}`,
          description: `${server.description}: the ${server.title} MCP server, signed in with your personal access token`,
        },
      ],
    }),
  );

  out.file(
    `plugins/${plugin.name}/.claude-plugin/plugin.json`,
    json({
      name: plugin.name,
      version: connector.version,
      description: `${server.description}. Connects Claude Code to the ${server.title} MCP server as you.`,
      author: { name: plugin.repo.split('/')[0] },
      homepage: repoUrl,
      repository: repoUrl,
      keywords: ['mcp', 'auniverse', 'adelaide-university', 'events'],
      userConfig: {
        token: {
          type: 'string',
          title: `${server.title} personal access token`,
          description: `Create one at ${server.token_page} (Profile → MCP). It starts with ${auth.token_prefix}`,
          sensitive: true,
          required: true,
        },
      },
      mcpServers: {
        [server.name]: {
          type: 'http',
          url: server.url,
          headers: { [auth.header]: `${auth.scheme} \${user_config.token}` },
        },
      },
    }),
  );

  const projectConfig = json({
    mcpServers: { [server.name]: { type: 'http', url: server.url, headers: { [auth.header]: bearer } } },
  });
  out.file('templates/claude-code/mcp.json', projectConfig);

  const pluginSteps = [
    `claude plugin marketplace add ${plugin.repo}`,
    `claude plugin install ${names.pluginRef}`,
  ].join('\n');
  const manualSteps = [`export ${auth.env_var}="${auth.token_prefix}..."`, claudeAddCommand(connector)].join('\n');

  out.block('README.md', 'claude-code-plugin', fence('bash', pluginSteps));
  out.block('README.md', 'claude-code-manual', fence('bash', manualSteps));
  out.block('docs/claude-code.md', 'plugin', fence('bash', pluginSteps));
  out.block(
    'docs/claude-code.md',
    'plugin-update',
    fence('bash', [`claude plugin marketplace update ${plugin.marketplace}`, `claude plugin update ${names.pluginRef}`].join('\n')),
  );
  out.block(
    'docs/claude-code.md',
    'plugin-configure-stdin',
    fence('bash', `printf '{"token":"%s"}' "$${auth.env_var}" | claude plugin configure ${names.pluginRef} --values-stdin`),
  );
  out.block('docs/claude-code.md', 'manual', fence('bash', manualSteps));
  out.block(
    'docs/claude-code.md',
    'manual-powershell',
    fence(
      'powershell',
      [
        `[Environment]::SetEnvironmentVariable('${auth.env_var}', '${auth.token_prefix}...', 'User')`,
        `$env:${auth.env_var} = '${auth.token_prefix}...'`,
        claudeAddCommand(connector),
      ].join('\n'),
    ),
  );
  out.block(
    'docs/claude-code.md',
    'manual-cmd',
    fence('bat', [`setx ${auth.env_var} ${auth.token_prefix}...`, claudeAddCommand(connector, { quote: '"' })].join('\n')),
  );
  out.block('docs/claude-code.md', 'project', fence('json', projectConfig));
  out.block(
    'docs/claude-code.md',
    'remove',
    fence('bash', [`claude plugin uninstall ${names.pluginRef}`, `claude mcp remove ${server.name} --scope user`].join('\n')),
  );

  const tools = readOnlyTools(catalog);
  const allow = (prefix) => json({ permissions: { allow: tools.map((t) => `${prefix}${t}`) } });
  out.block('docs/claude-code.md', 'permissions-plugin', fence('json', allow(names.pluginPrefix)));
  out.block('docs/claude-code.md', 'permissions-manual', fence('json', allow(names.manualPrefix)));
  out.block('docs/claude-code.md', 'tool-names', [
    `- Plugin: \`${names.pluginPrefix}<tool>\`, for example \`${names.pluginPrefix}${catalog.tools[0].name}\``,
    `- Added by hand: \`${names.manualPrefix}<tool>\`, for example \`${names.manualPrefix}${catalog.tools[0].name}\``,
  ].join('\n'));
  const prompts = catalog.prompts.map((p) => `**${p.name}**`);
  out.block(
    'docs/claude-code.md',
    'prompts',
    prompts.length
      ? `The server's ${prompts.length === 1 ? 'prompt appears as a slash command' : 'prompts appear as slash commands'}: type \`/\` and look for ${prompts.join(', ')}.`
      : "The server doesn't offer any prompts at the moment.",
  );
}

// ---------- Codex ----------

const tomlString = (value) => JSON.stringify(String(value));

/** `codex mcp add`: always with --url (without it the URL is saved as a command to run). */
export function codexAddCommand(connector, { url = connector.server.url, name = connector.server.name, envVar = connector.auth.env_var } = {}) {
  return `codex mcp add ${name} --url ${url} --bearer-token-env-var ${envVar}`;
}

export function codexConfig(connector) {
  const { server, auth } = connector;
  return [
    `[mcp_servers.${server.name}]`,
    `url = ${tomlString(server.url)}`,
    `bearer_token_env_var = ${tomlString(auth.env_var)}`,
    '',
  ].join('\n');
}

export function codex(connector, catalog, out) {
  const { server, auth } = connector;
  const config = codexConfig(connector);
  out.file(
    'templates/codex/config.toml',
    [
      `# ${server.title} for Codex: add this to the end of ~/.codex/config.toml (Windows: %USERPROFILE%\\.codex\\config.toml),`,
      `# or of .codex/config.toml in a project you trust. Settings placed below it would become part of it.`,
      `# Codex reads the token from $${auth.env_var}.`,
      `# ${GENERATED_TOML_NOTE}`,
      config,
    ].join('\n'),
  );

  const steps = [`export ${auth.env_var}="${auth.token_prefix}..."`, codexAddCommand(connector)].join('\n');
  out.block('README.md', 'codex', fence('bash', steps));
  out.block('docs/codex.md', 'add', fence('bash', steps));
  out.block(
    'docs/codex.md',
    'add-powershell',
    fence(
      'powershell',
      [
        `[Environment]::SetEnvironmentVariable('${auth.env_var}', '${auth.token_prefix}...', 'User')`,
        `$env:${auth.env_var} = '${auth.token_prefix}...'`,
        codexAddCommand(connector),
      ].join('\n'),
    ),
  );
  out.block('docs/codex.md', 'config', fence('toml', config));
  out.block('docs/codex.md', 'remove', fence('bash', `codex mcp remove ${server.name}`));
  out.block(
    'docs/codex.md',
    'tool-names',
    `Codex shows the calls as \`${server.name}.<tool>\`, for example \`${server.name}.${catalog.tools[0].name}\`. ` +
      `Settings for single tools in \`config.toml\` (\`enabled_tools\`, \`disabled_tools\`) take the bare name, such as \`${catalog.tools[0].name}\`.`,
  );
}

const GENERATED_TOML_NOTE = 'Generated by scripts/sync.mjs from connector.json; do not edit by hand.';
