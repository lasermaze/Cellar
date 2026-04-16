export interface Env {
  GITHUB_APP_PEM: string;
  GITHUB_APP_ID: string;
  GITHUB_INSTALLATION_ID: string;
  CELLAR_MEMORY_REPO: string;
}

// ---------------------------------------------------------------------------
// Constants — must mirror Swift AgentTools.allowedEnvKeys exactly
// ---------------------------------------------------------------------------

const ALLOWED_ENV_KEYS = new Set([
  "WINEDEBUG",
  "WINEDLLOVERRIDES",
  "WINEPREFIX",
  "STAGING_SHARED_MEMORY",
  "STAGING_WRITECOPY",
  "MESA_GL_VERSION_OVERRIDE",
  "__GL_THREADED_OPTIMIZATIONS",
  "DXVK_HUD",
  "DXVK_LOG_LEVEL",
  "PROTON_USE_WINED3D",
  "SDL_VIDEODRIVER",
  "PULSE_LATENCY_MSEC",
  "__GLX_VENDOR_LIBRARY_NAME",
]);

const VALID_DLL_MODES = new Set(["n", "b", "n,b", "b,n", ""]);

const ALLOWED_REGISTRY_PREFIXES = [
  "HKEY_CURRENT_USER\\",
  "HKEY_LOCAL_MACHINE\\",
];

// ---------------------------------------------------------------------------
// Rate limiting — in-memory per Worker instance (resets on restart, acceptable)
// ---------------------------------------------------------------------------

const rateLimitMap = new Map<string, number[]>();

function isRateLimited(ip: string): boolean {
  const now = Date.now();
  const cutoff = now - 60 * 60 * 1000; // 1 hour
  const timestamps = (rateLimitMap.get(ip) ?? []).filter((t) => t > cutoff);
  if (timestamps.length >= 100) return true;
  timestamps.push(now);
  rateLimitMap.set(ip, timestamps);
  return false;
}

// ---------------------------------------------------------------------------
// Slugify — mirrors Swift slugify() behavior
// ---------------------------------------------------------------------------

function slugify(name: string): string {
  return name
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");
}

// ---------------------------------------------------------------------------
// Base64url helpers for JWT
// ---------------------------------------------------------------------------

function base64url(data: ArrayBuffer): string {
  const bytes = new Uint8Array(data);
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
}

function base64urlFromString(str: string): string {
  return base64url(new TextEncoder().encode(str).buffer as ArrayBuffer);
}

// ---------------------------------------------------------------------------
// JWT generation using SubtleCrypto RS256 (no npm deps)
// ---------------------------------------------------------------------------

async function makeJWT(pemKey: string, appId: string): Promise<string> {
  // Strip PEM headers (handles both PKCS8 "PRIVATE KEY" and PKCS1 "RSA PRIVATE KEY")
  const stripped = pemKey
    .replace(/-----BEGIN (RSA )?PRIVATE KEY-----/g, "")
    .replace(/-----END (RSA )?PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");

  const binaryDer = Uint8Array.from(atob(stripped), (c) => c.charCodeAt(0));

  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    binaryDer.buffer as ArrayBuffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const payload = { iss: appId, iat: now - 60, exp: now + 510 };

  const headerB64 = base64urlFromString(JSON.stringify(header));
  const payloadB64 = base64urlFromString(JSON.stringify(payload));
  const signingInput = `${headerB64}.${payloadB64}`;

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    new TextEncoder().encode(signingInput)
  );

  return `${signingInput}.${base64url(signature)}`;
}

// ---------------------------------------------------------------------------
// Validation — mirrors Swift sanitizeEntry() exactly
// ---------------------------------------------------------------------------

interface DllOverride {
  dll: string;
  mode: string;
  placement?: string;
  source?: string;
}

interface RegistryEntry {
  key: string;
  valueName: string;
  data: string;
  purpose?: string;
}

interface CollectiveMemoryEntry {
  schemaVersion: number;
  gameId: string;
  gameName: string;
  config: {
    environment: Record<string, string>;
    dllOverrides: DllOverride[];
    registry: RegistryEntry[];
    launchArgs: string[];
    setupDeps: string[];
  };
  environment: {
    arch: string;
    wineVersion: string;
    macosVersion: string;
    wineFlavor: string;
  };
  environmentHash: string;
  reasoning: string;
  engine?: string;
  graphicsApi?: string;
  confirmations: number;
  lastConfirmed: string;
}

