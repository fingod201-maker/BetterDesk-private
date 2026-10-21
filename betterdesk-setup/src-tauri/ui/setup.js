/* zoom-private Setup — UI glue for the Tauri commands. */
(function () {
  var $ = function (id) { return document.getElementById(id); };
  var logEl = $('log');
  var stepEl = $('step');
  var statusEl = $('status');
  var goBtn = $('go');
  var consoleInput = $('console');

  function log(line) {
    logEl.textContent += (logEl.textContent ? '\n' : '') + line;
    logEl.scrollTop = logEl.scrollHeight;
  }

  function step(name) {
    stepEl.textContent = name;
    log('• ' + name);
  }

  function setStatus(text, kind) {
    statusEl.textContent = text || '';
    statusEl.className = 'status' + (kind ? ' ' + kind : '');
  }

  var api = window.__TAURI__;
  if (!api || !api.core) {
    setStatus('This window must be opened by the zoom-private Setup app.', 'err');
    return;
  }

  api.event.listen('setup-log', function (e) { log(e.payload.line); });
  api.event.listen('setup-step', function (e) { step(e.payload.step); });

  api.core.invoke('detect').then(function (info) {
    consoleInput.value = info.default_console;
    $('os').textContent = info.os_label;
    $('arch').textContent = info.arch;
    $('installed').textContent = info.already_installed
      ? 'client already installed'
      : 'client not installed';
    if (info.already_installed) {
      setStatus('A client is already installed at ' + info.client_path + '. Running setup again repairs it.', 'ok');
    }
  }).catch(function (e) {
    setStatus('Detection failed: ' + e, 'err');
  });

  $('console-link').addEventListener('click', function () {
    var url = (consoleInput.value || '').trim();
    if (url) { api.core.invoke('open_console', { url: url }).catch(function () {}); }
  });

  goBtn.addEventListener('click', function () {
    var consoleUrl = (consoleInput.value || '').trim();
    if (!consoleUrl) { setStatus('Enter the console address first.', 'err'); return; }
    goBtn.disabled = true;
    logEl.textContent = '';
    setStatus('Installing…');
    step('Starting');
    api.core.invoke('install', { console: consoleUrl })
      .then(function () {
        step('done');
        setStatus('Installed. The client is running and registers itself with the console.', 'ok');
      })
      .catch(function (e) {
        setStatus(String(e && e.message ? e.message : e), 'err');
        log('✗ ' + (e && e.message ? e.message : e));
      })
      .finally(function () { goBtn.disabled = false; });
  });
})();
