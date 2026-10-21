'use strict';

/**
 * Device -> web console authentication contract.
 *
 * The Go API issues the enrollment device_token (betterdesk-server/api/
 * branding_handlers.go -> issueEnrollmentDeviceToken) and stores it in the
 * shared `device_tokens` table as sha256(token). The console accepts that
 * token on the device WebSocket (bd-signal / remote relay) through
 * verifyDeviceWsAuth. If this contract breaks, enrolled devices silently
 * fail to connect back to the web console.
 */

const fs = require('fs');
const os = require('os');
const path = require('path');
const crypto = require('crypto');

const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'bd-device-token-'));
const dbPath = path.join(tmpDir, 'db_v2.sqlite3');

process.env.DB_PATH = dbPath;
process.env.DB_TYPE = 'sqlite';

const Database = require('better-sqlite3');
const db = new Database(dbPath);
db.exec(`
    CREATE TABLE IF NOT EXISTS device_tokens (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        token_hash TEXT UNIQUE NOT NULL,
        token_prefix TEXT NOT NULL DEFAULT '',
        name TEXT NOT NULL DEFAULT '',
        peer_id TEXT DEFAULT '',
        status TEXT NOT NULL DEFAULT 'pending',
        max_uses INTEGER DEFAULT 1,
        use_count INTEGER DEFAULT 0,
        created_at TEXT DEFAULT (datetime('now')),
        expires_at TEXT DEFAULT NULL,
        revoked_at TEXT DEFAULT NULL,
        last_used_at TEXT DEFAULT NULL,
        created_by TEXT NOT NULL DEFAULT '',
        note TEXT NOT NULL DEFAULT ''
    )
`);

const { hashDeviceToken, verifyDeviceWsAuth, verifyEnrollmentToken } = require('../lib/deviceTokenAuth');

function issueToken(peerId, overrides = {}) {
    const plain = crypto.randomBytes(24).toString('hex');
    const row = {
        token_hash: hashDeviceToken(plain),
        token_prefix: plain.slice(0, 6),
        name: `Auto-${peerId}`,
        peer_id: peerId,
        status: 'active',
        max_uses: 0,
        use_count: 0,
        expires_at: null,
        ...overrides,
    };
    db.prepare(`
        INSERT INTO device_tokens (token_hash, token_prefix, name, peer_id, status, max_uses, use_count, expires_at)
        VALUES (@token_hash, @token_prefix, @name, @peer_id, @status, @max_uses, @use_count, @expires_at)
    `).run(row);
    return plain;
}

afterAll(() => {
    try { db.close(); } catch (_e) { /* ignore */ }
    try { fs.rmSync(tmpDir, { recursive: true, force: true }); } catch (_e) { /* ignore */ }
});

describe('device token auth (device -> web console)', () => {
    test('hashDeviceToken matches the Go sha256-hex scheme', () => {
        const expected = crypto.createHash('sha256').update('abc', 'utf8').digest('hex');
        expect(hashDeviceToken('abc')).toBe(expected);
    });

    test('accepts an active enrollment token bound to the device', async () => {
        const token = issueToken('BD-ABCDEFGH');
        await expect(verifyDeviceWsAuth('BD-ABCDEFGH', token)).resolves.toBe(true);
    });

    test('rejects the same token for a different device id', async () => {
        const token = issueToken('BD-ABCDEFGH');
        await expect(verifyDeviceWsAuth('BD-OTHER', token)).resolves.toBe(false);
    });

    test('rejects revoked and expired tokens', async () => {
        const revoked = issueToken('BD-REVOKED', { status: 'revoked' });
        const expired = issueToken('BD-EXPIRED', {
            status: 'active',
            expires_at: new Date(Date.now() - 60_000).toISOString(),
        });
        await expect(verifyDeviceWsAuth('BD-REVOKED', revoked)).resolves.toBe(false);
        await expect(verifyDeviceWsAuth('BD-EXPIRED', expired)).resolves.toBe(false);
    });

    test('rejects a token whose use limit is exhausted', async () => {
        const token = issueToken('BD-LIMITED', { max_uses: 1, use_count: 1 });
        await expect(verifyEnrollmentToken('BD-LIMITED', token)).resolves.toBe(false);
    });

    test('rejects missing or too-short credentials', async () => {
        await expect(verifyDeviceWsAuth('', 'token')).resolves.toBe(false);
        await expect(verifyDeviceWsAuth('BD-X', '')).resolves.toBe(false);
        await expect(verifyDeviceWsAuth('BD-X', 'short')).resolves.toBe(false);
    });
});
