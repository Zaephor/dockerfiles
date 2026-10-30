// factory-prime — convergent pinned harness priming (D11, spec §5, R14).
//
// Node script shipped in the looperd image (Task 7 wires the entrypoint).
// Runs at every daemon start, after the models.json render and before
// `exec looperd`. Inputs: $LOOPER_CONFIG (the config bootstrap renders — its
// [agent] table names the harness vendor) + the pin envs bootstrap's
// harness_pin_envs renders into the zone EnvironmentFile:
// FACTORY_HARNESS_PIN_<VENDOR> (vendor upper-cased, '-' → '_', so
// claude-code → FACTORY_HARNESS_PIN_CLAUDE_CODE) and the optional
// FACTORY_HARNESS_PIN_<VENDOR>_INTEGRITY twin.
//
// Per vendor (spec §5 loop):
//   1. Steady state = stamp present AND `<bin> --version` output CONTAINS
//      the exact pin (formats differ per CLI — `claude 2.1.312 …`,
//      `codex-cli 0.95.0 …` — spec §11.1 resolved to a contains-check) →
//      skip everything. No network, no npm: a steady daemon starts offline.
//   2. Missing/mismatch → npm install into <dataRoot>/harnesses/<vendor>/
//      <version>/ (npm verifies dist.integrity against the registry when the
//      version is pinned exactly; the ..._INTEGRITY env is recorded in the
//      stamp and compared at start instead — npm has no --integrity flag),
//      write the stamp atomically, re-run the version assert, and only then
//      swap the <dataRoot>/harnesses/bin/<bin> symlink (write .tmp + rename
//      — atomic). Every step before the swap leaves the previous pin fully
//      runnable: old version dirs are kept (rollback = pin back + restart);
//      pruning is manual by design (runbook).
//   3. Any failure → PrimeError (FAIL: prefix) → main() exits 1: the daemon
//      refuses to start on half-state.
//   4. opencode warm step (§5.6, BL-23(a)): gated on a .warm-stamp in
//      <dataRoot>/cache/opencode recording the warmed PIN — once per pin,
// re-paid after a bump. The fetch points HOME inside /data so it persists
//      and agent runs never touch npm; a warm that exits 0 but populates
//      nothing under the cache home FAILS (refuse to mark warm).
//   5. Compose the exec env: PATH prefix <dataRoot>/harnesses/bin + one
//      config-dir export per vendor (CODEX_HOME / CLAUDE_CONFIG_DIR /
//      OPENCODE_CONFIG_DIR → /config/<vendor>; all three are in looper's
//      inheritedAgentEnvKeys allowlist — verified executor.go). main()
//      prints them as `export` lines on stdout; the entrypoint evals them.
//
// `pi` never primes (baked into the agent-base image): parseVendors → [],
// main() prints nothing and exits 0 (fast path).
//
// run/install/warm are injectable so unit tests never touch network/npm;
// dataRoot is the fs root every path derives from.
import { spawnSync } from 'node:child_process';
import {
  mkdirSync,
  readdirSync,
  readFileSync,
  renameSync,
  rmSync,
  symlinkSync,
  writeFileSync,
} from 'node:fs';
import { dirname, join } from 'node:path';
import { argv, env, exit, stderr, stdout } from 'node:process';
import { pathToFileURL } from 'node:url';

export class PrimeError extends Error {
  constructor(message) {
    super(message.startsWith('FAIL:') ? message : `FAIL: ${message}`);
    this.name = 'PrimeError';
  }
}

function fail(message) {
  throw new PrimeError(message);
}

function errText(err) {
  return err instanceof Error ? err.message : String(err);
}

// The pin table (Tasks 6-9 consume these exact strings): npm package +
// the bin npm links into <dir>/node_modules/.bin/.
export const PRIME_TABLE = {
  'claude-code': { pkg: '@anthropic-ai/claude-code', bin: 'claude' },
  codex: { pkg: '@openai/codex', bin: 'codex' },
  opencode: { pkg: 'opencode-ai', bin: 'opencode' },
};

