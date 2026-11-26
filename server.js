const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = process.env.PORT || 10000;
const DIST_DIR = path.join(__dirname, 'public');

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

const server = http.createServer((req, res) => {
  const urlPath = (req.url || '/').split('?')[0];
  let safePath = path.normalize(urlPath).replace(/^(\.\.[/\\])+/, '');
  if (safePath === '/' || safePath === '\\') {
    safePath = 'index.html';
  }

  let filePath = path.join(DIST_DIR, safePath);

  if (!fs.existsSync(filePath) || fs.statSync(filePath).isDirectory()) {
    // SPA fallback for Flutter GoRouter routes
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

    // Never cache the bootstrap/index/service worker; cache static assets
    if (ext === '.html' || path.basename(filePath) === 'flutter_service_worker.js') {
      headers['Cache-Control'] = 'no-cache, no-store, must-revalidate';
    } else {
      headers['Cache-Control'] = 'public, max-age=86400';
    }

    res.writeHead(200, headers);
    res.end(content);
  });
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`Barbell Therapy web server running on http://0.0.0.0:${PORT}`);
});
