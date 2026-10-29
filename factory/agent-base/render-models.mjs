// agent-base models.json renderer (Task 5).
//
// Converts LLM_PROVIDERS_JSON — the compact array emitted by
// bootstrap/render.py:render_llm_providers_json — into pi's
// ~/.pi/agent/models.json (the pi coding agent's custom-provider config):
//
//   {"providers": {"<name>": {"name": ..., "api": ..., "baseUrl": <literal>?,
//                             "apiKey": <literal>, "models": [{"id": ...}]}}}
//
// baseUrlEnv AND apiKeyEnv are resolved against `env` AT RENDER TIME and
// emitted as literals. baseUrl: pi 1.4.0 does not ${VAR}-interpolate baseUrl
// (only apiKey and headers go through resolveConfigValue — provider-composer
// passes baseUrl through raw into the URL constructor), so a "${VAR}"
// string would kill the first request with "Invalid URL" (BL-18, found by
// the BL-16 spike). apiKey: looper's agent env is an allowlist + scrub
// (inheritedAgentEnvKeys — PATH/HOME/SSL_CERT_FILE class names only), so
// provider keys present in the DAEMON env never reach the spawned pi and a
// "${VAR}" apiKey is unresolvable there — pi fails with "No API key found
// for <provider>. Use /login" and the planner loop silently backs off
// (BL-1 first live-LLM run). The renderer runs where the vars ARE set, so
// inlining adds no new failure mode; models.json is written mode 0600 to
// keep the secret out of world-readable files (the same reason BL-18
// refused to inline into a 0644 file — the mode fix makes inlining safe).
// Fail-fast validation (controller ruling): every referenced var must be
// present as a key of `env` — a missing one throws at container start
// instead of surfacing as a 401 mid-loop — and baseUrl/apiKey values must be
// non-empty (baseUrl must also parse as a URL; pi's URL constructor would
// throw mid-loop otherwise).
//
// Exported: renderModels(providersJson, env) -> models.json object.
// CLI main (node render-models.mjs): reads LLM_PROVIDERS_JSON, validates every
// referenced var against process.env, writes ~/.pi/agent/models.json.
import { chmodSync, mkdirSync, writeFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join } from 'node:path';
import { argv, env, exit, stderr } from 'node:process';
import { pathToFileURL } from 'node:url';

function fail(message) {
  throw new Error(`render-models: ${message}`);
}

function isPresent(env, varName) {
  return Object.prototype.hasOwnProperty.call(env, varName);
}

function renderProvider(entry, env) {
  if (entry === null || typeof entry !== 'object' || Array.isArray(entry)) {
    fail('every provider entry must be a JSON object');
  }
  const { name } = entry;
  if (typeof name !== 'string' || name.length === 0) {
    fail('every provider entry must have a non-empty "name"');
  }
  if (typeof entry.api !== 'string' || entry.api.length === 0) {
    fail(`provider "${name}": missing required "api"`);
  }
  if (!Array.isArray(entry.models) || entry.models.length === 0) {
    fail(`provider "${name}": "models" must be a non-empty array (pi requires at least one model per provider)`);
  }

  const hasEnv = Object.prototype.hasOwnProperty.call(entry, 'apiKeyEnv') && entry.apiKeyEnv !== null;
  const hasLiteral = Object.prototype.hasOwnProperty.call(entry, 'apiKeyLiteral') && entry.apiKeyLiteral !== null;
  if (hasEnv && hasLiteral) {
    fail(`provider "${name}": apiKeyEnv and apiKeyLiteral are mutually exclusive — exactly one must be set`);
  }
  if (!hasEnv && !hasLiteral) {
    fail(`provider "${name}": exactly one of apiKeyEnv / apiKeyLiteral is required`);
  }
  if (hasEnv && (typeof entry.apiKeyEnv !== 'string' || entry.apiKeyEnv.length === 0)) {
    fail(`provider "${name}": apiKeyEnv must be a non-empty string when set`);
  }

  const out = { name, api: entry.api };

  if (entry.baseUrlEnv != null) {
    if (typeof entry.baseUrlEnv !== 'string' || entry.baseUrlEnv.length === 0) {
      fail(`provider "${name}": baseUrlEnv must be a non-empty string when set`);
    }
    if (!isPresent(env, entry.baseUrlEnv)) {
      fail(`provider "${name}": base URL env var "${entry.baseUrlEnv}" not provided by the daemon env`);
    }
    // Inline the resolved literal: pi 1.4.0 passes baseUrl through raw (no
    // ${VAR} interpolation), and the renderer runs where the var is set —
    // resolving here adds no new failure mode (BL-18).
    const baseUrl = env[entry.baseUrlEnv];
    if (typeof baseUrl !== 'string' || baseUrl.length === 0) {
      fail(`provider "${name}": base URL env var "${entry.baseUrlEnv}" is set but empty — cannot inline a literal baseUrl`);
    }
    try {
      new URL(baseUrl);
    } catch {
      fail(`provider "${name}": base URL env var "${entry.baseUrlEnv}" does not parse as a URL — pi would fail with "Invalid URL" at first request`);
    }
    out.baseUrl = baseUrl;
  }

  if (hasEnv) {
    if (!isPresent(env, entry.apiKeyEnv)) {
      fail(`provider "${name}": API key env var "${entry.apiKeyEnv}" not provided by the daemon env`);
    }
    // Inline the resolved literal, exactly like baseUrl above: looper's
    // agent-env allowlist never passes provider keys to the spawned pi, so a
    // "${VAR}" string would be unresolvable at request time (BL-1 finding —
    // planner died with "No API key found for <provider>").
    const apiKey = env[entry.apiKeyEnv];
    if (typeof apiKey !== 'string' || apiKey.length === 0) {
      fail(`provider "${name}": API key env var "${entry.apiKeyEnv}" is set but empty — cannot inline a literal apiKey`);
    }
    out.apiKey = apiKey;
  } else {
    if (typeof entry.apiKeyLiteral !== 'string' || entry.apiKeyLiteral.length === 0) {
      fail(`provider "${name}": apiKeyLiteral must be a non-empty string when set`);
    }
    out.apiKey = entry.apiKeyLiteral;
  }

  out.models = entry.models.map((model, index) => {
    if (model === null || typeof model !== 'object' || typeof model.id !== 'string' || model.id.length === 0) {
      fail(`provider "${name}": models[${index}] must be an object with a non-empty string "id"`);
    }
    return { id: model.id };
  });

  return out;
}

