/**
 * BetterDesk Console - Landing Release Service
 *
 * Resolves the correct BetterDesk client binary for a visitor's device so the
 * public "join meeting" landing page can offer one-click, zero-config downloads.
 *
 * Two sources, in priority order:
 *   1. GitHub releases of LANDING_GITHUB_OWNER/LANDING_GITHUB_REPO (freshest,
 *      when client builds are published as release assets).
 *   2. Repo-bundled pre-built clients under distro/clients/** (the signed
 *      Android APKs, Windows NSIS/MSI, Linux .deb/.rpm that ship in the tree).
 *
 * Downloads are backend-proxied (no CORS / rate-limit pain in the browser) and
 * only whitelisted assets are ever streamed — never an arbitrary URL (no SSRF).
 *
 * Config:
 *   LANDING_GITHUB_OWNER  (default: fingod201-maker)
 *   LANDING_GITHUB_REPO   (default: BetterDesk-private)
 *   UPDATE_GITHUB_TOKEN | GITHUB_TOKEN  (optional, raises API rate limit)
 *   LANDING_DISTRO_DIR    (optional, override distro/clients path)
 *
 * @module services/landingReleaseService
 */

'use strict';

const fs = require('fs');
const path = require('path');
const https = require('https');

const GITHUB_OWNER = process.env.LANDING_GITHUB_OWNER || 'fingod201-maker';
const GITHUB_REPO = process.env.LANDING_GITHUB_REPO || 'BetterDesk-private';
const GITHUB_API = 'https://api.github.com';
const GITHUB_TOKEN = process.env.UPDATE_GITHUB_TOKEN
    || process.env.GITHUB_TOKEN
    || process.env.BETTERDESK_GITHUB_TOKEN
    || '';

// web-nodejs/services/ → repo root is two levels up (works for checkout + flat).
const DISTRO_ROOT = process.env.LANDING_DISTRO_DIR
    || path.resolve(__dirname, '..', '..', 'distro', 'clients');

const CACHE_TTL_MS = Number(process.env.LANDING_GITHUB_CACHE_MS) || 10 * 60 * 1000;
const USER_AGENT = 'BetterDesk-Landing/1.0';

/** Canonical platforms surfaced by the landing page. */
const PLATFORMS = Object.freeze(['windows', 'macos', 'linux', 'android', 'ios']);

let _cache = { expires: 0, data: null };

// ---------------------------------------------------------------------------
// HTTP helpers
// ---------------------------------------------------------------------------

function httpsGetJson(urlPath) {
    return new Promise((resolve, reject) => {
        const url = urlPath.startsWith('https://') ? new URL(urlPath) : new URL(urlPath, GITHUB_API);
        const headers = { 'User-Agent': USER_AGENT, Accept: 'application/vnd.github+json' };
        if (GITHUB_TOKEN) headers.Authorization = `Bearer ${GITHUB_TOKEN}`;

        const req = https.get({ hostname: url.hostname, path: url.pathname + url.search, headers }, (res) => {
            if (res.statusCode === 301 || res.statusCode === 302) {
                res.resume();
                return resolve(httpsGetJson(res.headers.location));
            }
            const chunks = [];
            res.on('data', (c) => chunks.push(c));
            res.on('end', () => {
                const body = Buffer.concat(chunks).toString();
                if (res.statusCode >= 400) {
                    const err = new Error(`GitHub API ${res.statusCode}`);
                    err.statusCode = res.statusCode;
                    return reject(err);
                }
                try {
                    resolve(JSON.parse(body));
                } catch (_e) {
                    reject(new Error('Invalid JSON from GitHub API'));
                }
            });
        });
        req.on('error', reject);
        req.setTimeout(15000, () => { req.destroy(); reject(new Error('GitHub API timeout')); });
    });
}

// ---------------------------------------------------------------------------
// Asset classification
// ---------------------------------------------------------------------------

