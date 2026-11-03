'use strict';

const {
    buildWindowsSupportInstallerScript,
} = require('../services/windowsSupportInstaller');

describe('Support Agent installers', () => {
    test('Windows installer honors disabled task and autostart profile', () => {
        const script = buildWindowsSupportInstallerScript({
            installService: false,
            autostart: false,
        });
        expect(script).toContain('$profileInstallsTask = $false');
        expect(script).toContain('$profileAutostarts = $false');
        expect(script).toContain('installed without autostart');
    });

    test('Windows installer enables the user-session task profile', () => {
        const script = buildWindowsSupportInstallerScript({
            installService: true,
            autostart: true,
        });
        expect(script).toContain('$profileInstallsTask = $true');
        expect(script).toContain('$profileAutostarts = $true');
        expect(script).toContain('Register-ScheduledTask');
    });
});