// Accept both camelCase and snake_case field names (Swift Codable sends snake_case)
function pick(obj: Record<string, unknown>, camel: string, snake: string): unknown {
  return obj[camel] ?? obj[snake];
}

function validateAndSanitize(entry: unknown): CollectiveMemoryEntry | string {
  if (typeof entry !== "object" || entry === null) return "entry must be an object";
  const e = entry as Record<string, unknown>;

  // Required top-level fields (accept both camelCase and snake_case)
  const gameId = pick(e, "gameId", "game_id");
  const gameName = pick(e, "gameName", "game_name");
  const environmentHash = pick(e, "environmentHash", "environment_hash");
  const config = pick(e, "config", "config");
  const environment = pick(e, "environment", "environment");
  const schemaVersion = pick(e, "schemaVersion", "schema_version");
  const reasoning = pick(e, "reasoning", "reasoning");
  const confirmations = pick(e, "confirmations", "confirmations");
  const lastConfirmed = pick(e, "lastConfirmed", "last_confirmed");
  const engine = pick(e, "engine", "engine");
  const graphicsApi = pick(e, "graphicsApi", "graphics_api");

  if (typeof gameId !== "string" || !gameId) return "missing gameId";
  if (typeof gameName !== "string" || !gameName) return "missing gameName";
  if (typeof environmentHash !== "string" || !environmentHash)
    return "missing environmentHash";
  if (typeof config !== "object" || config === null) return "missing config";
  if (typeof environment !== "object" || environment === null)
    return "missing environment";

  const env = environment as Record<string, unknown>;
  const envArch = pick(env, "arch", "arch") as string | undefined;
  const envWineVer = pick(env, "wineVersion", "wine_version") as string | undefined;
  const envMacosVer = pick(env, "macosVersion", "macos_version") as string | undefined;
  const envWineFlavor = pick(env, "wineFlavor", "wine_flavor") as string | undefined;
  if (typeof envArch !== "string") return "missing environment.arch";
  if (typeof envWineVer !== "string") return "missing environment.wineVersion";
  if (typeof envMacosVer !== "string") return "missing environment.macosVersion";
  if (typeof envWineFlavor !== "string") return "missing environment.wineFlavor";

  const cfg = config as Record<string, unknown>;

  // Sanitize environment keys — filter to allowlist, truncate values to 200 chars
  const rawEnv = (cfg.environment ?? {}) as Record<string, unknown>;
  const sanitizedEnv: Record<string, string> = {};
  for (const [k, v] of Object.entries(rawEnv)) {
    if (ALLOWED_ENV_KEYS.has(k) && typeof v === "string") {
      sanitizedEnv[k] = v.slice(0, 200);
    }
  }

  // Sanitize dllOverrides — drop invalid modes, truncate dll/source
  const rawDlls = Array.isArray(cfg.dllOverrides ?? cfg.dll_overrides) ? (cfg.dllOverrides ?? cfg.dll_overrides) as unknown[] : [];
  const sanitizedDlls: DllOverride[] = rawDlls
    .filter(
      (d): d is Record<string, unknown> =>
        typeof d === "object" && d !== null
    )
    .filter((d) => VALID_DLL_MODES.has(String(d.mode ?? "")))
    .map((d: any) => ({
      dll: String(d.dll ?? "").slice(0, 50),
      mode: String(d.mode ?? ""),
      ...(d.placement !== undefined ? { placement: String(d.placement) } : {}),
      ...(d.source !== undefined ? { source: String(d.source).slice(0, 100) } : {}),
    }));

  // Sanitize registry — drop entries with invalid key prefixes, truncate fields
  const rawReg = Array.isArray(cfg.registry) ? cfg.registry : [];
  const sanitizedReg: RegistryEntry[] = rawReg
    .filter(
      (r): r is Record<string, unknown> =>
        typeof r === "object" && r !== null
    )
    .filter((r) =>
      ALLOWED_REGISTRY_PREFIXES.some((prefix) =>
        String(r.key ?? "").startsWith(prefix)
      )
    )
    .map((r: any) => ({
      key: String(r.key ?? "").slice(0, 200),
      valueName: String(r.valueName ?? r.value_name ?? "").slice(0, 100),
      data: String(r.data ?? "").slice(0, 200),
      ...(r.purpose !== undefined ? { purpose: String(r.purpose) } : {}),
    }));

  // Sanitize launchArgs — cap at 5 entries, 100 chars each
  const rawLaunchArgs = cfg.launchArgs ?? cfg.launch_args;
  const rawArgs = Array.isArray(rawLaunchArgs) ? rawLaunchArgs : [];
  const sanitizedArgs = rawArgs
    .slice(0, 5)
    .map((a: any) => String(a).slice(0, 100));

  // Sanitize setupDeps — only /^[a-z0-9_]{1,50}$/ strings
  const rawSetupDeps = cfg.setupDeps ?? cfg.setup_deps;
  const rawDeps = Array.isArray(rawSetupDeps) ? rawSetupDeps : [];
  const sanitizedDeps = rawDeps
    .filter((d: any) => typeof d === "string" && /^[a-z0-9_]{1,50}$/.test(d));

  return {
    schemaVersion: typeof schemaVersion === "number" ? schemaVersion : 1,
    gameId: gameId as string,
    gameName: gameName as string,
    config: {
      environment: sanitizedEnv,
      dllOverrides: sanitizedDlls,
      registry: sanitizedReg,
      launchArgs: sanitizedArgs,
      setupDeps: sanitizedDeps,
    },
    environment: {
      arch: envArch as string,
      wineVersion: envWineVer as string,
      macosVersion: envMacosVer as string,
      wineFlavor: envWineFlavor as string,
    },
    environmentHash: environmentHash as string,
    reasoning: typeof reasoning === "string" ? reasoning as string : "",
    ...(typeof engine === "string" ? { engine: engine as string } : {}),
    ...(typeof graphicsApi === "string" ? { graphicsApi: graphicsApi as string } : {}),
    confirmations: typeof confirmations === "number" ? confirmations as number : 1,
    lastConfirmed:
      typeof lastConfirmed === "string"
        ? lastConfirmed as string
        : new Date().toISOString(),
  };
}