// Config-dir export per vendor (looper inherits these into the agent env —
// spec §5.5); the rendered config trees land there via Task 6's renderer.
// Paths mirror bootstrap's _HARNESS_HOME EXACTLY (render.py, spec §4,
// runbook): claude-code is /config/claude — NOT /config/claude-code — so
// daemon-side `podman exec … claude` (which sees these exports) and agents
// (whose [agent.env] overlay carries the same value) agree on one config
// dir (BL-23(e)).
const CONFIG_DIR = {
  'claude-code': { env: 'CLAUDE_CONFIG_DIR', path: '/config/claude' },
  codex: { env: 'CODEX_HOME', path: '/config/codex' },
  opencode: { env: 'OPENCODE_CONFIG_DIR', path: '/config/opencode' },
};

// Pin env name as bootstrap/render.py:harness_pin_envs renders it: vendor
// upper-cased with '-' → '_' (claude-code → FACTORY_HARNESS_PIN_CLAUDE_CODE),
// plus the optional `..._INTEGRITY` twin.
export function pinEnvName(vendor) {
  return `FACTORY_HARNESS_PIN_${vendor.toUpperCase().replace(/-/g, '_')}`;
}

// --- TOML-subset parser: [agent] vendor (v1) --------------------------------
//
// Scoped to exactly what bootstrap renders for v1: the `vendor` key of the
// `[agent]` table, quoted. Sub-tables ([agent.env]) are NOT `[agent]`;
// unknown tables/keys are skipped. Malformed input fails fast.
// TODO(v2): agent.profiles/roles overlays per R14 — merge overlay vendors
// with the base [agent] vendor (dedup, order-preserving).

function stripTomlComment(line) {
  // Quote-aware: `vendor = "a#b" # note` keeps the quoted #, drops the rest.
  let inString = false;
  for (let i = 0; i < line.length; i += 1) {
    const ch = line[i];
    if (ch === '"') inString = !inString;
    else if (ch === '#' && !inString) return line.slice(0, i);
  }
  return line;
}

function parseTomlStringValue(raw) {
  const value = raw.trim();
  const basic = /^"((?:[^"\\]|\\.)*)"$/.exec(value);
  if (basic) {
    return { value: basic[1].replace(/\\(.)/g, (_, ch) => (ch === 'n' ? '\n' : ch === 't' ? '\t' : ch)) };
  }
  const literal = /^'([^']*)'$/.exec(value);
  if (literal) return { value: literal[1] };
  return { error: `not a quoted string: ${value}` };
}

export function parseVendors(configToml) {
  if (typeof configToml !== 'string' || configToml.trim().length === 0) {
    fail('looper config is empty — cannot read the [agent] vendor');
  }
  let inAgentTable = false;
  let sawAgentTable = false;
  let vendor = null;
  for (const rawLine of configToml.split(/\r?\n/)) {
    const line = stripTomlComment(rawLine).trim();
    if (line.length === 0) continue;
    const header = /^\[([^\]]+)\]$/.exec(line);
    if (header) {
      inAgentTable = header[1].trim() === 'agent';
      if (inAgentTable) sawAgentTable = true;
      continue;
    }
    const kv = /^([A-Za-z0-9_.-]+)\s*=\s*(.+)$/.exec(line);
    if (!kv || !inAgentTable || kv[1] !== 'vendor') continue;
    if (vendor !== null) {
      fail('duplicate "vendor" key in [agent] — malformed looper config');
    }
    const parsed = parseTomlStringValue(kv[2]);
    if (parsed.error) {
      fail(`[agent] vendor must be a quoted string (e.g. vendor = "codex") — ${parsed.error}`);
    }
    if (parsed.value.length === 0) {
      fail('[agent] vendor is empty — cannot determine the harness to prime');
    }
    vendor = parsed.value;
  }
  if (vendor === null) {
    fail(
      sawAgentTable
        ? '[agent] has no vendor key — cannot determine the harness to prime'
        : 'looper config has no [agent] table — cannot determine the harness to prime',
    );
  }
  // pi is baked into the agent-base image (the historical default vendor):
  // nothing to prime, no pin envs, no exports.
  if (vendor === 'pi') return [];
  if (!Object.prototype.hasOwnProperty.call(PRIME_TABLE, vendor)) {
    fail(`unknown harness vendor '${vendor}' — known: ${Object.keys(PRIME_TABLE).join(', ')}, pi`);
  }
  return [vendor];
}

