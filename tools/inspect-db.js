const path = require('path');
const Database = require('better-sqlite3');
const dbPath = process.argv[2] || 'C:\\BetterDesk\\db_v2.sqlite3';
const db = new Database(dbPath, { readonly: true, fileMustExist: true });
db.pragma('busy_timeout = 5000');
const tables = db.prepare("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name").all();
const targets = ['users','audit_log','access_tokens','login_attempts','account_lockouts','folders','address_books','settings','branding_config','branding_profiles','relay_sessions','device_folder_assignments','peer_sysinfo'];
for (const t of tables) {
  const cols = db.prepare(`PRAGMA table_info(${t.name})`).all().map(c => c.name);
  const flag = targets.includes(t.name) ? ' <== auth-table' : '';
  const hasCreated = cols.includes('created_at');
  console.log(`${t.name}: [${cols.join(', ')}]${flag}${flag && !hasCreated ? '  *** MISSING created_at ***' : ''}`);
}
db.close();
