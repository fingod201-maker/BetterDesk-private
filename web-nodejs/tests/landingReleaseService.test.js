'use strict';

/**
 * Landing page release resolution — OS auto-detect download mapping.
 *
 * The public landing page detects the visitor OS/arch and asks the release
 * index for the matching client asset. Portable zip bundles (client + install
 * script) are preferred over raw binaries so unsigned builds still install
 * cleanly on SmartScreen / Gatekeeper machines.
 */

const fs = require('fs');
const os = require('os');
const path = require('path');

const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'bd-landing-'));
for (const name of [
    'betterdesk-client-windows-x64.zip',
    'betterdesk-client-linux-x64.zip',
    'betterdesk-client-macos-universal.zip',
    'BetterDesk Agent_1.0.0_x64-setup.exe',
    'BetterDesk Agent_1.0.0_amd64.deb',
    'CHECKSUMS.sha256',
    'random.zip',
]) {
    fs.writeFileSync(path.join(tmpDir, name), 'x');
}

process.env.LANDING_DISTRO_DIR = tmpDir;

const landing = require('../services/landingReleaseService');

afterAll(() => {
    try { fs.rmSync(tmpDir, { recursive: true, force: true }); } catch (_e) { /* ignore */ }
});

describe('landing release asset classification', () => {
    test('classifies a Windows zip bundle', () => {
        const meta = landing.classifyAsset('betterdesk-client-windows-x64.zip');
        expect(meta).toMatchObject({ platform: 'windows', format: 'zip', arch: 'x64' });
    });

    test('classifies a macOS universal zip bundle', () => {
        const meta = landing.classifyAsset('betterdesk-client-macos-universal.zip');
        expect(meta).toMatchObject({ platform: 'macos', format: 'zip', arch: 'universal' });
    });

    test('classifies a Linux zip bundle', () => {
        const meta = landing.classifyAsset('betterdesk-client-linux-x64.zip');
        expect(meta).toMatchObject({ platform: 'linux', format: 'zip', arch: 'x64' });
    });

    test('ignores a zip without any platform hint', () => {
        expect(landing.classifyAsset('random.zip')).toBeNull();
    });

    test('ignores checksums and signature sidecars', () => {
        expect(landing.classifyAsset('client.exe.sha256')).toBeNull();
        expect(landing.classifyAsset('client.exe.asc')).toBeNull();
    });

    test('still classifies native installers', () => {
        expect(landing.classifyAsset('BetterDesk Agent_1.0.0_x64-setup.exe'))
            .toMatchObject({ platform: 'windows', format: 'exe' });
        expect(landing.classifyAsset('BetterDesk Agent_1.0.0_amd64.deb'))
            .toMatchObject({ platform: 'linux', format: 'deb' });
    });
});

describe('landing auto-detect resolution', () => {
    test('resolves the Windows bundle for a Windows visitor', async () => {
        const asset = await landing.resolveAsset('windows', 'x64');
        expect(asset).not.toBeNull();
        expect(asset.platform).toBe('windows');
        expect(asset.downloadPath).toContain('platform=windows');
    });

    test('resolves the universal macOS bundle for an Apple Silicon visitor', async () => {
        const asset = await landing.resolveAsset('macos', 'arm64');
        expect(asset).not.toBeNull();
        expect(asset.platform).toBe('macos');
        expect(asset.arch).toBe('universal');
    });

    test('resolves the Linux bundle for a Linux visitor', async () => {
        const asset = await landing.resolveAsset('linux', 'x64');
        expect(asset).not.toBeNull();
        expect(asset.platform).toBe('linux');
    });

    test('prefers the portable zip bundle over the raw installer', async () => {
        const asset = await landing.resolveAsset('windows', 'x64');
        expect(asset.format).toBe('zip');
    });
});