// ---------------------------------------------------------------------------
// GitHub Contents API helpers
// ---------------------------------------------------------------------------

async function getInstallationToken(env: Env): Promise<string> {
  const jwt = await makeJWT(env.GITHUB_APP_PEM, env.GITHUB_APP_ID);
  const resp = await fetch(
    `https://api.github.com/app/installations/${env.GITHUB_INSTALLATION_ID}/access_tokens`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${jwt}`,
        Accept: "application/vnd.github+json",
        "User-Agent": "cellar-memory-proxy/1.0",
      },
    }
  );
  if (!resp.ok) {
    throw new Error(`Failed to get installation token: ${resp.status}`);
  }
  const data = (await resp.json()) as { token: string };
  return data.token;
}

// Normalize config from either camelCase or snake_case existing entries
function normalizeConfig(cfg: Record<string, unknown> | undefined): CollectiveMemoryEntry["config"] {
  if (!cfg) return { environment: {}, dllOverrides: [], registry: [], launchArgs: [], setupDeps: [] };
  return {
    environment: (cfg.environment ?? {}) as Record<string, string>,
    dllOverrides: ((cfg.dllOverrides ?? cfg.dll_overrides ?? []) as any[]).map((d: any) => ({
      dll: d.dll ?? "", mode: d.mode ?? "",
      ...(d.placement ? { placement: d.placement } : {}),
      ...(d.source ? { source: d.source } : {}),
    })),
    registry: ((cfg.registry ?? []) as any[]).map((r: any) => ({
      key: r.key ?? "", valueName: r.valueName ?? r.value_name ?? "", data: r.data ?? "",
      ...(r.purpose ? { purpose: r.purpose } : {}),
    })),
    launchArgs: (cfg.launchArgs ?? cfg.launch_args ?? []) as string[],
    setupDeps: (cfg.setupDeps ?? cfg.setup_deps ?? []) as string[],
  };
}

// Normalize environment from either camelCase or snake_case
function normalizeEnv(env: Record<string, unknown> | undefined): CollectiveMemoryEntry["environment"] {
  if (!env) return { arch: "", wineVersion: "", macosVersion: "", wineFlavor: "" };
  return {
    arch: (env.arch ?? "") as string,
    wineVersion: (env.wineVersion ?? env.wine_version ?? "") as string,
    macosVersion: (env.macosVersion ?? env.macos_version ?? "") as string,
    wineFlavor: (env.wineFlavor ?? env.wine_flavor ?? "") as string,
  };
}

// Convert a CollectiveMemoryEntry to snake_case JSON keys for Swift Codable compatibility
function toSnakeCaseEntry(e: CollectiveMemoryEntry): Record<string, unknown> {
  return {
    schema_version: e.schemaVersion,
    game_id: e.gameId,
    game_name: e.gameName,
    config: {
      environment: e.config.environment,
      dll_overrides: e.config.dllOverrides.map(d => ({
        dll: d.dll,
        mode: d.mode,
        ...(d.placement ? { placement: d.placement } : {}),
        ...(d.source ? { source: d.source } : {}),
      })),
      registry: e.config.registry.map(r => ({
        key: r.key,
        value_name: r.valueName,
        data: r.data,
        ...(r.purpose ? { purpose: r.purpose } : {}),
      })),
      launch_args: e.config.launchArgs,
      setup_deps: e.config.setupDeps,
    },
    environment: {
      arch: e.environment.arch,
      wine_version: e.environment.wineVersion,
      macos_version: e.environment.macosVersion,
      wine_flavor: e.environment.wineFlavor,
    },
    environment_hash: e.environmentHash,
    reasoning: e.reasoning,
    ...(e.engine ? { engine: e.engine } : {}),
    ...(e.graphicsApi ? { graphics_api: e.graphicsApi } : {}),
    confirmations: e.confirmations,
    last_confirmed: e.lastConfirmed,
  };
}

async function writeEntryToGitHub(
  entry: CollectiveMemoryEntry,
  token: string,
  repo: string,
  attempt = 0
): Promise<void> {
  const slug = slugify(entry.gameId);
  const path = `entries/${slug}.json`;
  const apiBase = `https://api.github.com/repos/${repo}/contents/${path}`;
  const headers = {
    Authorization: `Bearer ${token}`,
    Accept: "application/vnd.github+json",
    "Content-Type": "application/json",
    "User-Agent": "cellar-memory-proxy/1.0",
  };

  // GET existing file
  const getResp = await fetch(apiBase, { headers });
  let sha: string | undefined;
  let entries: CollectiveMemoryEntry[] = [];

  if (getResp.ok) {
    const existing = (await getResp.json()) as { sha: string; content: string };
    sha = existing.sha;
    const decoded = atob(existing.content.replace(/\s/g, ""));
    try {
      const parsed = JSON.parse(decoded) as Record<string, unknown>[];
      // Normalize: accept both camelCase and snake_case from existing entries
      entries = parsed.map(raw => ({
        schemaVersion: (raw.schemaVersion ?? raw.schema_version ?? 1) as number,
        gameId: (raw.gameId ?? raw.game_id ?? "") as string,
        gameName: (raw.gameName ?? raw.game_name ?? "") as string,
        config: normalizeConfig(raw.config as Record<string, unknown> | undefined),
        environment: normalizeEnv(raw.environment as Record<string, unknown> | undefined),
        environmentHash: (raw.environmentHash ?? raw.environment_hash ?? "") as string,
        reasoning: (raw.reasoning ?? "") as string,
        engine: (raw.engine ?? undefined) as string | undefined,
        graphicsApi: (raw.graphicsApi ?? raw.graphics_api ?? undefined) as string | undefined,
        confirmations: (raw.confirmations ?? 1) as number,
        lastConfirmed: (raw.lastConfirmed ?? raw.last_confirmed ?? new Date().toISOString()) as string,
      }));
    } catch {
      entries = [];
    }
  } else if (getResp.status === 404) {
    entries = [];
  } else {
    throw new Error(`GitHub GET failed: ${getResp.status}`);
  }

  // Merge: increment confirmation if matching environmentHash, otherwise append
  const existingIdx = entries.findIndex(
    (e) => e.environmentHash === entry.environmentHash
  );
  if (existingIdx >= 0) {
    entries[existingIdx].confirmations =
      (entries[existingIdx].confirmations ?? 1) + 1;
    entries[existingIdx].lastConfirmed = new Date().toISOString();
  } else {
    entries.push(entry);
  }

  // Convert to snake_case for Swift Codable compatibility before writing
  const snakeCaseEntries = entries.map(toSnakeCaseEntry);

  // Encode and PUT
  const content = btoa(
    unescape(encodeURIComponent(JSON.stringify(snakeCaseEntries, null, 2)))
  );
  const putBody: Record<string, unknown> = {
    message: `chore: update memory entry for ${entry.gameName}`,
    content,
  };
  if (sha) putBody.sha = sha;

  const putResp = await fetch(apiBase, {
    method: "PUT",
    headers,
    body: JSON.stringify(putBody),
  });

  if (putResp.status === 409 && attempt === 0) {
    // Conflict — retry once
    return writeEntryToGitHub(entry, token, repo, 1);
  }

  if (!putResp.ok) {
    throw new Error(`GitHub PUT failed: ${putResp.status}`);
  }
}

// ---------------------------------------------------------------------------
// Wiki append helpers
// ---------------------------------------------------------------------------

interface WikiAppendPayload {
  page: string;
  entry: string;
  commitMessage?: string;
}

// Allowed wiki page paths — prevents directory traversal and writes outside wiki/
const WIKI_PAGE_PATTERN = /^(engines|symptoms|environments|games)\/[a-z0-9-]+\.md$|^log\.md$|^index\.md$/;

async function writeWikiPage(
  page: string,
  entry: string,
  commitMessage: string,
  token: string,
  repo: string,
  attempt = 0
): Promise<"ok" | "skipped"> {
  const path = `wiki/${page}`;
  const apiBase = `https://api.github.com/repos/${repo}/contents/${path}`;
  const headers = {
    Authorization: `Bearer ${token}`,
    Accept: "application/vnd.github+json",
    "Content-Type": "application/json",
    "User-Agent": "cellar-memory-proxy/1.0",
  };

  // GET current file (or 404 — file does not exist yet)
  const getResp = await fetch(apiBase, { headers });
  let sha: string | undefined;
  let existing = "";
  if (getResp.ok) {
    const data = (await getResp.json()) as { sha: string; content: string };
    sha = data.sha;
    existing = atob(data.content.replace(/\s/g, ""));
  } else if (getResp.status !== 404) {
    throw new Error(`GitHub GET failed: ${getResp.status}`);
  }

  // Server-side substring dedup — the Swift client no longer dedups locally
  if (existing.length > 0 && existing.includes(entry.trim())) {
    return "skipped";
  }

  // Append with a leading newline if existing content does not already end in one
  const sep = existing.length === 0 || existing.endsWith("\n") ? "" : "\n";
  const updated = existing + sep + entry + "\n";
  const content = btoa(unescape(encodeURIComponent(updated)));
  const putBody: Record<string, unknown> = { message: commitMessage, content };
  if (sha) putBody.sha = sha;

  const putResp = await fetch(apiBase, {
    method: "PUT",
    headers,
    body: JSON.stringify(putBody),
  });

  if (putResp.status === 409 && attempt === 0) {
    // Concurrent write — retry once
    return writeWikiPage(page, entry, commitMessage, token, repo, 1);
  }
  if (!putResp.ok) {
    throw new Error(`GitHub PUT failed: ${putResp.status}`);
  }
  return "ok";
}

// ---------------------------------------------------------------------------
// Contribute handler
// ---------------------------------------------------------------------------

async function handleContribute(
  request: Request,
  env: Env
): Promise<Response> {
  const cors = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
    "Content-Type": "application/json",
  };

  // Body size cap — 50KB
  const contentLength = Number(request.headers.get("Content-Length") ?? 0);
  if (contentLength > 51200) {
    return new Response(
      JSON.stringify({ status: "error", message: "request body too large" }),
      { status: 413, headers: cors }
    );
  }

  // Parse body
  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return new Response(
      JSON.stringify({ status: "error", message: "invalid JSON" }),
      { status: 400, headers: cors }
    );
  }

  if (typeof body !== "object" || body === null) {
    return new Response(
      JSON.stringify({ status: "error", message: "body must be an object" }),
      { status: 400, headers: cors }
    );
  }

  const rawEntry = (body as Record<string, unknown>).entry;
  if (!rawEntry) {
    return new Response(
      JSON.stringify({ status: "error", message: "missing entry field" }),
      { status: 400, headers: cors }
    );
  }

  // Validate and sanitize
  const result = validateAndSanitize(rawEntry);
  if (typeof result === "string") {
    return new Response(
      JSON.stringify({ status: "error", message: result }),
      { status: 400, headers: cors }
    );
  }
  const entry = result;

  // Rate limit: 10 writes/hr/IP
  const ip =
    request.headers.get("CF-Connecting-IP") ??
    request.headers.get("X-Forwarded-For") ??
    "unknown";
  if (isRateLimited(ip)) {
    return new Response(
      JSON.stringify({ status: "error", message: "rate limit exceeded" }),
      { status: 429, headers: cors }
    );
  }

  // Write to GitHub via installation token
  try {
    const token = await getInstallationToken(env);
    await writeEntryToGitHub(entry, token, env.CELLAR_MEMORY_REPO);
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    return new Response(
      JSON.stringify({ status: "error", message: msg }),
      { status: 502, headers: cors }
    );
  }

  return new Response(JSON.stringify({ status: "ok" }), {
    status: 200,
    headers: cors,
  });
}

