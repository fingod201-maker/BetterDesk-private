// Generate src-tauri/icons/icon.icns from the PNGs already in that folder.
//
// Tauri v2's macOS bundler requires an .icns in bundle.icon, but the repo only
// ships PNGs (+ a .ico). The Tauri CLI's `icon` command needs a single 1024x1024
// RGBA source, which we do not have, so we assemble an ICNS container directly
// (modern .icns entries embed PNG data verbatim).
//
// Usage: node scripts/gen-icns.mjs
import { readFileSync, writeFileSync, readdirSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const iconsDir = join(here, '..', 'src-tauri', 'icons');
const outFile = join(iconsDir, 'icon.icns');

// ICNS OSType per square pixel size (PNG-based element types).
const TYPE_BY_SIZE = {
    16: 'icp4',
    32: 'icp5',
    64: 'icp6',
    128: 'ic07',
    256: 'ic08',
    512: 'ic09',
    1024: 'ic10',
};

function pngSize(buf) {
    // PNG signature (8) + IHDR length (4) + type (4) => width @16, height @20.
    if (buf.length < 24 || buf.toString('ascii', 1, 4) !== 'PNG') return null;
    return { width: buf.readUInt32BE(16), height: buf.readUInt32BE(20) };
}

function chunk(type, data) {
    const header = Buffer.alloc(8);
    header.write(type, 0, 'ascii');
    header.writeUInt32BE(data.length + 8, 4);
    return Buffer.concat([header, data]);
}

const candidates = existsSync(iconsDir) ? readdirSync(iconsDir).filter((f) => f.toLowerCase().endsWith('.png')) : [];
const entries = [];
const seen = new Set();

for (const file of candidates) {
    const buf = readFileSync(join(iconsDir, file));
    const size = pngSize(buf);
    if (!size || size.width !== size.height) {
        console.warn(`skip ${file}: not a square PNG`);
        continue;
    }
    const type = TYPE_BY_SIZE[size.width];
    if (!type) {
        console.warn(`skip ${file}: ${size.width}px has no ICNS type`);
        continue;
    }
    if (seen.has(type)) continue;
    seen.add(type);
    entries.push(chunk(type, buf));
    console.log(`  ${type}  ${size.width}x${size.height}  <- ${file}`);
}

if (entries.length === 0) {
    console.error('No usable PNGs found; cannot build icon.icns');
    process.exit(1);
}

const body = Buffer.concat(entries);
const header = Buffer.alloc(8);
header.write('icns', 0, 'ascii');
header.writeUInt32BE(body.length + 8, 4);

writeFileSync(outFile, Buffer.concat([header, body]));
console.log(`Wrote ${outFile} (${(body.length + 8)} bytes, ${entries.length} entries)`);
