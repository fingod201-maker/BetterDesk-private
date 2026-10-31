# Zoom meeting link

## Route map

| Source | Local route | Owner |
| --- | --- | --- |
| `https://us05web.zoom.us/j/82037280661?...#success` | `/j/82037280661` | `src/app/j/[meetingId]/page.tsx`, `src/components/sites/zoom/launch-meeting-options.tsx` |
| Browser join transition to `https://app.zoom.us/wc/82037280661/join?...` | `/wc/82037280661/join` | `src/app/wc/[meetingId]/join/page.tsx`, `src/components/sites/zoom/join-meeting-form.tsx` |

The root route redirects to the original launch route. On “Join from browser”, the local page preserves `pwd`, sets `ref_from=launch` and `fromPWA=1`, and carries the provided RTA tracking values into the browser join route. The supplied passcode does not produce a visible passcode field.

## Inspection evidence and limits

The browser inspection service could not render the supplied meeting URL. A direct request to `us05web.zoom.us/j/82037280661` returned a Cloudflare rate-limit page. The workspace contains a saved copy of the Zoom launch page HTML; its DOM confirms a Zoom SVG wordmark, Support and English controls, the “Join meeting” heading, primary app button, secondary browser button, download and terms copy, and the footer links. The secondary button uses `zoom-button zoom-button--lg zoom-button--secondary g7nkJFrV`, `aria-disabled="false"`, and `order: 2`. The app-hosted launch shell and web-client HTML were also retrieved; the latter exposes the meeting number, required display name, remember-name checkbox, Join action, footer, and media-preview strings. Zoom's published join guide describes the app/browser choice, browser permission prompt, name entry, preview controls, and final Join action. The local browser action preserves the passcode, changes the pathname to `/wc/{meetingId}/join`, and requests real camera/microphone access. The browser route displays the actual camera stream when permitted and exposes mute/video controls and permission/device error states.

The saved Zoom launch DOM is recreated at `/j/{meetingId}`. Its bundled CSS provides the visual measurements used for the local launch page: Inter/Open Sans/Helvetica/Arial font stack, centered 840px frame, 24px bold heading with a 52px lower margin, and a 400px button column with 20px gaps. The app-launch notice appears after the app protocol handoff attempt and auto-dismisses after five seconds. Selecting “Join from browser” navigates to `/wc/{meetingId}/join` with the provided query values. The browser destination uses Zoom's dark canvas, with a brief dark “Joining meeting” loader bridging the route change. Its permission prompt uses the source `zm-modal` structure, the exact Zoom placeholder artwork, and the two supplied instruction strings; the modal is sized to 480px wide with Zoom dark-modal styling. It requests browser camera/microphone access when it appears. The browser owns the native permission prompt appearance. The local Join action stops at a preparing state and does not connect to the real meeting. Zoom's live app route could not be rendered by the web viewer; its permission image was fetched from the exact asset URL supplied by the user.