// ---------------------------------------------------------------------------
// Wiki append handler
// ---------------------------------------------------------------------------

async function handleWikiAppend(
  request: Request,
  env: Env
): Promise<Response> {
  const cors = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
    "Content-Type": "application/json",
  };

  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: cors });
  }
  if (request.method !== "POST") {
    return new Response("method not allowed", { status: 405, headers: cors });
  }

  // IP rate limit — reuse existing rateLimitMap via isRateLimited helper
  const ip =
    request.headers.get("CF-Connecting-IP") ??
    request.headers.get("X-Forwarded-For") ??
    "unknown";
  if (isRateLimited(ip)) {
    return new Response(
      JSON.stringify({ status: "error", message: "rate_limited" }),
      { status: 429, headers: cors }
    );
  }

  // Body size cap — 50KB, same as handleContribute
  const contentLength = Number(request.headers.get("Content-Length") ?? 0);
  if (contentLength > 51200) {
    return new Response(
      JSON.stringify({ status: "error", message: "payload_too_large" }),
      { status: 413, headers: cors }
    );
  }

  const raw = await request.text();
  if (raw.length > 51200) {
    return new Response(
      JSON.stringify({ status: "error", message: "payload_too_large" }),
      { status: 413, headers: cors }
    );
  }

  let payload: WikiAppendPayload;
  try {
    payload = JSON.parse(raw) as WikiAppendPayload;
  } catch {
    return new Response(
      JSON.stringify({ status: "error", message: "invalid_json" }),
      { status: 400, headers: cors }
    );
  }

  // Path allowlist — prevent directory traversal
  if (typeof payload.page !== "string" || !WIKI_PAGE_PATTERN.test(payload.page)) {
    return new Response(
      JSON.stringify({ status: "error", message: "invalid_page" }),
      { status: 400, headers: cors }
    );
  }
  if (typeof payload.entry !== "string" || payload.entry.trim().length === 0) {
    return new Response(
      JSON.stringify({ status: "error", message: "empty_entry" }),
      { status: 400, headers: cors }
    );
  }

  const commitMessage = payload.commitMessage?.trim() || `wiki: append to ${payload.page}`;

  try {
    const token = await getInstallationToken(env);
    const repo = env.CELLAR_MEMORY_REPO ?? "lasermaze/cellar-memory";
    const result = await writeWikiPage(payload.page, payload.entry, commitMessage, token, repo);
    return new Response(JSON.stringify({ status: result }), {
      status: 200,
      headers: cors,
    });
  } catch (err) {
    return new Response(
      JSON.stringify({ status: "error", message: String(err) }),
      { status: 502, headers: cors }
    );
  }
}

// ---------------------------------------------------------------------------
// Main fetch handler
// ---------------------------------------------------------------------------

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const cors = {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type",
    };

    // Preflight
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors });
    }

    if (request.method === "POST" && url.pathname === "/api/contribute") {
      return handleContribute(request, env);
    }

    if (url.pathname === "/api/wiki/append") {
      return handleWikiAppend(request, env);
    }

    return new Response(JSON.stringify({ status: "error", message: "not found" }), {
      status: 404,
      headers: { ...cors, "Content-Type": "application/json" },
    });
  },
};
