$wc = New-Object System.Net.WebClient
$content = $wc.DownloadString('http://147.224.213.55:8080/')
Write-Host $content.Substring(0,500)