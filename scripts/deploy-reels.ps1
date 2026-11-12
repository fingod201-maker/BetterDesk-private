# Deploy the Reels lure page to the OCI box behind the Cloudflare tunnel.
#
#   pwsh -File scripts/deploy-reels.ps1
#
# Idempotent: creates/refreshes the static site, the systemd unit, the tunnel
# ingress and the proxied DNS record, then verifies. Env overrides:
#   REELS_HOST  (default reels.telcom.stream)
#   CF_API_TOKEN / CF_ZONE_ID  (token needs Zone.DNS Edit; Cache Purge optional)

[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'

$sshKey  = if ($env:SSH_KEY)  { $env:SSH_KEY }  else { "$env:USERPROFILE\.ssh\betterdesk_oci" }
$sshHost = if ($env:SSH_HOST) { $env:SSH_HOST } else { 'opc@147.224.213.55' }
$sub     = if ($env:REELS_HOST) { $env:REELS_HOST } else { 'reels.telcom.stream' }
$token   = if ($env:CF_API_TOKEN) { $env:CF_API_TOKEN } else { 'cfut_9wZ3EjlAu0DyGGEd9KmVUIsowNSm5vI7B4nPu2mZ298e7b44' }
$zone    = if ($env:CF_ZONE_ID)  { $env:CF_ZONE_ID }  else { '6cb3a3eb8fe4148b35289e5007d5f53f' }
$tunnel  = 'cc4bbdfe-cdca-4048-9e02-baad3c5cd9a4'
$port    = 3300
$repo    = Split-Path $PSScriptRoot -Parent
$site    = Join-Path $repo 'reels'

$ssh = @('-i', $sshKey, '-o', 'StrictHostKeyChecking=no', $sshHost)

Write-Host "1/4  Uploading $site ..."
& scp @ssh (Join-Path $site 'index.html') (Join-Path $site 'server.js') (Join-Path $site 'logo.svg') "${sshHost}:/tmp/"

Write-Host "2/4  Installing service ..."
$provision = @"
set -e
sudo mkdir -p /opt/betterdesk/reels
for f in index.html server.js logo.svg; do sudo install -o opc -g opc -m 644 /tmp/\$f /opt/betterdesk/reels/\$f; done
sudo tee /etc/systemd/system/betterdesk-reels.service >/dev/null <<UNIT
[Unit]
Description=BetterDesk Reels lure page
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=opc
Group=opc
WorkingDirectory=/opt/betterdesk/reels
Environment=REELS_PORT=$port
Environment=REELS_HOST=127.0.0.1
Environment=NODE_ENV=production
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=3
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
UNIT
sudo systemctl daemon-reload && sudo systemctl enable --now betterdesk-reels
sudo python3 - <<PY
p='/etc/cloudflared/betterdesk/config.yml'
s=open(p).read()
if '$sub' not in s:
    block='  - hostname: $sub\n    service: http://127.0.0.1:$port\n\n'
    open(p,'w').write(s.replace('  - service: http_status:404', block+'  - service: http_status:404', 1))
    print('ingress added')
else:
    print('ingress present')
PY
sudo systemctl restart cloudflared-betterdesk
sleep 3
systemctl is-active betterdesk-reels cloudflared-betterdesk
curl -s -o /dev/null -w 'local %{http_code}\n' http://127.0.0.1:$port/healthz
"@
$provision | & ssh @ssh 'cat > /tmp/deploy-reels.sh && bash /tmp/deploy-reels.sh'

Write-Host "3/4  Ensuring DNS CNAME ..."
$h = @{ Authorization = "Bearer $token" }
$existing = (Invoke-RestMethod -Uri "https://api.cloudflare.com/client/v4/zones/$zone/dns_records?name=$sub" -Headers $h).result
if ($existing.Count -gt 0) {
    Write-Host "     CNAME present: $($existing[0].id)"
} else {
    $body = @{ type = 'CNAME'; name = ($sub -replace '\.telcom\.stream$',''); content = "$tunnel.cfargotunnel.com"; proxied = $true; ttl = 1 } | ConvertTo-Json
    $r = Invoke-RestMethod -Method Post -Uri "https://api.cloudflare.com/client/v4/zones/$zone/dns_records" -Headers $h -ContentType 'application/json' -Body $body
    Write-Host "     CNAME created: $($r.result.id)"
}

Write-Host "4/4  Verifying https://$sub ..."
$code = (Invoke-WebRequest -Uri "https://$sub/healthz" -UseBasicParsing).StatusCode
Write-Host "     https://$sub/healthz -> $code"
Write-Host "Done. Lure link: https://$sub"