const EXT_MAP = {
    '.exe': { format: 'exe', platform: 'windows', contentType: 'application/x-msdownload' },
    '.msi': { format: 'msi', platform: 'windows', contentType: 'application/x-msdownload' },
    '.dmg': { format: 'dmg', platform: 'macos', contentType: 'application/x-apple-diskimage' },
    '.pkg': { format: 'pkg', platform: 'macos', contentType: 'application/octet-stream' },
    '.deb': { format: 'deb', platform: 'linux', contentType: 'application/vnd.debian.binary-package' },
    '.rpm': { format: 'rpm', platform: 'linux', contentType: 'application/x-rpm' },
    '.appimage': { format: 'appimage', platform: 'linux', contentType: 'application/octet-stream' },
    '.apk': { format: 'apk', platform: 'android', contentType: 'application/vnd.android.package-archive' },
    '.aab': { format: 'aab', platform: 'android', contentType: 'application/octet-stream' },
};

/** Detect CPU architecture. Defaults to x64 when unknown. */
function classifyArch(name) {
    const n = name.toLowerCase();
    if (/arm64|aarch64|armv8|arm64-v8a/.test(n)) return 'arm64';
    if (/armeabi|armv7|arm32/.test(n)) return 'arm32';
    if (/universal/.test(n)) return 'universal';
    if (/x64|amd64|x86_64/.test(n)) return 'x64';
    if (/ia32|x86(?!_64)/.test(n)) return 'x86';
    return 'x64';
}

/**
 * Classify an asset file name into { platform, arch, format, contentType } or null.
 * Ignores checksums, manifests and signature sidecars.
 */
function classifyAsset(name) {
    if (!name) return null;
    const lower = name.toLowerCase();
    if (/\.(sha256|sha512|sig|asc|json|md|txt|example)$/.test(lower)) return null;
    if (/checksums?/.test(lower)) return null;

    const dot = lower.lastIndexOf('.');
    const ext = dot >= 0 ? lower.slice(dot) : '';
    const mapped = EXT_MAP[ext];
    if (!mapped) return null;

    return {
        platform: mapped.platform,
        format: mapped.format,
        arch: classifyArch(name),
        contentType: mapped.contentType,
    };
}

/** Rank a format so the most "installer-like" asset wins ties. */
function formatRank(format) {
    switch (format) {
        case 'msi': case 'pkg': case 'deb': case 'apk': return 0;
        case 'exe': case 'dmg': case 'appimage': return 1;
        case 'rpm': return 2;
        default: return 5;
    }
}

/** Prefer installer/portable client names over sidecar binaries. */
function nameScore(name) {
    const n = String(name || '').toLowerCase();
    let s = 0;
    if (/setup|installer/.test(n)) s += 4;
    if (/\bclient\b/.test(n)) s += 3;
    if (/release/.test(n)) s += 2;
    if (/universal/.test(n)) s += 2;
    if (/arm64|v8a|amd64|x86_64|x64/.test(n)) s += 1;
    if (/agent\.(exe|deb|rpm)$/.test(n)) s -= 2; // sidecar binary, not the client
    if (/nssm/.test(n)) s -= 10;
    return s;
}

function downloadPathFor(asset) {
    const qs = new URLSearchParams({ platform: asset.platform, arch: asset.arch, format: asset.format, source: asset.source });
    return `/landing/download?${qs.toString()}`;
}

// ---------------------------------------------------------------------------
// Sources
// ---------------------------------------------------------------------------

async function fetchGithubAssets() {
    let releases = [];
    try {
        releases = await httpsGetJson(`/repos/${GITHUB_OWNER}/${GITHUB_REPO}/releases?per_page=30`);
    } catch (err) {
        if (err.statusCode && err.statusCode !== 404) {
            console.warn(`[landing] release lookup failed: ${err.message}`);
        }
    }

    const usable = (Array.isArray(releases) ? releases : []).filter((r) => r && r.draft !== true);
    const stable = usable.filter((r) => r.prerelease !== true);
    // Newest first (GitHub returns releases in reverse chronological order).
    const ordered = stable.length ? stable : usable;
    const release = ordered[0] || null;

    // Merge assets across recent releases so an Android-only (or desktop-only)
    // release never hides the other platforms. Newer releases win.
    const byKey = new Map();
    ordered.forEach((rel, releaseIndex) => {
        if (!rel || !Array.isArray(rel.assets)) return;
        for (const a of rel.assets) {
            const meta = classifyAsset(a.name);
            if (!meta) continue;
            const key = `${meta.platform}/${meta.arch}/${meta.format}`;
            const current = byKey.get(key);
            const better = !current
                || releaseIndex < current.releaseIndex
                || (releaseIndex === current.releaseIndex
                    && nameScore(a.name) > nameScore(current.name));
            if (better) {
                byKey.set(key, {
                    name: a.name,
                    size: a.size,
                    platform: meta.platform,
                    arch: meta.arch,
                    format: meta.format,
                    contentType: a.content_type || meta.contentType,
                    source: 'github',
                    url: GITHUB_TOKEN ? (a.url || a.browser_download_url) : a.browser_download_url,
                    releaseIndex,
                    releaseTag: rel.tag_name,
                });
            }
        }
    });

    return {
        release: release ? {
            tag: release.tag_name,
            name: release.name,
            publishedAt: release.published_at,
            htmlUrl: release.html_url,
            releasesUrl: `https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/releases`,
        } : null,
        assets: [...byKey.values()],
    };
}

