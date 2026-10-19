# BetterDesk + Cloudflare Tunnel (Option B — free, keeps your PC as the server)

Cloudflare Tunnel makes an **outbound** connection from your PC to Cloudflare's edge
and publishes your local services as public `https://` / `wss://` hostnames. Because it
dials *out*, it tunnels straight through CGNAT — **no router port-forwarding needed**,
which is why this is the right choice for your home/mobile connection.

---

## ⚠️ Read this first: DuckDNS ≠ Cloudflare Tunnel

`desktop-client.duckdns.org` **cannot** be used directly with a Cloudflare Tunnel.
Cloudflare Tunnel can only serve hostnames that live in a **Cloudflare zone**
(a domain whose nameservers you point at Cloudflare). `duckdns.org` is not yours, so
Cloudflare can't publish records for it.

So you have **two real paths**:

| Path | Stable hostname? | Domain needed? | Best for |
|------|------------------|----------------|----------|
| **A. TryCloudflare quick tunnel** | ❌ (URL changes on restart) | No | Testing / proving it works **now** |
| **B. Named tunnel on your domain** | ✅ | Yes — a domain added to Cloudflare (free) | Production / handing to clients |

You can do **A immediately** (below), then move to **B** whenever you add a domain to
your Cloudflare account (Cloudflare Registrar sells `.com` at ~cost, or use a free
`.tk`/`.ml`-style zone, or repoint any domain you already own to Cloudflare's
nameservers — it stays free on Cloudflare's plan).

---

## Path A — TryCloudflare quick tunnel (works in ~30 seconds, no domain)

Publish your web console right now:

```powershell
docker run -d --name bd-tunnel-demo --restart unless-stopped `
  cloudflare/cloudflared:latest tunnel --no-autoupdate `
  --url http://host.docker.internal:5000
```

Get your public URL:

```powershell
docker logs bd-tunnel-demo 2>&1 | Select-String 'trycloudflare.com'
```

That prints something like `https://calm-pond-1234.trycloudflare.com`. Open it — your
BetterDesk console is now on the public internet over HTTPS. WebSocket paths (`/ws/...`)
work automatically through the tunnel.

> The URL is **random and changes every restart** of the container. Fine for testing;
> for anything you hand to clients, use Path B.

Stop / remove the demo:

```powershell
docker rm -f bd-tunnel-demo
```

---

## Path B — Named tunnel (stable hostname, what you actually want long-term)

### 1. Add your domain to Cloudflare
- Cloudflare dashboard → **Add a site** → enter your domain → Free plan.
- At your registrar, change the domain's **nameservers** to the two Cloudflare gives you.
- Wait for "Active" (usually minutes).

### 2. Create the tunnel
Cloudflare dashboard → **Zero Trust** → **Networks** → **Tunnels** → **Create a tunnel**
→ **Cloudflared** → name it `betterdesk`.

### 3. Install / run the connector with your token
On the "Install connector" screen, choose **Docker** and copy the token command, or just
use the compose file in this folder:

```powershell
# from c:\Users\milaz\BetterDesk\cloudflared
$env:CLOUDFLARE_TUNNEL_TOKEN = "PASTE_TOKEN_FROM_DASHBOARD"
docker compose -f docker-compose.cloudflared.yml up -d
docker logs betterdesk-cloudflared
```

### 4. Add Public Hostnames (in the dashboard, on the tunnel's "Public Hostnames" tab)

| Public hostname | Service (URL) | Type | What it exposes |
|-----------------|---------------|------|-----------------|
| `panel.YOURDOMAIN.com` | `http://host.docker.internal:5000` | HTTP | Web console / admin panel |
| `api.YOURDOMAIN.com`   | `http://host.docker.internal:21114` | HTTP | Go REST API (`/api`) |
| `cdap.YOURDOMAIN.com`  | `http://host.docker.internal:21122` | HTTP | CDAP WebSocket gateway (desktop client) |

`host.docker.internal` reaches services running on your Windows host. If you later run
the full `docker-compose.yml` stack, change these to the container names
(`betterdesk-console:5000`, `betterdesk-server:21114`, etc.) and put cloudflared on the
same `betterdesk-net` network.

> WebSocket / WSS upgrade is handled automatically by cloudflared — no extra headers needed.

---

## What to bake into the client build (the values you asked about)

Once you have a stable hostname, the generator/console needs:

| Setting | Value |
|---------|-------|
| `PANEL_PUBLIC_HOST` / `PANEL_PUBLIC_URL` | `https://panel.YOURDOMAIN.com` |
| `PUBLIC_API_URL` | `https://api.YOURDOMAIN.com` |
| CDAP endpoint (`cdap_url`) | `wss://cdap.YOURDOMAIN.com/cdap` |
| `HTTPS_ENABLED` | `true` |
| `TRUST_PROXY` | `true` (Cloudflare edge is the proxy) |

These already exist as keys in `C:\BetterDeskConsole\.env` (confirmed present).

---

## Honest limitation you must know

Cloudflare Tunnel carries **HTTP / HTTPS / WebSocket only**. It **cannot** expose the
raw **TCP** ports (21116 signal, 21117 relay) or **UDP** (21115 NAT test) to arbitrary
RustDesk clients over a public hostname.

- ✅ Works through the tunnel: web console, REST API, CDAP WSS, and WSS signal/relay
  (21118/21119) if your client speaks WebSocket.
- ❌ Does **not** work through the tunnel: legacy clients that need raw TCP/UDP to
  21116/21117.

The modern BetterDesk desktop client uses the **CDAP WebSocket** channel, so it works
fully behind Cloudflare Tunnel. If you ever need legacy raw-TCP clients, that requires a
real public IP (a small VPS), which is the only thing CGNAT blocks.
