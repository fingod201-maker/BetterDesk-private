# Operator

Drives a real logged-in browser for outreach. LinkedIn has no personal DM API, so this
is the honest way to automate it without a partner app.

## One-time

```
cd operator
npm install
node build-queues.js
node run.js --platform linkedin --stage view --queue out/queue-view.csv --max 1
```

The first run opens Chromium. Log in manually (and finish 2FA). The profile is stored
in `operator/profile-linkedin/`; later runs reuse it. Use a residential connection and
the same machine for a while — a datacenter IP that keeps changing is the main
detection trigger.

## Daily loop

```
node run.js --platform linkedin --stage view    --queue out/queue-view.csv --max 15
node run.js --platform linkedin --stage connect --queue out/queue-connect.csv --max 15
node run.js --platform linkedin --stage dm      --queue out/queue-dm.csv --max 15
node run.js --platform linkedin --stage check
```

`check` scans the connections list and writes `out/status-*.csv` rows as `accepted`,
so you can build the DM queue from accepted people only. Pacing is built in
(40–85s connects, 25–50s DMs, 7–14s views) and every failure is screenshotted to `out/`.

## Profiles

`docs/campaign-out.csv` has a `profile` column. Fill the LinkedIn URL per person and
run `build-queues.js`. Without it, the tool searches `who + company` and opens the
first `/in/` result — acceptable, but URL beats search.

## Selector rot

LinkedIn changes the DOM. The script tries role/name selectors, then text selectors.
When everything fails it records `no-connect-button` / `no-message-button` and saves a
screenshot. Update the selector lists in `run.js`; nothing else needs to change.

## Facebook

Same runner: `--platform facebook --stage view|dm`, queue with `profile` (profile URL).
Facebook DMs often require a friend request first; send requests manually, then run the
DM queue. Groups posting stays manual.

## Limits

20–30 connects/day, 40–60 DMs/day, one InMail only if no reply after a week. Stop for
the day on the first captcha, solve it, then continue. Do not run two stages in
parallel on one account.
