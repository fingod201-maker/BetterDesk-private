'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const {
    buildMacSupportInstallerScript,
    buildLinuxSupportInstallerScript,
    hasUnixSupportInstallers,
    writeUnixSupportInstallers,
    constants,
} = require('../services/platformSupportInstaller');

describe('macOS Support installer bundle', () => {
    const script = buildMacSupportInstallerScript({ installService: true, autostart: true });

    test('runs in the logged-in user session via a LaunchAgent', () => {
        expect(script).toContain('HOME/Library/LaunchAgents');
        expect(script).toContain('Library/LaunchAgents');
        expect(script).toContain('launchctl bootstrap "gui/');
        expect(script).toContain('LimitLoadToSessionType');
        expect(script).toContain('Aqua');
        expect(script).toContain('KeepAlive');
        expect(script).toContain('RunAtLoad');
        expect(script).toContain(constants.MACOS_LABEL);
    });

    test('never installs a session-0 LaunchDaemon', () => {
        expect(script).not.toContain('/Library/LaunchDaemons');
        expect(script).not.toContain('launchctl bootstrap system');
    });

    test('is unattended and self-restarting', () => {
        expect(script).not.toMatch(/\bread\s+-[rp]/);
        expect(script).not.toContain('Read-Host');
        expect(script).toContain('agent-launch.sh');
        expect(script).toContain('start-agent.sh');
        expect(script).toContain('ThrottleInterval');
        expect(script).toContain('Screen Recording');
        expect(script).toContain('Accessibility');
    });

    test('honors the disabled profile', () => {
        const disabled = buildMacSupportInstallerScript({ installService: false, autostart: false });
        expect(disabled).toContain('INSTALL_SERVICE="0"');
        expect(disabled).toContain('AUTOSTART="0"');
        expect(disabled).toContain('installed without autostart');
    });
});

describe('Linux Support installer bundle', () => {
    const script = buildLinuxSupportInstallerScript({ installService: true, autostart: true });

    test('runs in the desktop session via systemd --user and XDG autostart', () => {
        expect(script).toContain('systemctl --user');
        expect(script).toContain('.config/autostart');
        expect(script).toContain('betterdesk-support-agent.desktop');
        expect(script).toContain(constants.LINUX_UNIT);
        expect(script).toContain('graphical-session.target');
    });

    test('never installs a root system service', () => {
        expect(script).not.toContain('/etc/systemd/system');
        expect(script).not.toContain('User=root');
    });

    test('is unattended and self-restarting', () => {
        expect(script).not.toMatch(/\bread\s+-[rp]/);
        expect(script).toContain('agent-launch.sh');
        expect(script).toContain('Restart=always');
        expect(script).toContain('grim');
        expect(script).toContain('scrot');
    });

    test('honors the disabled profile', () => {
        const disabled = buildLinuxSupportInstallerScript({ installService: false, autostart: false });
        expect(disabled).toContain('INSTALL_SERVICE="0"');
        expect(disabled).toContain('AUTOSTART="0"');
        expect(disabled).toContain('installed without service or autostart');
    });
});

describe('Unix Support installer files', () => {
    test.each(['macos', 'linux'])('writes executable install/uninstall pair for %s', async (platform) => {
        const stageDir = await fs.promises.mkdtemp(path.join(os.tmpdir(), 'betterdesk-unix-installer-'));
        try {
            await writeUnixSupportInstallers(stageDir, platform, {
                installService: true,
                autostart: true,
            });
            expect(hasUnixSupportInstallers(stageDir)).toBe(true);
            for (const name of ['install-betterdesk-support.sh', 'uninstall-betterdesk-support.sh']) {
                const stat = await fs.promises.stat(path.join(stageDir, name));
                expect(stat.isFile()).toBe(true);
                if (process.platform !== 'win32') {
                    expect(stat.mode & 0o111).toBeTruthy();
                }
            }
        } finally {
            await fs.promises.rm(stageDir, { recursive: true, force: true });
        }
    });
});
