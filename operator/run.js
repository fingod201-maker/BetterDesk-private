'use strict';

/**
 * Browser operator for LinkedIn / Facebook.
 *
 * LinkedIn has no public DM API for personal accounts, so this drives a real
 * logged-in Chromium profile. Log in manually once per platform; 2FA and
 * captchas are handled by the human, everything else runs from a queue.
 *
 * Usage:
 *   node run.js --platform linkedin --stage view    --queue queue.csv --max 15
 *   node run.js --platform linkedin --stage connect --queue queue.csv --max 15
 *   node run.js --platform linkedin --stage dm      --queue queue.csv --max 15
 *   node run.js --platform linkedin --stage check
 *   node run.js --platform facebook --stage view|dm --queue queue.csv
 *
 * Queue columns:
 *   connect: who,co,profile,note
 *   dm/view: who,co,profile[,message]
 * profile may be empty; the tool falls back to LinkedIn search on who+co.
 */

const fs = require('fs');
const path = require('path');
const readline = require('readline');
const { chromium } = require('playwright');

function arg(name, fallback) {
  const i = process.argv.indexOf('--' + name);
  return i > -1 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
}
function flag(name) { return process.argv.includes('--' + name); }

const platform = arg('platform', 'linkedin');
const stage = arg('stage', 'view');
const queueFile = arg('queue', '');
const max = parseInt(arg('max', '15'), 10);
const dry = flag('dry');
const profileDir = path.resolve(arg('profile', 'profile-' + platform));
const outDir = path.resolve('out');
fs.mkdirSync(outDir, { recursive: true });
fs.mkdirSync(profileDir, { recursive: true });

const statusFile = path.join(outDir, 'status-' + platform + '.csv');
if (!fs.existsSync(statusFile)) {
  fs.writeFileSync(statusFile, 'ts,platform,stage,who,co,result,detail\n');
}

function log(...a) { console.log(new Date().toISOString().slice(11, 19), ...a); }
function rnd(min, max) { return min + Math.floor(Math.random() * (max - min)); }
async function human(min, max) { return new Promise((r) => setTimeout(r, rnd(min, max))); }

