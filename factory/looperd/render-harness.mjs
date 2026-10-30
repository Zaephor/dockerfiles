// render-harness — per-harness config renderer (Task 6, R13, spec §4).
//
// Node script shipped in the looperd image (Task 7 wires the entrypoint
// after factory-prime). Renders the config FILE each harness vendor reads:
//
//   codex      <configRoot>/codex/config.toml     (CODEX_HOME)
//   opencode   <configRoot>/opencode/opencode.json (OPENCODE_CONFIG_DIR)
//   claude-code  — no file (env-only auth: ANTHROPIC_* in [agent.env])
//
// Input: $FACTORY_HARNESS_CFG_JSON — the compact blob Task 2's
// harness_pin_envs renders into the zone EnvironmentFile:
// {vendor, baseUrl, model, envKey, providerId}. It carries the env NAME the
// file must reference (codex env_key, opencode apiKey "{env:VAR}") — the key
// VALUE never appears in the blob, and nothing here ever writes key material
// (spec §4: "key never in the file"). UNSET → skip silently, exit 0 (pi
// zones / bare interactive use — the entrypoint's LLM_PROVIDERS_JSON skip
// pattern); SET-BUT-EMPTY → FAIL: + exit 1 (BL-9: refuse to guess on a
// bootstrap/renderer contract break).
//
// File bodies are the probe-verified shapes (research/spike-multi-harness/,
// pinned verbatim by tests):
//   codex — model/model_provider + [model_providers.<providerId>] with
//     name/base_url/env_key/wire_api="chat" (name is a REQUIRED field — codex
//     0.94.0 refuses the table without it, found live by Task 11's REAL
//     lane). The chat wire is load-bearing:
//     z.ai has no Responses API, and codex ≥~0.95 refuses wire_api="chat"
//     (the pin stays at 0.94.0 — codex.md gotcha 1). A non-URL baseUrl or a
//     provider-qualified model ref means the Task 2 contract drifted — fail
//     named at render time instead of a 401/"Invalid URL" mid-loop
//     (render-models.mjs stance).
//   opencode — a factory-<provider> provider block: npm
//     "@ai-sdk/openai-compatible" (custom providers ship no default AI-SDK
//     package), options.baseURL, options.apiKey "{env:VAR}" (shell-style
//     ${VAR} is NOT expanded — the literal would be sent as the bearer
//     token; a missing options.apiKey sends requests unauthenticated —
//     opencode.md "learned the hard way"), and models keyed by the bare id
//     from the "<providerId>/<id>" ref Task 2 maps for opencode.
//
// Every write lands mode 0600 with chmodSync on every render (R11: mode
// only applies at create, so an older 0644 file gets tightened, not just
// replaced). configRoot defaults to /config — the mount factory-prime's
// CODEX_HOME/OPENCODE_CONFIG_DIR exports point at; $FACTORY_CONFIG_ROOT
// overrides it so unit tests never write outside tmpdirs (the
// FACTORY_DATA_ROOT seam precedent, Task 5).
//
// Exported: parseHarnessCfg(raw) (envelope + vendor), renderCodexConfig(...)
// and renderOpencodeConfig(...) (pure body builders), renderHarnessFiles(...)
// (dispatch + fs). CLI main (node render-harness.mjs): reads the blob env,
// writes files, prints one stderr line per file; any failure → RenderError
// ("FAIL:" prefix) → exit 1.
import { chmodSync, mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { argv, env, exit, stderr } from 'node:process';
import { pathToFileURL } from 'node:url';

export class RenderError extends Error {
  constructor(message) {
    super(message.startsWith('FAIL:') ? message : `FAIL: ${message}`);
    this.name = 'RenderError';
  }
}

function fail(message) {
  throw new RenderError(message);
}

// Task 2's vendor set: the two file-rendering vendors plus claude-code
// (which renders nothing — it is listed so a claude-code blob is a clean
// no-op rather than a scary unknown-vendor failure).
const KNOWN_VENDORS = ['claude-code', 'codex', 'opencode'];

function requireField(obj, field, vendor) {
  const value = obj?.[field];
  if (typeof value !== 'string' || value.length === 0) {
    fail(`vendor '${vendor}': blob field "${field}" must be a non-empty string — re-run the provision CLI to re-render FACTORY_HARNESS_CFG_JSON`);
  }
  return value;
}

function requireBaseUrl(obj, vendor) {
  const baseUrl = requireField(obj, 'baseUrl', vendor);
  try {
    new URL(baseUrl);
  } catch {
    fail(`vendor '${vendor}': blob field "baseUrl" (${baseUrl}) does not parse as a URL — the harness would break with "Invalid URL" at first request`);
  }
  return baseUrl;
}

// TOML basic-string literal (same escaping rule as bootstrap/render.py's
// _toml_quote: backslash, then double-quote).
function tomlQuote(value) {
  return `"${value.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;
}

// TOML key: bare when it matches TOML's bare-key charset, otherwise a quoted
// key — a provider id containing a dot must NOT render as a nested table
// ([model_providers.my.zai] would be model_providers.my.zai, not one key).
function tomlKey(key) {
  return /^[A-Za-z0-9_-]+$/.test(key) ? key : tomlQuote(key);
}

function requireBareModelId(model, vendor) {
  if (model.includes('/')) {
    fail(
      `vendor '${vendor}': blob field "model" must be the BARE model id (Task 2 maps codex refs to the bare id), got '${model}' — the Task 2 blob contract drifted`,
    );
  }
  return model;
}

// '__proto__' as a computed object key sets the prototype instead of an own
// key — the provider/model block would silently vanish from opencode.json
// (the BL-9 pollution class; render-models.mjs guards its provider names for
// the same reason). Codex output is TOML string interpolation — no object
// keys, no vector there.
function requireSafeJsonKey(value, what, vendor) {
  if (value === '__proto__') {
    fail(`vendor '${vendor}': ${what} '__proto__' is forbidden — it would corrupt the rendered JSON`);
  }
  return value;
}

// --- body builders (pure; validated inputs) -----------------------------------

/**
 * codex `$CODEX_HOME/config.toml` — spec §4 row, probe-verified
 * (research/spike-multi-harness/codex.md Option 1). providerId names the
 * model_provider and the [model_providers.<providerId>] table (Task 2: "the
 * name the rendered config gives the provider" — "zai" on the example
 * config); env_key references the key by env NAME.
 *
 * @param {{providerId: string, baseUrl: string, envKey: string, model: string}} cfg
 * @returns {string}
 */
export function renderCodexConfig(cfg) {
  const vendor = 'codex';
  const providerId = requireField(cfg, 'providerId', vendor);
  const baseUrl = requireBaseUrl(cfg, vendor);
  const envKey = requireField(cfg, 'envKey', vendor);
  const model = requireBareModelId(requireField(cfg, 'model', vendor), vendor);
  return [
    `model = ${tomlQuote(model)}`,
    `model_provider = ${tomlQuote(providerId)}`,
    '',
    `[model_providers.${tomlKey(providerId)}]`,
    // `name` is REQUIRED (codex 0.94.0 serde: "missing field `name`") — the
    // Task 6 renderer dropped it and the fake lanes never read the file, so
    // only Task 11's first REAL codex run surfaced it (planner queue retried
    // forever as retryable_transient, zero log lines). Display label; the
    // providerId is the deterministic value (the probe used a human label,
    // same field).
    `name = ${tomlQuote(providerId)}`,
    `base_url = ${tomlQuote(baseUrl)}`,
    `env_key = ${tomlQuote(envKey)}`,
    'wire_api = "chat"',
    '',
  ].join('\n');
}

/**
 * opencode `$OPENCODE_CONFIG_DIR/opencode.json` — spec §4 row, probe-verified
 * (research/spike-multi-harness/opencode.md "rendered opencode.json").
 * providerId is factory-prefixed ("factory-zai"), decoupled from opencode's
 * versioned built-in catalog; model is the "<providerId>/<id>" ref Task 2
 * emits and is split back apart here (fail named on drift).
 *
 * @param {{providerId: string, baseUrl: string, envVar: string, model: string}} cfg
 * @returns {string}
 */
export function renderOpencodeConfig(cfg) {
  const vendor = 'opencode';
  const providerId = requireSafeJsonKey(requireField(cfg, 'providerId', vendor), 'providerId', vendor);
  const baseUrl = requireBaseUrl(cfg, vendor);
  const envVar = requireField(cfg, 'envVar', vendor);
  const model = requireField(cfg, 'model', vendor);
  const prefix = `${providerId}/`;
  if (!model.startsWith(prefix) || model.slice(prefix.length).length === 0 || model.slice(prefix.length).includes('/')) {
    fail(
      `vendor 'opencode': blob field "model" must be "<providerId>/<id>" (Task 2 emits factory-prefixed refs), got '${model}' for provider '${providerId}' — the Task 2 blob contract drifted`,
    );
  }
  const modelId = requireSafeJsonKey(model.slice(prefix.length), 'model id', vendor);
  const doc = {
    $schema: 'https://opencode.ai/config.json',
    provider: {
      [providerId]: {
        npm: '@ai-sdk/openai-compatible',
        // Display label derived from the deterministic id (BL-23(g)) — same
        // stance as codex's `name = providerId`: no hardcoded vendor text.
        name: providerId,
        options: {
          baseURL: baseUrl,
          apiKey: `{env:${envVar}}`,
        },
        models: {
          [modelId]: { name: modelId },
        },
      },
    },
  };
  return `${JSON.stringify(doc, null, 2)}\n`;
}

// --- envelope + dispatch --------------------------------------------------------

/**
 * Parse + validate the FACTORY_HARNESS_CFG_JSON envelope: a JSON object
 * naming a known vendor. Field-level requirements are enforced by the
 * per-vendor renderers (claude-code needs nothing — it renders no file).
 *
 * @param {string} raw
 * @returns {{vendor: string, baseUrl?: string, model?: string, envKey?: string, providerId?: string}}
 */
export function parseHarnessCfg(raw) {
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch (err) {
    fail(`FACTORY_HARNESS_CFG_JSON is invalid JSON (${err instanceof Error ? err.message : String(err)})`);
  }
  if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
    fail('FACTORY_HARNESS_CFG_JSON must be a JSON object {vendor, baseUrl, model, envKey, providerId}');
  }
  const { vendor } = parsed;
  if (typeof vendor !== 'string' || vendor.length === 0) {
    fail('FACTORY_HARNESS_CFG_JSON: "vendor" must be a non-empty string');
  }
  if (!KNOWN_VENDORS.includes(vendor)) {
    fail(`FACTORY_HARNESS_CFG_JSON: unknown harness vendor '${vendor}' — known: ${KNOWN_VENDORS.join(', ')}`);
  }
  return parsed;
}

// 0600 on every write (R11): writeFileSync mode only applies at create, so
// chmodSync enforces it on re-renders too — an older 0644 file gets
// tightened, not just replaced. The files reference the key by env NAME, but
// R13 treats rendered harness config as secret-adjacent (it names endpoints
// + identities) and 0600 costs nothing.
function writeConfigFile(target, body) {
  mkdirSync(dirname(target), { recursive: true });
  writeFileSync(target, body, { mode: 0o600 });
  chmodSync(target, 0o600);
  return target;
}

/**
 * Render every config file the vendor needs under <configRoot>/<vendor>/.
 * claude-code → {} (no file). Returns {<vendor>: <written path>}.
 *
 * @param {{vendor: string, baseUrl?: string, model?: string, envKey?: string, providerId?: string, envVar?: string}} cfg
 * @param {string} configRoot
 * @returns {Record<string, string>}
 */
export function renderHarnessFiles({ cfg, configRoot }) {
  const vendor = cfg?.vendor;
  if (vendor === 'claude-code') {
    // Spec §4: env-only auth (ANTHROPIC_* ride [agent.env] literals) — the
    // vendor deliberately renders no file.
    return {};
  }
  if (vendor === 'codex') {
    return { codex: writeConfigFile(join(configRoot, 'codex', 'config.toml'), renderCodexConfig(cfg)) };
  }
  if (vendor === 'opencode') {
    // Task 2's blob names the env var field "envKey" for BOTH vendors; the
    // brief's renderer param is "envVar" (opencode.json calls it the apiKey
    // env). Map here so renderOpencodeConfig stays callable directly.
    return {
      opencode: writeConfigFile(
        join(configRoot, 'opencode', 'opencode.json'),
        renderOpencodeConfig({
          providerId: cfg.providerId,
          baseUrl: cfg.baseUrl,
          envVar: cfg.envKey ?? cfg.envVar,
          model: cfg.model,
        }),
      ),
    };
  }
  fail(`unknown harness vendor '${String(vendor)}' — known: ${KNOWN_VENDORS.join(', ')}`);
}

// --- CLI ------------------------------------------------------------------------

function main() {
  const raw = env.FACTORY_HARNESS_CFG_JSON;
  if (raw == null) {
    // Unset: pi zones and bare interactive use render nothing (Task 2 emits
    // the blob only for file-rendering vendors) — silent skip, exit 0.
    return;
  }
  if (raw.length === 0) {
    fail('FACTORY_HARNESS_CFG_JSON is set but empty — a harness zone was rendered without its renderer inputs; re-run the provision CLI');
  }
  const cfg = parseHarnessCfg(raw);
  const configRoot =
    env.FACTORY_CONFIG_ROOT && env.FACTORY_CONFIG_ROOT.length > 0 ? env.FACTORY_CONFIG_ROOT : '/config';
  const written = renderHarnessFiles({ cfg, configRoot });
  for (const [vendor, path] of Object.entries(written)) {
    stderr.write(`render-harness: wrote ${path} (vendor ${vendor}, mode 0600)\n`);
  }
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
