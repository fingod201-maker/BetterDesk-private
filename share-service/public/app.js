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
          message: $('message').value
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
      if (data.service === 'docusign') {
        notice('DocuSign has no compose deep link. Copy the message and paste it in the envelope email, or use the copied link in DocuSign.', false);
      } else {
        notice('Invitation ready. Open the composer and send.', true);
      }
      if (data.service !== 'copy' && data.service !== 'docusign') window.open(data.link, '_blank', 'noopener');
    } catch (error) {
      notice(error.message, false);
    } finally {
      button.disabled = false;
    }
  });

  $('copy').addEventListener('click', function () { if (last) copy(last.target); });
  $('copybody').addEventListener('click', function () { if (last) copy(last.body); });
  $('year').textContent = new Date().getFullYear();
})();
