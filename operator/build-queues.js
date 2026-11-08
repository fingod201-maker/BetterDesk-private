'use strict';

/** Build operator queues from docs/campaign-out.csv. */
const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const input = path.join(root, 'docs', 'campaign-out.csv');

function splitCsv(line) {
  const out = [];
  let cur = '';
  let q = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (ch === '"') {
      if (q && line[i + 1] === '"') { cur += '"'; i++; } else q = !q;
    } else if (ch === ',' && !q) { out.push(cur); cur = ''; } else cur += ch;
  }
  out.push(cur);
  return out;
}
function csv(rows, cols) {
  const esc = (v) => '"' + String(v || '').replace(/"/g, '""') + '"';
  return [cols.join(','), ...rows.map((r) => cols.map((c) => esc(r[c])).join(','))].join('\n') + '\n';
}

const text = fs.readFileSync(input, 'utf8').replace(/^\uFEFF/, '');
const lines = text.split(/\r?\n/).filter((l) => l.trim());
const head = splitCsv(lines.shift());
const rows = lines.map((l) => {
  const c = splitCsv(l);
  const r = {};
  head.forEach((h, i) => { r[h.trim()] = (c[i] || '').trim(); });
  return r;
});

function hook(row) {
  const s = row.sector || '';
  if (/ADP/.test(row.co)) return 'distributed payroll and benefits teams';
  if (/hospital/.test(s)) return 'unattended support for on-call staff';
  if (/real estate|property|design-build/.test(s)) return 'site and deal teams';
  if (/finance|accounting|CFO/.test(s)) return 'finance and on-call teams';
  if (/energy|oil/.test(s)) return 'field and finance teams';
  if (/shipping/.test(s)) return 'chartering and ops teams';
  if (/construction/.test(s)) return 'site and back-office teams';
  return s || 'operations teams';
}
function senior(row) { return /Chairman|Founder|CEO|President|Managing Director|Owner/i.test(row.title || ''); }

for (const r of rows) {
  if (!r.note) {
    r.note = senior(r)
      ? `Hi ${r.who} - ${r.co} keeps coming up in ${r.sector}. We are doing a short private review of remote-support paths for senior teams; six minutes, no account. Worth connecting?`
      : `Hi ${r.who} - following ${r.co}'s work in ${r.sector}. We are running a short private review of remote-support tooling with operators; six minutes, no account. Worth connecting?`;
  }
  if (!r.message) {
    r.message = `Thanks for connecting, ${r.who}. Short context: we are testing a lighter remote-support path for ${hook(r)} - one page, no account, no install calls. The page picks the right client for your machine. Six minutes if you will take it: ${r.link}`;
  }
}

const outDir = path.join(__dirname, 'out');
fs.mkdirSync(outDir, { recursive: true });
fs.writeFileSync(path.join(outDir, 'queue-connect.csv'), csv(rows, ['who', 'co', 'profile', 'note']));
fs.writeFileSync(path.join(outDir, 'queue-dm.csv'), csv(rows, ['who', 'co', 'profile', 'message']));
fs.writeFileSync(path.join(outDir, 'queue-view.csv'), csv(rows, ['who', 'co', 'profile']));
console.log('wrote out/queue-connect.csv, out/queue-dm.csv, out/queue-view.csv (' + rows.length + ' rows)');
console.log('Add profile URLs to docs/campaign-out.csv and re-run if search fallback is not good enough.');