// --- prime loop (spec §5) -----------------------------------------------------

function readStamp(stampPath) {
  let raw;
  try {
    raw = readFileSync(stampPath, 'utf8');
  } catch {
    return null;
  }
  try {
    const stamp = JSON.parse(raw);
    return stamp !== null && typeof stamp === 'object' ? stamp : null;
  } catch {
    // A corrupt stamp counts as a mismatch → reinstall (fail-closed).
    return null;
  }
}

function writeStampAtomic(stampPath, stamp) {
  const tmp = `${stampPath}.tmp`;
  writeFileSync(tmp, `${JSON.stringify(stamp, null, 2)}\n`);
  renameSync(tmp, stampPath);
}

function swapSymlinkAtomic(linkPath, targetPath) {
  mkdirSync(dirname(linkPath), { recursive: true });
  const tmp = `${linkPath}.tmp`;
  rmSync(tmp, { force: true });
  symlinkSync(targetPath, tmp);
  // rename(2) over an existing symlink replaces it atomically — a daemon
  // starting concurrently never observes a missing bin.
  renameSync(tmp, linkPath);
}

function dirPopulated(dir) {
  try {
    return readdirSync(dir).length > 0;
  } catch {
    return false;
  }
}

// `<bin> --version` output containing the exact pin string (formats differ
// per CLI — spec §11.1); stderr is searched too (some CLIs print there).
function versionOutput(out) {
  return `${out?.stdout ?? ''}\n${out?.stderr ?? ''}`;
}

function assertsPin(out, version) {
  return out != null && out.code === 0 && versionOutput(out).includes(version);
}

function snippet(text) {
  const firstLine = text.split('\n').map((l) => l.trim()).filter(Boolean)[0] ?? '';
  return firstLine.length > 120 ? `${firstLine.slice(0, 117)}...` : firstLine;
}

// Real-world implementations (injected run/install keep tests offline).

function defaultRun(cmd) {
  const result = spawnSync(cmd, { shell: true, encoding: 'utf8' });
  return { code: result.status ?? 1, stdout: result.stdout ?? '', stderr: result.stderr ?? '' };
}

function defaultInstall(pkg, version, dir) {
  const result = spawnSync('npm', ['install', '--prefix', dir, `${pkg}@${version}`], {
    encoding: 'utf8',
  });
  if (result.status !== 0) {
    throw new Error(
      `npm install --prefix ${dir} ${pkg}@${version} exited ${result.status}\n${`${result.stdout ?? ''}${result.stderr ?? ''}`.trim()}`,
    );
  }
}

// Default warm (spec §5.6, §11 item 2): `opencode models` walks the provider
// registry and pre-fetches opencode's AI-SDK provider packages into HOME's
// cache dirs — HOME is pointed inside the /data volume so the fetch persists
// across container recreation and agent runs never touch npm. Fallback if
// `models` alone does not populate the cache: a 1-token `opencode run warm`
// (same HOME), tried only when `models` exits non-zero. Acceptance either
// way (BL-23(a), REAL-run evidence opencode-warm-inventory.txt): cacheHome
// non-empty after warm — a warm that populates nothing FAILS instead of
// writing a stamp that would gate future starts on an empty cache.
export function defaultWarm({ cacheHome, bin, run }) {
  const q = (s) => `"${s.replace(/"/g, '\\"')}"`;
  let out = run(`HOME=${q(cacheHome)} ${q(bin)} models`);
  if (out.code !== 0) {
    out = run(`HOME=${q(cacheHome)} ${q(bin)} run warm`);
  }
  if (out.code !== 0) {
    fail(`opencode warm: both 'opencode models' and 'opencode run warm' exited ${out.code}`);
  }
  if (!dirPopulated(cacheHome)) {
    fail(
      `opencode warm: exited 0 but populated nothing under ${cacheHome} — refusing to mark warm (a real warm pre-fetches the AI-SDK provider packages there)`,
    );
  }
}

