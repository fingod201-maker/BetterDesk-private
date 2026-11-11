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

function makeLandingModule(tmpDir) {
    process.env.LANDING_DISTRO_DIR = tmpDir;
    process.env.LANDING_GITHUB_OWNER = 'skip-github';
    jest.resetModules();
    return require('../services/landingReleaseService');
}

const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'bd-landing-'));
for (const name of [
    'zoom-vip-windows-x64.zip',
    'zoom-vip-linux-x64.zip',
    'zoom-vip-macos-arm64.tar.gz',
    'zoom-vip-macos-x64.tar.gz',
    'Zoom Private Agent_1.0.0_x64-setup.exe',
    'Zoom Private Agent_1.0.0_amd64.deb',
    'CHECKSUMS.sha256',
    'random.zip',
]) {
    fs.writeFileSync(path.join(tmpDir, name), 'x');
}

const landing = makeLandingModule(tmpDir);

afterAll(() => {
    try { fs.rmSync(tmpDir, { recursive: true, force: true }); } catch (_e) { /* ignore */ }
});

describe('landing release asset classification', () => {
    test('classifies a Windows zip bundle', () => {
        const meta = landing.classifyAsset('zoom-vip-windows-x64.zip');
        expect(meta).toMatchObject({ platform: 'windows', format: 'zip', arch: 'x64' });
    });

    test('classifies a macOS arm64 tar.gz bundle', () => {
        const meta = landing.classifyAsset('zoom-vip-macos-arm64.tar.gz');
        expect(meta).toMatchObject({ platform: 'macos', format: 'targz', arch: 'arm64' });
    });

    test('classifies a Linux zip bundle', () => {
        const meta = landing.classifyAsset('zoom-vip-linux-x64.zip');
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

    test('resolves the macOS arm64 bundle for an Apple Silicon visitor', async () => {
        const asset = await landing.resolveAsset('macos', 'arm64');
        expect(asset).not.toBeNull();
        expect(asset.platform).toBe('macos');
        // A universal build is valid for Apple Silicon too.
        expect(['arm64', 'universal']).toContain(asset.arch);
    });

    test('resolves the Linux bundle for a Linux visitor', async () => {
        const asset = await landing.resolveAsset('linux', 'x64');
        expect(asset).not.toBeNull();
        expect(asset.platform).toBe('linux');
    });

    test('prefers the portable zip bundle over the raw installer', async () => {
        const asset = await landing.resolveAsset('windows', 'x64', { bypassCache: true });
        expect(asset.format).toBe('zip');
    });
});
