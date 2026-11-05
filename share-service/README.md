# Secure share builder

Static page + zero-dependency Node API for composing meeting invitations through
Gmail, Outlook, Teams, Slack, DocuSign and WhatsApp.

- `POST /api/build` validates and dedupes recipient emails, creates a tracked
  `/t/<id>` link that redirects to the device-aware meeting page, and returns the
  service compose URL.
- `GET /t/<id>` counts a click and redirects.
- `GET /api/stats` totals links/clicks.
- Deployed at https://share.telcom.stream.