/** Recursively scan distro/clients for downloadable custom builds. */
function scanDistroAssets() {
    const assets = [];
    let stack = [];
    try {
        if (!fs.existsSync(DISTRO_ROOT)) return assets;
        stack = [DISTRO_ROOT];
        while (stack.length) {
            const dir = stack.pop();
            let entries;
            try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch (_e) { continue; }
            for (const ent of entries) {
                const full = path.join(dir, ent.name);
                if (ent.isDirectory()) { stack.push(full); continue; }
                if (!ent.isFile()) continue;
                const meta = classifyAsset(ent.name);
                if (!meta) continue;
                let stat;
                try { stat = fs.statSync(full); } catch (_e) { continue; }
                assets.push({
                    name: ent.name,
                    size: stat.size,
                    platform: meta.platform,
                    arch: meta.arch,
                    format: meta.format,
                    contentType: meta.contentType,
                    source: 'distro',
                    absPath: full,
                });
            }
        }
    } catch (err) {
        console.warn(`[landing] distro scan failed: ${err.message}`);
    }
    return assets;
}

/** Merge sources, deduping by key with GitHub preferred, then name score. */
function mergeAssets(github, distro) {
    const byKey = new Map();
    const consider = (asset) => {
        const key = `${asset.platform}/${asset.arch}/${asset.format}`;
        const cur = byKey.get(key);
        if (!cur) { byKey.set(key, asset); return; }
        const srcRank = (a) => (a.source === 'github' ? 0 : 1);
        const score = (a) => -(nameScore(a.name));
        const better = srcRank(asset) < srcRank(cur)
            || (srcRank(asset) === srcRank(cur)) && (nameScore(asset.name) > nameScore(cur.name));
        if (better) byKey.set(key, asset);
    };
    github.forEach(consider);
    distro.forEach(consider);

    const assets = [...byKey.values()].map((a) => ({ ...a, downloadPath: downloadPathFor(a) }));
    const assetsByKey = {};
    for (const a of assets) assetsByKey[`${a.platform}/${a.arch}/${a.format}`] = a;
    return { assets, assetsByKey };
}

// ---------------------------------------------------------------------------
// Release index
// ---------------------------------------------------------------------------

/**
 * Build the cached index: latest release + merged (GitHub + distro) assets.
 * @returns {Promise<object>}
 */
async function getReleaseIndex({ bypassCache = false } = {}) {
    if (!bypassCache && _cache.data && _cache.expires > Date.now()) {
        return _cache.data;
    }

    const gh = await fetchGithubAssets();
    const distro = scanDistroAssets();
    const merged = mergeAssets(gh.assets, distro);

    const data = {
        owner: GITHUB_OWNER,
        repo: GITHUB_REPO,
        tag: gh.release ? gh.release.tag : null,
        name: gh.release ? gh.release.name : null,
        publishedAt: gh.release ? gh.release.publishedAt : null,
        htmlUrl: gh.release ? gh.release.htmlUrl : `https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/releases`,
        releasesUrl: `https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/releases`,
        assets: merged.assets,
        assetsByKey: merged.assetsByKey,
        sources: { github: gh.assets.length, distro: distro.length },
    };

    _cache = { expires: Date.now() + CACHE_TTL_MS, data };
    return data;
}

/**
 * Resolve the best asset for a platform (+ optional arch).
 * GitHub assets are preferred; the repo-bundled distro build is the fallback.
 */
