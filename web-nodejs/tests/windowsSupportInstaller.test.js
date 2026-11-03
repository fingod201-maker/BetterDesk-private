'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const {
    buildWindowsSupportInstallerScript,
    hasWindowsSupportInstallers,
    writeWindowsSupportInstallers,
} = require('../services/windowsSupportInstaller');

describe('Windows Support installer bundle', () => {
    test('runs the agent hidden in the logged-in user session', () => {
        const script = buildWindowsSupportInstallerScript({ installService: true, autostart: true });

        expect(script).toContain('Register-ScheduledTask');
        expect(script).toContain('wscript.exe');
        expect(script).toContain('start-agent.vbs');
        expect(script).toContain('agent-launch.cmd');
        expect(script).toContain('--tray');
        expect(script).toContain('Interactive');
    });

    test('never installs a session-0 service', () => {
        const script = buildWindowsSupportInstallerScript();
        expect(script).not.toContain('--install-service');
        expect(script).not.toContain('--uninstall-service');
        expect(script).not.toContain('New-Service');
    });

    test('writes both installer entry points to the artifact root', async () => {
        const stageDir = await fs.promises.mkdtemp(path.join(os.tmpdir(), 'betterdesk-installer-'));
        try {
            await writeWindowsSupportInstallers(stageDir, { installService: true, autostart: true });
            expect(hasWindowsSupportInstallers(stageDir)).toBe(true);
            expect(await fs.promises.readFile(
                path.join(stageDir, 'Install-BetterDesk.ps1'),
                'utf8'
            )).toContain('Register-ScheduledTask');
        } finally {
            await fs.promises.rm(stageDir, { recursive: true, force: true });
        }
    });
});
