const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const PORT = process.env.PORT || 10000;
const DIST_DIR = path.join(__dirname, 'public');
const FALLBACK_STORE = path.join(__dirname, 'sync_store.json');

const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.mjs': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.wasm': 'application/wasm',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.ttf': 'font/ttf',
  '.otf': 'font/otf',
};

// ── Storage Layer (PostgreSQL via DATABASE_URL, or local JSON fallback) ───────

let pgPool = null;

async function initStorage() {
  const dbUrl = process.env.DATABASE_URL;
  if (dbUrl) {
    try {
      const { Pool } = require('pg');
      const needsSsl = !dbUrl.includes('localhost') && !dbUrl.includes('127.0.0.1');
      pgPool = new Pool({
        connectionString: dbUrl,
        ssl: needsSsl ? { rejectUnauthorized: false } : false,
      });
      await pgPool.query(`
        CREATE TABLE IF NOT EXISTS sync_workspaces (
          workspace_id TEXT PRIMARY KEY,
          passcode_hash TEXT NOT NULL,
          version BIGINT NOT NULL DEFAULT 0,
          updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
          payload JSONB
        );
      `);
      console.log('Sync storage initialized: PostgreSQL');
      return;
    } catch (err) {
      console.error('PostgreSQL init failed, falling back to file store:', err.message);
      pgPool = null;
    }
  }
  console.log('Sync storage initialized: local JSON fallback (set DATABASE_URL for persistent DB)');
}

function hashPasscode(workspaceId, passcode) {
  return crypto
    .createHash('sha256')
    .update(`barbell_therapy:${workspaceId}:${passcode}`)
    .digest('hex');
}

function readFallbackStore() {
  try {
    if (fs.existsSync(FALLBACK_STORE)) {
      return JSON.parse(fs.readFileSync(FALLBACK_STORE, 'utf8'));
    }
  } catch (_) {}
  return {};
}

function writeFallbackStore(store) {
  fs.writeFileSync(FALLBACK_STORE, JSON.stringify(store), 'utf8');
}

async function getWorkspace(workspaceId) {
  if (pgPool) {
    const res = await pgPool.query(
      'SELECT workspace_id, passcode_hash, version::int AS version, updated_at, payload FROM sync_workspaces WHERE workspace_id = $1',
      [workspaceId]
    );
    return res.rows[0] || null;
  }
  const store = readFallbackStore();
  return store[workspaceId] || null;
}

async function createWorkspace(workspaceId, passcodeHash) {
  const now = new Date().toISOString();
  if (pgPool) {
    await pgPool.query(
      'INSERT INTO sync_workspaces (workspace_id, passcode_hash, version, updated_at, payload) VALUES ($1, $2, 0, NOW(), NULL)',
      [workspaceId, passcodeHash]
    );
    return { workspace_id: workspaceId, passcode_hash: passcodeHash, version: 0, updated_at: now, payload: null };
  }
  const store = readFallbackStore();
  store[workspaceId] = { workspace_id: workspaceId, passcode_hash: passcodeHash, version: 0, updated_at: now, payload: null };
  writeFallbackStore(store);
  return store[workspaceId];
}

async function updateWorkspacePayload(workspaceId, newVersion, payload) {
  const now = new Date().toISOString();
  if (pgPool) {
    const res = await pgPool.query(
      'UPDATE sync_workspaces SET version = $2, updated_at = NOW(), payload = $3::jsonb WHERE workspace_id = $1 RETURNING version::int AS version, updated_at',
      [workspaceId, newVersion, JSON.stringify(payload)]
    );
    return res.rows[0];
  }
  const store = readFallbackStore();
  store[workspaceId].version = newVersion;
  store[workspaceId].updated_at = now;
  store[workspaceId].payload = payload;
  writeFallbackStore(store);
  return { version: newVersion, updated_at: now };
}

// ── HTTP Helpers ──────────────────────────────────────────────────────────────

function setCors(res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
}

function sendJson(res, status, data) {
  setCors(res);
  res.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' });
  res.end(JSON.stringify(data));
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on('data', (chunk) => {
      size += chunk.length;
      if (size > 25 * 1024 * 1024) {
        reject(new Error('Payload too large'));
        req.destroy();
        return;
      }
      chunks.push(chunk);
    });
    req.on('end', () => {
      try {
        const raw = Buffer.concat(chunks).toString('utf8');
        resolve(raw ? JSON.parse(raw) : {});
      } catch (e) {
        reject(new Error('Invalid JSON body'));
      }
    });
    req.on('error', reject);
  });
}

