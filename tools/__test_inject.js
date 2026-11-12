// Smoke test for the embedded installer injection (packaging-time step).
// Usage: node __test_inject.js   (safe: operates on COPIES in %TEMP%)
'use strict';
const fs = require('fs');
const fsp = fs.promises;
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const worker = require('C:/BetterDeskConsole/services/clientTemplateWorker.js');
const inject = worker._internals.injectEmbeddedInstallers;
if (typeof inject !== 'function') throw new Error('injectEmbeddedInstallers not exported');

const SRC = 'C:/BetterDeskConsole/data/modules/betterdesk-client-builder/outputs/94cabccb2bf1809a945bb1611b84fe3524090c36efb94623';
const FILES = [
    { name: 'betterdesk-support-94cabccb2bf1809a945bb1611b84fe3524090c36efb94623-windows-x86_64.zip', platform: 'windows', arch: 'x64', format: 'portable', check: 'zip' },
    { name: 'betterdesk-support-94cabccb2bf1809a945bb1611b84fe3524090c36efb94623-linux-x86_64.tar.gz', platform: 'linux', arch: 'x64', format: 'portable', check: 'tar' },
    { name: 'betterdesk-support-94cabccb2bf1809a945bb1611b84fe3524090c36efb94623-macos-aarch64.tar.gz', platform: 'macos', arch: 'arm64', format: 'portable', check: 'tar' },
];
const BRANDING = { install_service: true, autostart: true };

(async () => {
    const tmp = await fsp.mkdtemp(path.join(os.tmpdir(), 'bd-inject-'));
    let failed = false;
    for (const spec of FILES) {
        const src = path.join(SRC, spec.name);
        const dst = path.join(tmp, spec.name);
        await fsp.copyFile(src, dst);
        const t0 = Date.now();
        await inject(dst, { platform: spec.platform, arch: spec.arch, format: spec.format }, BRANDING);
        const secs = ((Date.now() - t0) / 1000).toFixed(1);
        let listing = '';
        if (spec.check === 'zip') {
            const r = spawnSync('tar', ['-tf', dst], { encoding: 'utf8' });
            listing = r.stdout || '';
        } else {
            const r = spawnSync('tar', ['-tzf', dst], { encoding: 'utf8' });
            listing = r.stdout || '';
        }
        const hasInstall = /(^|\/)Install-BetterDesk\.ps1$|(^|\/)install-betterdesk-support\.sh$/m.test(listing);
        const hasUninstall = /(^|\/)Uninstall-BetterDesk\.ps1$|(^|\/)uninstall-betterdesk-support\.sh$/m.test(listing);
        const size = (fs.statSync(dst).size / 1048576).toFixed(1);
        console.log(`${spec.platform}: ${secs}s size=${size}MB install=${hasInstall} uninstall=${hasUninstall}`);
        if (!hasInstall || !hasUninstall) {
            failed = true;
            console.log('  FAILED listing head:\n' + listing.split('\n').slice(0, 15).join('\n'));
        }
        if (spec.check === 'tar') {
            const r = spawnSync('tar', ['-tvzf', dst], { encoding: 'utf8' });
            if (r.status !== 0) { failed = true; console.log('  tar -t FAILED: ' + String(r.stderr).split('\n')[0]); }
            const lines = String(r.stdout || '').split('\n');
            const script = lines.find((l) => l.includes('install-betterdesk-support.sh'));
            const bin = lines.find((l) => /\/betterdesk\s*$/.test(l.trimEnd()) || l.includes('.app/Contents/MacOS/'));
            console.log('  script-mode: ' + (script ? script.substring(0, 20) : 'NOT FOUND'));
            console.log('  app-entry  : ' + (bin ? bin.trimEnd().substring(0, 70) : 'NOT FOUND'));
        }
        // idempotency: second injection must not duplicate entries
        await inject(dst, { platform: spec.platform, arch: spec.arch, format: spec.format }, BRANDING);
        const relist = spec.check === 'zip'
            ? spawnSync('tar', ['-tf', dst], { encoding: 'utf8' }).stdout
            : spawnSync('tar', ['-tzf', dst], { encoding: 'utf8' }).stdout;
        const instCount = String(relist || '').split(/\r?\n/)
            .filter((l) => /(^|\/)(Install-BetterDesk\.ps1|install-betterdesk-support\.sh)$/.test(l.trim())).length;
        if (instCount !== 1) { failed = true; console.log(`  DUPLICATE entries after re-inject: count=${instCount}`); }
    }
    console.log(failed ? 'RESULT: FAIL' : 'RESULT: PASS');
    process.exit(failed ? 1 : 0);
})().catch((e) => { console.error('ERROR:', e.message); process.exit(2); });
