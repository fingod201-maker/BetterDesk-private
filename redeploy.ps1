# redeploy.ps1
Set-Location \"C:\Users\milaz\BetterDesk\web-nodejs\"

# 1️⃣ Install / update dependencies
Write-Host "🔧 Installing npm deps ..."
npm install

# 2️⃣ Build the static site
Write-Host "🛠️ Building ..."
npm run build   # <-- assumes the project's build script is `vite build` or `webpack`

# 3️⃣ Commit & push the new artefacts
Write-Host "📦 Committing built files ..."
cd \"C:\Users\milaz\BetterDesk\"
git add web-nodejs/public
git commit -m "chore: rebuild landing page $(Get-Date -Format 'yyyy-MM-dd')"

Write-Host "⏫ Pushing to gh‑pages ..."
git subtree push --prefix web-nodejs/public origin gh-pages

Write-Host "✅ Deploy finished – open http://<your‑github‑pages‑url> to verify."