export function renderModels(providersJson, env) {
  let parsed;
  try {
    parsed = JSON.parse(providersJson);
  } catch (err) {
    fail(`LLM_PROVIDERS_JSON is invalid JSON (${err.message})`);
  }
  if (!Array.isArray(parsed)) {
    fail('LLM_PROVIDERS_JSON must be a JSON array of provider entries');
  }
  if (parsed.length === 0) {
    fail('LLM_PROVIDERS_JSON is empty — at least one provider is required');
  }
  if (env === null || typeof env !== 'object') {
    fail('env must be an object mapping provided variable names (values used for baseUrl resolution)');
  }

  const providers = {};
  for (const entry of parsed) {
    const provider = renderProvider(entry, env);
    // '__proto__' would set the object's prototype instead of an own key —
    // the entry would silently vanish from models.json (BL-9).
    if (provider.name === '__proto__') {
      fail(`provider name '__proto__' is forbidden — it would corrupt models.json`);
    }
    if (Object.prototype.hasOwnProperty.call(providers, provider.name)) {
      fail(`duplicate provider name '${provider.name}' — provider names must be unique`);
    }
    providers[provider.name] = provider;
  }
  return { providers };
}

function main() {
  const raw = env.LLM_PROVIDERS_JSON;
  if (raw == null || raw.length === 0) {
    stderr.write('render-models: LLM_PROVIDERS_JSON is not set — cannot render ~/.pi/agent/models.json\n');
    exit(1);
  }
  // baseUrlEnv and apiKeyEnv are resolved from `env` at render time and
  // inlined as literals (pi does not interpolate baseUrl; looper's agent
  // env allowlist does not pass provider keys through to pi).
  const models = renderModels(raw, env);

  const target = join(homedir(), '.pi', 'agent', 'models.json');
  mkdirSync(dirname(target), { recursive: true });
  // 0600: the inlined apiKey is secret material (BL-1); writeFileSync mode
  // only applies at create, so enforce it on every render (upgrade path:
  // an older 0644 file gets tightened, not just replaced).
  writeFileSync(target, JSON.stringify(models, null, 2) + '\n', { mode: 0o600 });
  chmodSync(target, 0o600);
  stderr.write(`render-models: wrote ${target} (${Object.keys(models.providers).length} provider(s))\n`);
}

const invokedAsMain =
  argv[1] != null && argv[1] !== '' && import.meta.url === pathToFileURL(argv[1]).href;
if (invokedAsMain) {
  try {
    main();
  } catch (err) {
    stderr.write(`${err instanceof Error ? err.message : String(err)}\n`);
    exit(1);
  }
}
