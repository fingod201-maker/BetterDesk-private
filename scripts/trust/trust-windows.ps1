param(
  [Parameter(Mandatory = $true)]
  [string]$CertPath
)

$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($CertPath)
$storeRoot = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root", "LocalMachine")
$storeRoot.Open("ReadWrite")
$storeRoot.Add($cert)
$storeRoot.Close()

$storePublisher = New-Object System.Security.Cryptography.X509Certificates.X509Store("TrustedPublisher", "LocalMachine")
$storePublisher.Open("ReadWrite")
$storePublisher.Add($cert)
$storePublisher.Close()

Write-Host "Installed self-signed publisher certificate into LocalMachine Root + TrustedPublisher."