'use strict';

/**
 * BetterDesk Landing Service — Security Hardening Middleware
 *
 * Applies:
 *   - Strict security headers (HSTS, CSP, X-Frame-Options, etc.)
 *   - Per-IP rate limiting (downloads + API)
 *   - Request body size caps
 *   - CORS allowlist (default: same-origin only; configurable via env)
 *
 * Intended for the public landing service (zoom.telcom.stream) which is
 * internet-facing and serves client downloads to untrusted visitors.
 */

const rateLimit = require('express-rate-limit');

const ALLOWED_ORIGINS = (process.env.LANDING_ALLOWED_ORIGINS || '')
    .split(',')
    .map((o) => o.trim())
    .filter(Boolean);

/** General security headers for every response. */
function securityHeaders(req, res, next) {
    // Prevent clickjacking
    res.setHeader('X-Frame-Options', 'DENY');
    // Prevent MIME sniffing
    res.setHeader('X-Content-Type-Options', 'nosniff');
    // Referrer policy
    res.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
    // HSTS (only meaningful over HTTPS; safe to emit always)
    res.setHeader(
        'Strict-Transport-Security',
        'max-age=31536000; includeSubDomains; preload'
    );
    // Content Security Policy — restrictive for the landing page itself.
    // Download endpoints return application/octet-stream so CSP doesn't apply.
    res.setHeader(
        'Content-Security-Policy',
        "default-src 'self'; " +
        "script-src 'self' 'unsafe-inline'; " +
        "style-src 'self' 'unsafe-inline'; " +
        "img-src 'self' data:; " +
        "connect-src 'self'; " +
        "frame-ancestors 'none'; " +
        "base-uri 'self'; " +
        "form-action 'self';"
    );
    // Remove server fingerprinting
    res.removeHeader('X-Powered-By');
    next();
}

/** Rate limiter for public download endpoints (generous, burst-friendly). */
const downloadLimiter = rateLimit({
    windowMs: 60 * 1000, // 1 minute
    max: 60, // 60 requests/minute per IP
    standardHeaders: true,
    legacyHeaders: false,
    message: { success: false, error: 'Too many download requests. Please wait and retry.' },
    keyGenerator: (req) => req.ip || req.connection.remoteAddress || 'unknown',
});

/** Rate limiter for JSON API endpoints (stricter). */
const apiLimiter = rateLimit({
    windowMs: 60 * 1000,
    max: 120, // 120 requests/minute per IP
    standardHeaders: true,
    legacyHeaders: false,
    message: { success: false, error: 'API rate limit exceeded. Please slow down.' },
    keyGenerator: (req) => req.ip || req.connection.remoteAddress || 'unknown',
});

/** CORS — default same-origin only unless LANDING_ALLOWED_ORIGINS is set. */
function corsMiddleware(req, res, next) {
    const origin = req.headers.origin || '';
    let allowOrigin = false;

    if (ALLOWED_ORIGINS.length === 0) {
        // Same-origin only: echo back the request origin if it matches host,
        // otherwise deny. Simplest safe default: reflect no origin.
        res.setHeader('Access-Control-Allow-Origin', 'null');
    } else if (ALLOWED_ORIGINS.includes(origin) || ALLOWED_ORIGINS.includes('*')) {
        allowOrigin = origin || '*';
        res.setHeader('Access-Control-Allow-Origin', allowOrigin);
    }

    if (allowOrigin) {
        res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
        res.setHeader('Access-Control-Allow-Headers', 'Accept, Content-Type');
        res.setHeader('Access-Control-Max-Age', '86400');
    }

    if (req.method === 'OPTIONS') {
        res.status(204).end();
        return;
    }
    next();
}

/** Body size cap — landing API has no large POST bodies. */
function bodySizeLimit(req, res, next) {
    if (req.headers['content-length']) {
        const len = Number(req.headers['content-length']);
        if (len > 1024 * 1024) {
            return res.status(413).json({ success: false, error: 'Request body too large.' });
        }
    }
    next();
}

module.exports = {
    securityHeaders,
    downloadLimiter,
    apiLimiter,
    corsMiddleware,
    bodySizeLimit,
};
