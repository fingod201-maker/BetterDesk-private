/**
 * BetterDesk Web Remote Client — MeshCentral transport adapter.
 * Uses BetterViewer (MNG_KVM) over meshrelay.
 */
(function () {
    'use strict';

    function MeshSession(canvas, opts) {
        this.canvas = canvas;
        this.opts = opts || {};
        this._handlers = {};
        this._state = 'idle';
        this._ws = null;
        this._desktop = null;
        this._deviceId = opts.deviceId || '';
    }

    MeshSession.prototype.on = function (event, fn) {
        if (!this._handlers[event]) this._handlers[event] = [];
        this._handlers[event].push(fn);
    };

    MeshSession.prototype._emit = function (event, data) {
        const list = this._handlers[event] || [];
        for (let i = 0; i < list.length; i++) list[i](data);
    };

    MeshSession.prototype._bindDesktop = function (desktop) {
        const self = this;
        desktop.on('state', function (s) { self._state = s; self._emit('state', s); });
        desktop.on('ready', function () { self._emit('ready'); });
        desktop.on('session_start', function () {
            self._emit('session_start');
            self._onStreaming();
        });
        desktop.on('disconnected', function () { self._emit('disconnected'); });
        desktop.on('videoFrame', function (f) { self._emit('videoFrame', f); });
        desktop.on('stats', function (s) { self._emit('stats', s); });
        desktop.on('inputLock', function (locked) { self._emit('cursorUpdate', { locked: locked }); });
        desktop.on('keyboardState', function (state) { self._emit('keyboardState', state); });
    };

    MeshSession.prototype.connect = async function () {
        this._state = 'connecting';
        this._emit('state', 'connecting');
        this._emit('log', 'Mesh: requesting desktop tunnel…');

        if (typeof BetterViewer !== 'function') {
            throw new Error('BetterViewer not loaded');
        }

        var self = this;
        this.fileTransfer = typeof MeshFileTransfer === 'function'
            ? new MeshFileTransfer(this._deviceId, function (event, data) { self._emit(event, data); })
            : {
                browseParent: function () {},
                browseDir: function () {},
                cancelTransfer: function () { return false; },
            };

        const relayBase = window.location.origin + '/';
        const tunnelQs = new URLSearchParams({ relay_base: relayBase });
        const pageQs = new URLSearchParams(window.location.search);
        if (pageQs.get('mesh_share')) {
            tunnelQs.set('mesh_share', pageQs.get('mesh_share'));
        }
        if (pageQs.get('guest') || pageQs.get('t')) {
            tunnelQs.set('guest', pageQs.get('guest') || pageQs.get('t'));
        }
        const capsEarly = window.__capabilities || {};
        if (capsEarly.guest_view_only || capsEarly.mesh_view_only) {
            tunnelQs.set('view_only', '1');
        }
        if (pageQs.get('record') === '1' || this.opts.serverRecord) {
            tunnelQs.set('record', '1');
        }
        const csrf = (window.BetterDesk && window.BetterDesk.csrfToken) || '';
        const headers = { 'Content-Type': 'application/json', Accept: 'application/json' };
        if (csrf) headers['X-CSRF-Token'] = csrf;
        const resp = await fetch(`/api/mesh/devices/${encodeURIComponent(this._deviceId)}/desktop?${tunnelQs.toString()}`, {
            method: 'POST',
            credentials: 'same-origin',
            headers,
        });
        if (!resp.ok) {
            const err = await resp.json().catch(() => ({}));
            throw new Error(err.error || 'Mesh tunnel request failed');
        }
        const data = await resp.json();
        const url = data.browser_url || data.data?.browser_url;
        if (!url) throw new Error('No mesh relay URL');

        const wsUrl = url.startsWith('http') ? url.replace(/^http/, 'ws') : (window.location.origin + url);
        this._ws = new WebSocket(wsUrl);
        this._ws.binaryType = 'arraybuffer';
        this._bindInput();

        this._ws.onmessage = (ev) => {
            if (ev.data instanceof ArrayBuffer) {
                this._drawFrame(ev.data);
                return;
            }
            let msg = null;
            try { msg = JSON.parse(ev.data); } catch { return; }
            if (!msg) return;
            if (msg.type === 'session-info') {
                this._agentReady = !!msg.agent_ready;
            } else if (msg.type === 'stream-started') {
                this._state = 'streaming';
                this._emit('state', 'streaming');
                this._emit('session_start');
                this._emit('ready');
                this._onStreaming();
            } else if (msg.type === 'agent-ready') {
                this._agentReady = true;
            } else if (msg.type === 'stream-stopped' || msg.type === 'agent-disconnected') {
                this._state = 'disconnected';
                this._emit('state', 'disconnected');
                this._emit('disconnected');
            } else if (msg.type === 'terminal_output') {
                this._emit('terminal', msg.output || '');
            }
        };

        this._ws.onerror = () => this._emit('error', { message: 'Mesh relay error' });
        this._ws.onclose = () => this.disconnect();
    };

    MeshSession.prototype._drawFrame = function (buf) {
        const self = this;
        const blob = new Blob([buf], { type: 'image/jpeg' });
        if (typeof createImageBitmap === 'function') {
            createImageBitmap(blob).then(function (bmp) {
                if (self._remoteW !== bmp.width || self._remoteH !== bmp.height) {
                    self._remoteW = bmp.width;
                    self._remoteH = bmp.height;
                    if (self.canvas.width !== bmp.width) self.canvas.width = bmp.width;
                    if (self.canvas.height !== bmp.height) self.canvas.height = bmp.height;
                }
                const ctx = self.canvas.getContext('2d');
                if (ctx) ctx.drawImage(bmp, 0, 0);
                if (bmp.close) bmp.close();
                self._emit('videoFrame', { width: bmp.width, height: bmp.height });
            }).catch(function () {});
        } else {
            const img = new Image();
            const url = URL.createObjectURL(blob);
            img.onload = function () {
                if (self.canvas.width !== img.width) self.canvas.width = img.width;
                if (self.canvas.height !== img.height) self.canvas.height = img.height;
                self._remoteW = img.width;
                self._remoteH = img.height;
                const ctx = self.canvas.getContext('2d');
                if (ctx) ctx.drawImage(img, 0, 0);
                URL.revokeObjectURL(url);
            };
            img.src = url;
        }
    };

    MeshSession.prototype._toRemote = function (ev) {
        const r = this.canvas.getBoundingClientRect();
        if (!r.width || !r.height || !this._remoteW) return null;
        // Canvas is letterboxed with object-fit: contain - map inside the
        // painted area only, not the full box.
        const scale = Math.min(r.width / this._remoteW, r.height / this._remoteH);
        const w = this._remoteW * scale;
        const h = this._remoteH * scale;
        const ox = r.left + (r.width - w) / 2;
        const oy = r.top + (r.height - h) / 2;
        return {
            x: Math.max(0, Math.min(this._remoteW - 1, Math.round((ev.clientX - ox) / scale))),
            y: Math.max(0, Math.min(this._remoteH - 1, Math.round((ev.clientY - oy) / scale)))
        };
    };

    MeshSession.prototype._sendInput = function (payload) {
        if (!this._ws || this._ws.readyState !== WebSocket.OPEN) return;
        this._ws.send(JSON.stringify(Object.assign({ type: 'input' }, payload)));
    };

    MeshSession.prototype._bindInput = function () {
        if (this._inputBound) return;
        this._inputBound = true;
        const self = this;
        const c = this.canvas;
        const map = { 0: 'left', 1: 'middle', 2: 'right' };
        c.addEventListener('mousemove', function (e) { const p = self._toRemote(e); if (p) self._sendInput({ event_type: 'mouse_move', x: p.x, y: p.y }); });
        c.addEventListener('mousedown', function (e) { const p = self._toRemote(e); if (p) { c.focus(); self._sendInput({ event_type: 'mouse_down', x: p.x, y: p.y, button: map[e.button] || 'left' }); } });
        c.addEventListener('mouseup', function (e) { const p = self._toRemote(e); if (p) self._sendInput({ event_type: 'mouse_up', x: p.x, y: p.y, button: map[e.button] || 'left' }); });
        c.addEventListener('wheel', function (e) { self._sendInput({ event_type: 'mouse_wheel', delta_y: e.deltaY > 0 ? 1 : -1 }); e.preventDefault(); }, { passive: false });
        c.addEventListener('keydown', function (e) {
            if (e.key === 'F11') return;
            self._sendInput({ event_type: 'key_down', key: e.key });
            if (e.key.length === 1 || e.key === 'Enter' || e.key === 'Backspace') e.preventDefault();
        });
        c.addEventListener('keyup', function (e) { self._sendInput({ event_type: 'key_up', key: e.key }); });
    };
    MeshSession.prototype._onStreaming = function () {
        if (this.fileTransfer && typeof this.fileTransfer.enable === 'function') {
            this.fileTransfer.enable();
        }
    };

    MeshSession.prototype.disconnect = function () {
        if (this.fileTransfer && typeof this.fileTransfer.disable === 'function') {
            this.fileTransfer.disable();
        }
        if (this._desktop) {
            this._desktop.disconnect();
            this._desktop = null;
        }
        if (this._ws) {
            try { this._ws.close(); } catch { /* ignore */ }
            this._ws = null;
        }
        this._state = 'disconnected';
        this._emit('state', 'disconnected');
        this._emit('disconnected');
    };

    MeshSession.prototype.authenticate = function () { return Promise.resolve(); };
    MeshSession.prototype.verify2fa = function () { return Promise.resolve(); };
    MeshSession.prototype.setViewOnly = function (viewOnly) {
        if (this._desktop && typeof this._desktop.setViewOnly === 'function') {
            this._desktop.setViewOnly(viewOnly);
        }
    };

    window.MeshSession = MeshSession;
})();
