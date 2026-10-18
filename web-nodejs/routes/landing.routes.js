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

const express = require('express');
const router = express.Router();
const landing = require('../services/landingReleaseService');

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
    if (chArch === 'arm' || chArch === 'arm64') arch = 'arm64';
    else if (platform === 'macos') arch = 'arm64';
    else if (platform === 'android') arch = 'arm64';

    const labels = {
        windows: 'Windows', macos: 'macOS', linux: 'Linux',
        android: 'Android', ios: 'iPhone / iPad', unknown: 'your device',
    };

    const mobile = chMobile || /mobile|android|iphone|ipad/.test(lower);

    return { platform, arch, mobile, label: labels[platform] || labels.unknown };
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
