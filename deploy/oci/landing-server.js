'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');

const ROOT = process.env.LANDING_ROOT || path.join(__dirname, '..', '..', 'pages');
const HOST = process.env.LANDING_HOST || '127.0.0.1';
const PORT = parseInt(process.env.LANDING_PORT || '8080', 10);
const REPO = process.env.LANDING_REPO || 'fingod201-maker/BetterDesk-private';
const TOKEN = process.env.BETTERDESK_GITHUB_TOKEN || process.env.GITHUB_TOKEN || '';
const CACHE_MS = 5 * 60 * 1000;

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.webp': 'image/webp',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
  '.apk': 'application/vnd.android.package-archive',
  '.txt': 'text/plain; charset=utf-8',
  '.map': 'application/json; charset=utf-8'
};

let cache = { at: 0, body: null, status: 200 };

function sendJson(res, status, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
    'Content-Length': Buffer.byteLength(body)
  });
  res.end(body);
}

async function getReleases() {
  if (cache.body && Date.now() - cache.at < CACHE_MS) return cache;
  const headers = {
    Accept: 'application/vnd.github+json',
    'User-Agent': 'betterdesk-landing'
  };
  if (TOKEN) headers.Authorization = 'Bearer ' + TOKEN;
  const response = await fetch('https://api.github.com/repos/' + REPO + '/releases?per_page=30', { headers });
  const body = await response.text();
  if (!response.ok) {
    if (cache.body) return cache;
    throw new Error('github-' + response.status);
  }
  cache = { at: Date.now(), body, status: 200 };
  return cache;
}

function serveStatic(req, res, pathname) {
  let rel = decodeURIComponent(pathname);
  if (rel === '/' || rel === '') rel = '/index.html';
  const target = path.resolve(ROOT, '.' + rel);
  if (!target.startsWith(path.resolve(ROOT) + path.sep) && target !== path.resolve(ROOT)) {
    res.writeHead(403, { 'Content-Type': 'text/plain' });
    res.end('Forbidden');
    return;
  }
  fs.stat(target, (err, stat) => {
    if (err || !stat.isFile()) {
      res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
      res.end('Not found');
      return;
    }
    const ext = path.extname(target).toLowerCase();
    const isHtml = ext === '.html';
    res.writeHead(200, {
      'Content-Type': MIME[ext] || 'application/octet-stream',
      'Cache-Control': isHtml ? 'public, max-age=60' : 'public, max-age=3600',
      'Content-Length': stat.size,
      'X-Content-Type-Options': 'nosniff'
    });
    fs.createReadStream(target).pipe(res);
  });
}

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, 'http://localhost');
    if (url.pathname === '/api/releases') {
      try {
        const result = await getReleases();
        res.writeHead(200, {
          'Content-Type': 'application/json; charset=utf-8',
          'Cache-Control': 'public, max-age=300',
          'Content-Length': Buffer.byteLength(result.body)
        });
        res.end(result.body);
      } catch (error) {
        sendJson(res, 502, { error: String(error.message || error) });
      }
      return;
    }
    if (url.pathname === '/healthz') {
      sendJson(res, 200, { ok: true, repo: REPO, cached: !!cache.body });
      return;
    }
    if (req.method !== 'GET' && req.method !== 'HEAD') {
      res.writeHead(405, { 'Content-Type': 'text/plain' });
      res.end('Method not allowed');
      return;
    }
    serveStatic(req, res, url.pathname);
  } catch (error) {
    sendJson(res, 500, { error: 'internal' });
  }
});

server.listen(PORT, HOST, () => {
  console.log('[landing] listening on http://' + HOST + ':' + PORT + ' root=' + ROOT + ' repo=' + REPO);
});
