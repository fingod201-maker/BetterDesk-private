const fs = require('fs');
const path = require('path');

const consoleDir = 'C:\\BetterDeskConsole';
const envPath = path.join(consoleDir, '.env');
const tokenFile = 'c:\\Users\\milaz\\BetterDesk\\tools\\.bd_token_tmp';

const token = fs.readFileSync(tokenFile, 'utf8').trim();
if (!/^github_pat_[A-Za-z0-9_]+$/.test(token)) {
    console.error('TOKEN_INVALID len=' + token.length);
    process.exit(1);
}
console.log('token len=' + token.length);

let check = fs.readFileSync(envPath, 'utf8').replace(/\r\n/g, '\n');
let lines = check.split('\n');
const re = /^BETTERDESK_GITHUB_TOKEN=/;
let found = false;
for (let i = 0; i < lines.length; i++) {
    if (re.test(lines[i])) { lines[i] = 'BETTERDESK_GITHUB_TOKEN=' + token; found = true; break; }
}
if (!found) lines.push('BETTERDESK_GITHUB_TOKEN=' + token);

let out = lines.join('\r\n');
if (!out.endsWith('\r\n')) out += '\r\n';
fs.writeFileSync(envPath, out, { encoding: 'utf8' });

const verify = fs.readFileSync(envPath, 'utf8');
const ghToken = (verify.match(/^BETTERDESK_GITHUB_TOKEN=(.*)$/m) || [])[1] || '';
const ghActions = (verify.match(/^BETTERDESK_CLIENT_GITHUB_ACTIONS=(.*)$/m) || [])[1];
console.log('TOKEN_len_in_env=' + ghToken.trim().length);
console.log('GITHUB_ACTIONS=' + ghActions);
console.log('TOKEN_FIX_OK');

