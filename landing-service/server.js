'use strict';

/**
 * BetterDesk Meet — standalone landing service.
 *
 * Serves the public landing page plus the client release/download API. This is
 * a slim, self-contained service (Express + the landing route/service modules)
 * intended to run anywhere — locally, on Railway, or behind any container host —
 * so the landing page has a public backend and can be fronted by GitHub Pages.
 *
 * Routes:
 *   GET /                     → landing page
 *   GET /landing              → landing page
 *   GET /join                 → 302 → /landing
 *   GET /img/*, /js/*         → static assets
 *   GET /api/landing/client   → device detection + recommended client
 *   GET /api/landing/releases → release index
 *   GET /api/landing/meeting/:id → meeting join deep-link
 *   GET /landing/download     → backend-proxied client download
 *   GET /healthz              → health probe
 *
 * Environment:
 *   PORT                  listen port (default 8080)
 *   LANDING_GITHUB_OWNER  release owner (default fingod201-maker)
 *   LANDING_GITHUB_REPO   release repo  (default BetterDesk)
 *   UPDATE_GITHUB_TOKEN / GITHUB_TOKEN  optional PAT (higher API rate limit)
 *   LANDING_ALLOWED_ORIGINS  comma-separated CORS allowlist (default: *)
 */

const path = require('path');
const express = require('express');
const cors = require('cors');

const landingRoutes = require('./routes/landing.routes');

const PUBLIC_DIR = path.join(__dirname, 'public');
const LANDING_HTML = path.join(PUBLIC_DIR, 'landing', 'index.html');

const app = express();
app.disable('x-powered-by');

// CORS — the page is often served from a different origin (GitHub Pages).
const allowed = (process.env.LANDING_ALLOWED_ORIGINS || '').trim();
app.use(cors(allowed
    ? { origin: allowed.split(',').map((o) => o.trim()).filter(Boolean) }
    : { origin: true }));

app.use(express.json());

// ---- Static landing assets -------------------------------------------------
app.use('/img', express.static(path.join(PUBLIC_DIR, 'img'), { maxAge: '7d' }));
app.use('/js', express.static(path.join(PUBLIC_DIR, 'js'), { maxAge: '1h' }));
app.use('/landing', express.static(path.join(PUBLIC_DIR, 'landing')));

app.get('/', (req, res) => res.sendFile(LANDING_HTML));
app.get('/landing', (req, res) => res.sendFile(LANDING_HTML));
app.get('/join', (req, res) => res.redirect(302, '/landing'));

// ---- Landing API + proxied downloads --------------------------------------
app.use('/', landingRoutes);

// ---- Health ----------------------------------------------------------------
app.get('/healthz', (req, res) => res.json({ status: 'ok', service: 'betterdesk-landing', ts: Date.now() }));

const port = parseInt(process.env.PORT, 10) || 8080;
app.listen(port, () => {
    console.log(`[landing-service] listening on :${port}`);
});
