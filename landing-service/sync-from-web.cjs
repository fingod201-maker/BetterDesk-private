'use strict';

/**
 * Vendor the canonical landing code from ../web-nodejs into this service so it
 * can be deployed on its own (Railway, container, etc.). Keeps a single source
 * of truth: edit in web-nodejs, then run `npm run sync` here.
 *
 *   node sync-from-web.cjs
 */

const fs = require('fs');
const path = require('path');

const SRC = path.resolve(__dirname, '..', 'web-nodejs');
const DST = __dirname;

const FILES = [
    ['services/landingReleaseService.js', 'services/landingReleaseService.js'],
    ['routes/landing.routes.js', 'routes/landing.routes.js'],
    ['public/landing/index.html', 'public/landing/index.html'],
    ['public/js/landing.js', 'public/js/landing.js'],
];

function copyFile(rel, outRel) {
    const from = path.join(SRC, rel);
    const to = path.join(DST, outRel);
    if (!fs.existsSync(from)) {
        console.error('  MISSING ' + rel);
        process.exitCode = 1;
        return;
    }
    fs.mkdirSync(path.dirname(to), { recursive: true });
    fs.copyFileSync(from, to);
    console.log('  ' + rel + ' -> ' + outRel);
}

for (const [rel, outRel] of FILES) copyFile(rel, outRel);

// Zoom-style imagery
const imgSrc = path.join(SRC, 'public', 'img');
const imgDst = path.join(DST, 'public', 'img');
fs.mkdirSync(imgDst, { recursive: true });
for (const name of fs.readdirSync(imgSrc)) {
    if (/^zoom-.*\.(png|ico)$/i.test(name)) {
        fs.copyFileSync(path.join(imgSrc, name), path.join(imgDst, name));
        console.log('  public/img/' + name);
    }
}

console.log('Synced landing sources from web-nodejs.');