function parseCsv(file) {
  const text = fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '');
  const lines = text.split(/\r?\n/).filter((l) => l.trim());
  const head = splitCsv(lines.shift());
  return lines.map((l) => {
    const cells = splitCsv(l);
    const row = {};
    head.forEach((h, i) => { row[h.trim()] = (cells[i] || '').trim(); });
    return row;
  });
}
function splitCsv(line) {
  const out = [];
  let cur = '';
  let q = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (ch === '"') {
      if (q && line[i + 1] === '"') { cur += '"'; i++; }
      else q = !q;
    } else if (ch === ',' && !q) { out.push(cur); cur = ''; }
    else cur += ch;
  }
  out.push(cur);
  return out;
}
function record(row, result, detail) {
  const esc = (v) => '"' + String(v || '').replace(/"/g, '""') + '"';
  fs.appendFileSync(statusFile,
    [new Date().toISOString(), platform, stage, row.who, row.co, result, detail || '']
      .map(esc).join(',') + '\n');
}

function waitEnter(text) {
  return new Promise((resolve) => {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    rl.question(text, () => { rl.close(); resolve(); });
  });
}

async function firstVisible(page, selectors) {
  for (const sel of selectors) {
    const loc = typeof sel === 'string' ? page.locator(sel) : sel;
    try {
      const n = await loc.count();
      for (let i = 0; i < Math.min(n, 4); i++) {
        const el = loc.nth(i);
        if (await el.isVisible().catch(() => false)) return el;
      }
    } catch { /* next */ }
  }
  return null;
}

async function ensureLogin(page, home, loginNeedle) {
  await page.goto(home, { waitUntil: 'domcontentloaded' }).catch(() => {});
  await human(2500, 4000);
  if (!page.url().includes(loginNeedle)) return;
  log('NOT LOGGED IN - log in in this window; waiting up to 60 minutes');
  const deadline = Date.now() + 60 * 60 * 1000;
  while (page.url().includes(loginNeedle)) {
    if (Date.now() > deadline) throw new Error('login timeout');
    await human(3500, 4000);
  }
  log('login ok');
}

async function captchaCheck(page) {
  const deadline = Date.now() + 10 * 60 * 1000;
  let told = false;
  while (/checkpoint|challenge|captcha|authwall/.test(page.url())) {
    if (!told) { log('CAPTCHA - solve it in the window; waiting 10 minutes'); told = true; }
    if (Date.now() > deadline) throw new Error('captcha timeout');
    await human(3500, 4000);
  }
}
async function openProfile(page, row) {
  if (row.profile) {
    await page.goto(row.profile, { waitUntil: 'domcontentloaded' });
  } else {
    const q = encodeURIComponent(row.who + ' ' + row.co);
    await page.goto('https://www.linkedin.com/search/results/people/?keywords=' + q,
      { waitUntil: 'domcontentloaded' });
    await human(2500, 4000);
    const link = page.locator('a[href*="/in/"]').first();
    if (await link.count()) {
      const href = await link.getAttribute('href');
      await page.goto(href.split('?')[0], { waitUntil: 'domcontentloaded' });
    }
  }
  await human(2000, 3500);
  await page.mouse.wheel(0, rnd(300, 700));
  await human(1200, 2200);
}

async function linkedinConnect(page, row) {
  let btn = await firstVisible(page, [
    page.getByRole('button', { name: /^Connect$/i }),
    page.getByRole('link', { name: /^Connect$/i }),
    page.locator('button:has-text("Connect")'),
  ]);
  if (!btn) {
    const more = await firstVisible(page, [
      page.getByRole('button', { name: /^More$/i }),
      page.locator('button:has-text("More actions")'),
    ]);
    if (more) {
      await more.click();
      await human(500, 900);
      btn = await firstVisible(page, [
        page.locator('div[role="menu"] >> text=/^Connect$/i'),
        page.locator('text=/^Connect$/i'),
      ]);
    }
  }
  if (!btn) return record(row, 'no-connect-button');
  await btn.click();
  await human(700, 1200);

  if (row.note) {
    const addNote = await firstVisible(page, [
      page.getByRole('button', { name: /add a note/i }),
      page.locator('button:has-text("Add a note")'),
    ]);
    if (addNote) { await addNote.click(); await human(500, 900); }
    const box = await firstVisible(page, [
      page.locator('textarea'),
      page.locator('div[contenteditable="true"]'),
    ]);
    if (box) { await box.fill(row.note); await human(500, 900); }
  }

  const send = await firstVisible(page, [
    page.getByRole('button', { name: /^Send$/i }),
    page.locator('button:has-text("Send")'),
    page.locator('button:has-text("Send invitation")'),
  ]);
  if (!send) return record(row, 'no-send-button');
  await send.click();
  await human(700, 1200);
  return record(row, 'sent');
}

async function linkedinDm(page, row) {
  const msg = await firstVisible(page, [
    page.getByRole('button', { name: /^Message$/i }),
    page.getByRole('link', { name: /^Message$/i }),
    page.locator('button:has-text("Message")'),
  ]);
  if (!msg) return record(row, 'no-message-button', 'not connected?');
  await msg.click();
  await human(1200, 2200);
  const box = await firstVisible(page, [
    page.locator('div[contenteditable="true"]'),
    page.locator('textarea'),
  ]);
  if (!box) return record(row, 'no-composer');
  await box.click();
  await box.type(row.message || row.note || '', { delay: rnd(10, 30) });
  await human(400, 900);
  const send = await firstVisible(page, [
    page.getByRole('button', { name: /^Send$/i }),
    page.locator('button:has-text("Send")'),
  ]);
  if (send) await send.click();
  else await page.keyboard.press('Enter');
  await human(700, 1200);
  return record(row, 'sent');
}

async function facebookDm(page, row) {
  const msg = await firstVisible(page, [
    page.getByRole('link', { name: /^Message$/i }),
    page.locator('a:has-text("Message")'),
    page.getByRole('button', { name: /^Message$/i }),
  ]);
  if (!msg) return record(row, 'no-message-button');
  await msg.click();
  await human(1500, 2600);
  const box = await firstVisible(page, [
    page.locator('div[contenteditable="true"]'),
    page.locator('textarea'),
  ]);
  if (!box) return record(row, 'no-composer');
  await box.click();
  await box.type(row.message || '', { delay: rnd(10, 30) });
  await human(400, 900);
  await page.keyboard.press('Enter');
  await human(700, 1200);
  return record(row, 'sent');
}

async function acceptedScan(page, rows) {
  await page.goto('https://www.linkedin.com/mynetwork/invite-connect/connections/',
    { waitUntil: 'domcontentloaded' });
  for (let i = 0; i < 4; i++) { await page.mouse.wheel(0, 1600); await human(1200, 2000); }
  const names = (await page.locator('span[dir="ltr"]').allInnerTexts()).map((s) => s.toLowerCase());
  for (const row of rows) {
    const hit = names.some((n) => n.includes(row.who.toLowerCase()) && n.length < 80);
    if (hit) record(row, 'accepted');
  }
  log('scan done');
}

(async () => {
  if (!queueFile && stage !== 'check') throw new Error('--queue required');
  const rows = queueFile ? parseCsv(queueFile).slice(0, max) : [];
  const browser = await chromium.launchPersistentContext(profileDir, {
    headless: false,
    viewport: { width: 1360, height: 900 },
    locale: 'en-US',
    timezoneId: platform === 'linkedin' ? 'America/New_York' : 'America/New_York',
    args: ['--disable-blink-features=AutomationControlled'],
  });
  const page = browser.pages()[0] || (await browser.newPage());

  try {
    if (platform === 'linkedin') {
      await ensureLogin(page, 'https://www.linkedin.com/feed/', '/login');
      if (stage === 'check') { await acceptedScan(page, parseCsv(queueFile).slice(0, 400)); }
    } else {
      await ensureLogin(page, 'https://www.facebook.com/', '/login');
    }

    for (let i = 0; i < rows.length; i++) {
      const row = rows[i];
      log(`[${i + 1}/${rows.length}] ${stage} ${row.who} @ ${row.co}`);
      try {
        if (platform === 'linkedin') {
          if (stage === 'view') { await openProfile(page, row); record(row, 'viewed'); }
          else {
            await openProfile(page, row);
            if (stage === 'connect') await linkedinConnect(page, row);
            else if (stage === 'dm') await linkedinDm(page, row);
          }
        } else if (stage === 'view') {
          await page.goto('https://www.facebook.com/search/people/?q=' + encodeURIComponent(row.who + ' ' + row.co),
            { waitUntil: 'domcontentloaded' });
          await human(2500, 4000);
          record(row, 'viewed');
        } else if (stage === 'dm') {
          await page.goto(row.profile || ('https://www.facebook.com/search/people/?q=' +
            encodeURIComponent(row.who + ' ' + row.co)), { waitUntil: 'domcontentloaded' });
          await human(2500, 4000);
          await facebookDm(page, row);
        }
      } catch (e) {
        record(row, 'error', String(e.message || e).slice(0, 200));
        await page.screenshot({ path: path.join(outDir, `fail-${Date.now()}.png`) }).catch(() => {});
      }
      await captchaCheck(page);
      if (i < rows.length - 1) {
        const wait = stage === 'connect' ? rnd(40000, 85000)
          : stage === 'dm' ? rnd(25000, 50000) : rnd(7000, 14000);
        log(`wait ${(wait / 1000).toFixed(0)}s`);
        await human(wait, wait + 500);
      }
    }
  } finally {
    if (dry) { await waitEnter('Dry run done. Press Enter to close... '); }
    await browser.close();
  }
})().catch((e) => { console.error(e); process.exit(1); });