/**
 * Prime every vendor to its exact pin. Injectables keep unit tests offline:
 * `run(cmd) -> {code, stdout[, stderr]}`, `install(pkg, version, dir)`,
 * `warm({vendor, dataRoot, cacheDir, cacheHome, bin, run})`.
 *
 * @returns {{envExports: Record<string, string>, pathPrefix: string}}
 */
export function prime({ dataRoot, vendors, run, install, warm, log }) {
  if (typeof dataRoot !== 'string' || dataRoot.length === 0) {
    fail('dataRoot is required (the /data volume root the harnesses live under)');
  }
  if (!Array.isArray(vendors)) {
    fail('vendors must be an array of {vendor, version, integrity?}');
  }
  const runFn = run ?? defaultRun;
  const installFn = install ?? defaultInstall;
  const logFn = log ?? (() => {});
  const binDir = join(dataRoot, 'harnesses', 'bin');
  const envExports = {};

  for (const entry of vendors) {
    const vendor = entry?.vendor;
    const version = entry?.version;
    const integrity = entry?.integrity;

    // pi ships inside the agent-base image — no priming, no exports (§5.1).
    if (vendor === 'pi') continue;
    if (!Object.prototype.hasOwnProperty.call(PRIME_TABLE, vendor)) {
      fail(`unknown harness vendor '${String(vendor)}' — known: ${Object.keys(PRIME_TABLE).join(', ')}, pi`);
    }
    if (typeof version !== 'string' || version.length === 0) {
      fail(`harness vendor '${vendor}' has no pin — refusing to float to latest`);
    }

    const { pkg, bin } = PRIME_TABLE[vendor];
    const dir = join(dataRoot, 'harnesses', vendor, version);
    const stampPath = join(dir, '.prime-stamp');
    const steadyBin = join(binDir, bin);
    const versionedBin = join(dir, 'node_modules', '.bin', bin);

    const stamp = readStamp(stampPath);
    const stampMatches =
      stamp != null &&
      stamp.vendor === vendor &&
      stamp.version === version &&
      // The integrity pin is compared at start even when npm's own registry
      // check covered the tarball at install (spec §5.3).
      (integrity == null || stamp.integrity === integrity);

    if (stampMatches && assertsPin(runFn(`${steadyBin} --version`), version)) {
      logFn(`${vendor} ${version}: stamp + version match — offline skip`);
    } else if (stampMatches && assertsPin(runFn(`${versionedBin} --version`), version)) {
      // BL-23(b): the install itself is fine — the bin-dir symlink is what
      // broke (manual /data prune, deleted bin dir, stale swap). Re-swap
      // from the existing versioned bin and stay offline: no npm.
      swapSymlinkAtomic(join(binDir, bin), versionedBin);
      logFn(`${vendor} ${version}: stamp + versioned bin match — bin symlink healed (no install)`);
    } else {
      // Missing/mismatch (§5.3): install into the versioned dir, stamp
      // atomically, re-assert, only then swap the bin symlink. Every step
      // before the swap leaves the previous pin fully runnable.
      mkdirSync(dir, { recursive: true });
      try {
        installFn(pkg, version, dir);
      } catch (err) {
        fail(`install of ${pkg}@${version} into ${dir} failed: ${errText(err)} — the previous version dir, stamp and bin symlink are untouched (pin back + restart rolls back)`);
      }
      writeStampAtomic(stampPath, integrity != null && integrity.length > 0
        ? { vendor, version, integrity }
        : { vendor, version });
      const out = runFn(`${versionedBin} --version`);
      if (!assertsPin(out, version)) {
        fail(`${vendor} ${version}: installed, but '${bin} --version' did not report the pin (code ${out?.code ?? '?'}: ${snippet(versionOutput(out))}) — refusing to swap the bin symlink`);
      }
      swapSymlinkAtomic(join(binDir, bin), versionedBin);
      logFn(`${vendor} ${version}: installed + asserted — bin symlink swapped`);
    }

    // Config-dir export (§5.5): looper inherits these into the agent env.
    envExports[CONFIG_DIR[vendor].env] = CONFIG_DIR[vendor].path;

    if (vendor === 'opencode') {
      // BL-23(a): once-per-pin gate. The old gate ("cache dir non-empty")
      // was satisfied forever by the primer's own marker file, so a pin
      // bump never re-paid the warm; the stamp records WHICH pin warmed.
      const cacheDir = join(dataRoot, 'cache', 'opencode');
      const warmStampPath = join(cacheDir, '.warm-stamp');
      const warmStamp = readStamp(warmStampPath);
      if (warmStamp != null && warmStamp.vendor === 'opencode' && warmStamp.version === version) {
        logFn('opencode: warm stamp matches the pin — skipping warm (§5.6)');
      } else {
        logFn('opencode: warm stamp missing or stale — warming (§5.6)');
        const warmFn = warm ?? defaultWarm;
        try {
          warmFn({
            vendor,
            dataRoot,
            cacheDir,
            cacheHome: join(dataRoot, 'cache', 'opencode-home'),
            bin: steadyBin,
            run: runFn,
          });
        } catch (err) {
          if (err instanceof PrimeError) throw err;
          fail(`opencode warm step failed: ${errText(err)}`);
        }
        // Bookkeeping lives here, not in warmFn: prime owns the stamp so
        // injected test fakes (and future warm strategies) cannot forget it.
        mkdirSync(cacheDir, { recursive: true });
        writeStampAtomic(warmStampPath, { vendor: 'opencode', version });
      }
    }
  }

  return { envExports, pathPrefix: binDir };
}

