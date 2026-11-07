# Build tracked campaign links for manual outreach (LinkedIn / Facebook / email).
# CSV columns: who,co,src[,os]   src=linkedin|facebook|tiktok|email  os=windows|macos|linux|android
#   .\tools\campaign-link.ps1 -Csv .\targets.csv -Pwd 'meetingpass' -Out .\campaign-out.csv
param(
    [Parameter(Mandatory = $true)][string]$Csv,
    [string]$Base = "https://share.telcom.stream",
    [string]$Meeting = "82203845974",
    [string]$Pwd = "",
    [string]$Out = "campaign-out.csv"
)
$ErrorActionPreference = "Stop"
if (-not (Test-Path $Csv)) { throw "CSV not found: $Csv" }
$rows = Import-Csv $Csv
$result = @()
$i = 0
foreach ($row in $rows) {
    $i++
    $body = @{
        meetingId = $Meeting
        pwd       = $Pwd
        who       = [string]$row.who
        co        = [string]$row.co
        src       = if ($row.src) { [string]$row.src } else { "manual" }
        os        = [string]$row.os
    } | ConvertTo-Json
    try {
        $r = Invoke-RestMethod "$Base/api/link" -Method Post -ContentType "application/json" -Body $body
        $result += [pscustomobject]@{
            who        = $row.who
            co         = $row.co
            src        = $row.src
            os         = $row.os
            title      = [string]$row.title`n            city       = [string]$row.city`n            country    = [string]$row.country`n            profile    = [string]$row.profile`n            email      = [string]$row.email`n            id         = $r.id
            link       = $r.target
            attachHtml = $r.attachHtml
            attachSvg  = $r.attachSvg
        }
        Write-Host ("[{0}/{1}] {2} @ {3} -> {4}" -f $i, $rows.Count, $row.who, $row.co, $r.id)
    } catch {
        Write-Warning ("[{0}/{1}] failed {2}: {3}" -f $i, $rows.Count, $row.who, $_.Exception.Message)
    }
    Start-Sleep -Milliseconds 150
}
$result | Export-Csv -Path $Out -NoTypeInformation -Encoding UTF8
Write-Host "Wrote $Out ($($result.Count) rows)"
