# Linux live-stream verification harness

Headless Ubuntu container used to verify the Linux support agent without
changing the host desktop session. It runs Xvfb, xterm, and the Linux agent.

```sh
KEY="$(cat /opt/betterdesk/keys/.api_key)"   # never commit this value
podman build -t bd-linux-client .
podman run -d --name bd-linux-live --network host \
  -e BDAGENT_API_KEY="$KEY" bd-linux-client
```

The agent reads `BDAGENT_API_KEY` (the config file intentionally leaves
`api_key` empty), connects to the CDAP gateway on `127.0.0.1:21122`, captures
the Xvfb display with `ffmpeg x11grab`, and injects mouse/keyboard events with
`xdotool`.

Verified on 2026-11-03:

- 1920x1080 JPEG frames
- mouse move/click/down/up
- keyboard text and Return
- terminal stream
- no `xdotool mousemove --sync` stalls (removed from the Linux backend)