// --- CLI ------------------------------------------------------------------------

function main() {
  const configPath = env.LOOPER_CONFIG;
  if (configPath == null || configPath.length === 0) {
    fail('LOOPER_CONFIG is not set — factory-prime cannot read the zone config');
  }
  let configToml;
  try {
    configToml = readFileSync(configPath, 'utf8');
  } catch (err) {
    fail(`cannot read LOOPER_CONFIG (${configPath}): ${errText(err)}`);
  }
  const vendors = parseVendors(configToml);
  if (vendors.length === 0) {
    // pi zone (fast path): the harness is baked into the image — print
    // nothing to eval and exit 0 (Task 7's entrypoint contract).
    return;
  }

  const dataRoot =
    env.FACTORY_DATA_ROOT && env.FACTORY_DATA_ROOT.length > 0 ? env.FACTORY_DATA_ROOT : '/data';
  const entries = vendors.map((vendor) => {
    const pinEnv = pinEnvName(vendor);
    const version = env[pinEnv];
    if (version == null || version.length === 0) {
      fail(`${pinEnv} is not set — refusing to float ${vendor} to latest (render the zone EnvironmentFile via the provision CLI, or hand-set the pin)`);
    }
    const integrityEnv = env[`${pinEnv}_INTEGRITY`];
    return integrityEnv != null && integrityEnv.length > 0
      ? { vendor, version, integrity: integrityEnv }
      : { vendor, version };
  });

  const { envExports, pathPrefix } = prime({
    dataRoot,
    vendors: entries,
    run: defaultRun,
    install: defaultInstall,
    log: (message) => stderr.write(`factory-prime: ${message}\n`),
  });

  // The entrypoint evals these lines (Task 7): PATH first, then the
  // config-dir exports looper's agent-env allowlist inherits.
  stdout.write(`export PATH="${pathPrefix}:$PATH"\n`);
  for (const [key, value] of Object.entries(envExports)) {
    stdout.write(`export ${key}="${value}"\n`);
  }
}

const invokedAsMain =
  argv[1] != null && argv[1] !== '' && import.meta.url === pathToFileURL(argv[1]).href;
if (invokedAsMain) {
  try {
    main();
  } catch (err) {
    stderr.write(`${errText(err)}\n`);
    exit(1);
  }
}