async function handleApi(req, res, urlPath) {
  if (req.method === 'OPTIONS') {
    setCors(res);
    res.writeHead(204);
    res.end();
    return;
  }

  if (urlPath === '/api/health' && req.method === 'GET') {
    return sendJson(res, 200, { ok: true, storage: pgPool ? 'postgres' : 'file' });
  }

  if (req.method !== 'POST') {
    return sendJson(res, 405, { error: 'Method not allowed' });
  }

  let body;
  try {
    body = await readBody(req);
  } catch (e) {
    return sendJson(res, 400, { error: e.message });
  }

  const workspaceId = String(body.workspaceId || '').trim().toLowerCase();
  const passcode = String(body.passcode || '').trim();
  if (!workspaceId || workspaceId.length < 3) {
    return sendJson(res, 400, { error: 'Gym Sync ID must be at least 3 characters.' });
  }
  if (!passcode || passcode.length < 4) {
    return sendJson(res, 400, { error: 'Sync passcode must be at least 4 characters.' });
  }

  const passHash = hashPasscode(workspaceId, passcode);
  let ws = await getWorkspace(workspaceId);

  if (urlPath === '/api/sync/connect') {
    if (!ws) {
      ws = await createWorkspace(workspaceId, passHash);
      return sendJson(res, 200, {
        ok: true,
        created: true,
        version: 0,
        updatedAt: ws.updated_at,
        payload: null,
      });
    }
    if (ws.passcode_hash !== passHash) {
      return sendJson(res, 401, { error: 'Incorrect sync passcode for this Gym Sync ID.' });
    }
    return sendJson(res, 200, {
      ok: true,
      created: false,
      version: ws.version,
      updatedAt: ws.updated_at,
      payload: ws.payload,
    });
  }

  if (!ws) {
    return sendJson(res, 404, { error: 'Workspace not found. Connect first.' });
  }
  if (ws.passcode_hash !== passHash) {
    return sendJson(res, 401, { error: 'Incorrect sync passcode.' });
  }

  if (urlPath === '/api/sync/pull') {
    return sendJson(res, 200, {
      ok: true,
      version: ws.version,
      updatedAt: ws.updated_at,
      payload: ws.payload,
    });
  }

  if (urlPath === '/api/sync/push') {
    const baseVersion = body.baseVersion;
    const payload = body.payload;
    if (!payload || typeof payload !== 'object') {
      return sendJson(res, 400, { error: 'Missing sync payload.' });
    }
    if (typeof baseVersion === 'number' && ws.version > baseVersion) {
      return sendJson(res, 409, {
        conflict: true,
        version: ws.version,
        updatedAt: ws.updated_at,
        payload: ws.payload,
      });
    }
    const nextVersion = ws.version + 1;
    const updated = await updateWorkspacePayload(workspaceId, nextVersion, payload);
    return sendJson(res, 200, {
      ok: true,
      version: updated.version,
      updatedAt: updated.updated_at,
    });
  }

  return sendJson(res, 404, { error: 'Unknown API route' });
}

// ── Main Server ───────────────────────────────────────────────────────────────

const server = http.createServer(async (req, res) => {
  const urlPath = (req.url || '/').split('?')[0];

  if (urlPath.startsWith('/api/')) {
    try {
      await handleApi(req, res, urlPath);
    } catch (err) {
      console.error('API error:', err);
      sendJson(res, 500, { error: 'Internal server error' });
    }
    return;
  }

  let safePath = path.normalize(urlPath).replace(/^(\.\.[/\\])+/, '');
  if (safePath === '/' || safePath === '\\') {
    safePath = 'index.html';
  }

  let filePath = path.join(DIST_DIR, safePath);
  if (!fs.existsSync(filePath) || fs.statSync(filePath).isDirectory()) {
    filePath = path.join(DIST_DIR, 'index.html');
  }

  const ext = path.extname(filePath).toLowerCase();
  const contentType = MIME_TYPES[ext] || 'application/octet-stream';

  fs.readFile(filePath, (err, content) => {
    if (err) {
      res.writeHead(500, { 'Content-Type': 'text/plain' });
      res.end('Internal Server Error');
      return;
    }

    const headers = {
      'Content-Type': contentType,
      'Cross-Origin-Opener-Policy': 'same-origin',
      'Cross-Origin-Embedder-Policy': 'credentialless',
    };

    if (ext === '.html' || path.basename(filePath) === 'flutter_service_worker.js') {
      headers['Cache-Control'] = 'no-cache, no-store, must-revalidate';
    } else {
      headers['Cache-Control'] = 'public, max-age=86400';
    }

    res.writeHead(200, headers);
    res.end(content);
  });
});

initStorage().then(() => {
  server.listen(PORT, '0.0.0.0', () => {
    console.log(`Barbell Therapy server running on http://0.0.0.0:${PORT}`);
  });
});
