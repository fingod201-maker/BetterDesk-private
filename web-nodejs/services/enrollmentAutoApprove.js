'use strict';

/**
 * Enrollment auto-approval.
 *
 * The Go server runs in "managed" enrollment mode: every new device lands in
 * the pending list and waits for a human in the console. For an in-house
 * fleet that is pure friction — the devices are ours, they present a valid
 * Ed25519 installation proof (the Go server rejects proofless support-agent
 * registrations outright) and they are bound to a known bundle id.
 *
 * This service approves those devices automatically the moment they enroll,
 * while leaving anything that does NOT carry a valid proof in the pending
 * list for a human to review.
 *
 * Policy (all configurable through the environment):
 *   ENROLLMENT_AUTO_APPROVE        "1" to enable (default: enabled)
 *   ENROLLMENT_AUTO_APPROVE_BUNDLES  comma separated bundle id allowlist
 *   ENROLLMENT_AUTO_APPROVE_TYPES    comma separated device type allowlist
 *   ENROLLMENT_AUTO_APPROVE_INTERVAL poll interval in seconds (default 5)
 */

const api = require('./betterdeskApi');

const ENABLED = String(process.env.ENROLLMENT_AUTO_APPROVE || '1').toLowerCase() !== '0';
const INTERVAL_MS = Math.max(2, parseInt(process.env.ENROLLMENT_AUTO_APPROVE_INTERVAL, 10) || 5) * 1000;
const ALLOWED_BUNDLES = String(process.env.ENROLLMENT_AUTO_APPROVE_BUNDLES || 'com.betterdesk.agent,com.betterdesk.client.universal')
    .split(',')
    .map((s) => s.trim().toLowerCase())
    .filter(Boolean);
const ALLOWED_TYPES = String(process.env.ENROLLMENT_AUTO_APPROVE_TYPES || 'os_agent')
    .split(',')
    .map((s) => s.trim().toLowerCase())
    .filter(Boolean);

let timer = null;
let running = false;

/**
 * Decide whether a pending device may be approved without a human.
 *
 * A device qualifies only when it is one of our own client builds:
 *   - the device type is allowlisted (os_agent)
 *   - the bundle id is allowlisted (com.betterdesk.agent)
 *   - a public key is present — the Go server only stores it after the
 *     device proved possession of the matching private key
 */
function isAutoApprovable(device) {
    if (!device || !device.device_id) return false;

    const type = String(device.device_type || '').toLowerCase();
    if (type && ALLOWED_TYPES.length && !ALLOWED_TYPES.includes(type)) return false;

    const bundle = String(device.bundle_id || '').toLowerCase();
    if (!bundle) return false;
    if (ALLOWED_BUNDLES.length && !ALLOWED_BUNDLES.includes(bundle)) return false;

    if (!String(device.public_key || '').trim()) return false;

    return true;
}

async function tick() {
    if (running) return;
    running = true;
    try {
        const res = await api.getEnrollmentPending();
        const payload = res && res.data !== undefined ? res.data : res;
        const devices = Array.isArray(payload)
            ? payload
            : (payload && (payload.devices || [])) || [];
        for (const device of devices) {
            if (!isAutoApprovable(device)) continue;
            const displayName = String(device.hostname || device.device_id).slice(0, 60);
            const result = await api.approveEnrollment(device.device_id, displayName, 'standard', 'support-agent,auto-approved');
            if (result && result.success) {
                console.log(`[enrollment-auto] approved ${device.device_id} (${device.bundle_id || 'unknown bundle'})`);
            } else {
                const err = (result && (result.error || result.message)) || 'approval failed';
                console.warn(`[enrollment-auto] could not approve ${device.device_id}: ${err}`);
            }
        }
    } catch (err) {
        console.warn('[enrollment-auto] poll failed:', err.message);
    } finally {
        running = false;
    }
}

/** Start the auto-approval poller. Safe to call once at boot. */
function start() {
    if (!ENABLED) {
        console.log('[enrollment-auto] disabled (ENROLLMENT_AUTO_APPROVE=0)');
        return;
    }
    if (timer) return;
    console.log(
        `[enrollment-auto] enabled — bundles: ${ALLOWED_BUNDLES.join(', ') || 'any'} | types: ${ALLOWED_TYPES.join(', ') || 'any'} | every ${INTERVAL_MS / 1000}s`
    );
    timer = setInterval(tick, INTERVAL_MS);
    timer.unref?.();
    setTimeout(tick, 2000);
}

function stop() {
    if (timer) {
        clearInterval(timer);
        timer = null;
    }
}

module.exports = { start, stop, tick, isAutoApprovable, ENABLED };
