# Zoom Front Page

A local Next.js recreation of Zoom's meeting launch page and browser-join flow.

## Run locally

```bash
npm install
npm run dev
```

Open `http://localhost:3000` to see the launch page. Select **Join from browser** to view the join flow, including its joining loader, camera/microphone prompt, video preview, and meeting-info form.

## Routes

- `/j/{meetingId}` — launch page with app and browser join actions
- `/wc/{meetingId}/join` — browser join and pre-join interface

The root route opens the supplied meeting `82203845974`. Other meeting IDs work through the dynamic routes above.

## Project folders

- `src/components/sites/zoom/` — Zoom launch and browser-join components
- `public/sites/zoom/` — Zoom logo and permission illustration
- `docs/research/zoom/` — route notes and implementation evidence
- `Join from Zoom Workplace app - Zoom.html` and its companion assets folder — saved source reference

## Checks

```bash
npm run typecheck
npm run lint
npm run build
```