async function resolveAsset(platform, arch) {
    if (!platform || !PLATFORMS.includes(platform)) return null;
    const index = await getReleaseIndex();
    const candidates = index.assets.filter((a) => a.platform === platform);
    if (candidates.length === 0) return null;

    const score = (a) => (a.source === 'github' ? 0 : 1);
    const pickFrom = (list) => [...list].sort((a, b) => {
        if (score(a) !== score(b)) return score(a) - score(b);
        const archPenalty = (x) => (arch && x.arch === arch ? 0 : x.arch === 'universal' ? 1 : x.arch === 'x64' ? 2 : 3);
        if (archPenalty(a) !== archPenalty(b)) return archPenalty(a) - archPenalty(b);
        return formatRank(a.format) - formatRank(b.format);
    })[0];

    if (arch === 'universal') {
        const uni = candidates.filter((a) => a.arch === 'universal');
        if (uni.length) return pickFrom(uni);
        // No universal build: fall back to the most common 64-bit Android ABI.
        const arm64 = candidates.filter((a) => a.arch === 'arm64');
        if (arm64.length) return pickFrom(arm64);
        return pickFrom(candidates);
    }
    if (arch) {
        const exact = candidates.filter((a) => a.arch === arch);
        if (exact.length) return pickFrom(exact);
    }
    const universal = candidates.filter((a) => a.arch === 'universal');
    if (universal.length) return pickFrom(universal);
    return pickFrom(candidates);
}

/**
 * Resolve a specific asset by exact key (platform/arch/format).
 * @returns {Promise<object|null>}
 */
async function resolveAssetByKey(platform, arch, format) {
    const index = await getReleaseIndex();
    const a = arch || 'x64';
    return index.assetsByKey[`${platform}/${a}/${format}`]
        || index.assetsByKey[`${platform}/${arch}/${format}`]
        || null;
}

// ---------------------------------------------------------------------------
// Streaming
// ---------------------------------------------------------------------------

function streamLocalFile(asset, res) {
    return new Promise((resolve, reject) => {
        res.setHeader('Content-Type', asset.contentType || 'application/octet-stream');
        res.setHeader('Content-Length', String(asset.size));
        res.setHeader('Content-Disposition', `attachment; filename="${asset.name}"`);
        const stream = fs.createReadStream(asset.absPath);
        stream.on('error', reject);
        stream.on('end', resolve);
        stream.pipe(res);
    });
}

function streamRemoteAsset(asset, res) {
    return new Promise((resolve, reject) => {
        const baseHeaders = { 'User-Agent': USER_AGENT, Accept: 'application/octet-stream' };
        if (GITHUB_TOKEN) baseHeaders.Authorization = `Bearer ${GITHUB_TOKEN}`;

        const follow = (target, withAuth = true) => {
            const headers = { ...baseHeaders };
            if (!withAuth) delete headers.Authorization;
            const req = https.get(target, { headers }, (upstream) => {
                if ((upstream.statusCode === 301 || upstream.statusCode === 302) && upstream.headers.location) {
                    upstream.resume();
                    return follow(upstream.headers.location, false);
                }
                if (upstream.statusCode !== 200) {
                    upstream.resume();
                    return reject(new Error(`Upstream ${upstream.statusCode}`));
                }
                res.setHeader('Content-Type', asset.contentType || 'application/octet-stream');
                if (upstream.headers['content-length']) {
                    res.setHeader('Content-Length', upstream.headers['content-length']);
                } else if (asset.size) {
                    res.setHeader('Content-Length', String(asset.size));
                }
                res.setHeader('Content-Disposition', `attachment; filename="${asset.name}"`);
                res.setHeader('Cache-Control', 'public, max-age=600');
                upstream.pipe(res);
                upstream.on('end', resolve);
                upstream.on('error', reject);
            });
            req.on('error', reject);
            req.setTimeout(120000, () => { req.destroy(); reject(new Error('Download timeout')); });
        };
        follow(asset.url);
    });
}

/** Stream an asset (local distro file or remote GitHub asset) to a response. */
function streamAsset(asset, res) {
    if (asset.source === 'distro' && asset.absPath) {
        return streamLocalFile(asset, res);
    }
    return streamRemoteAsset(asset, res);
}

module.exports = {
    PLATFORMS,
    DISTRO_ROOT,
    getReleaseIndex,
    resolveAsset,
    resolveAssetByKey,
    classifyAsset,
    classifyArch,
    streamAsset,
    get owner() { return GITHUB_OWNER; },
    get repo() { return GITHUB_REPO; },
};
