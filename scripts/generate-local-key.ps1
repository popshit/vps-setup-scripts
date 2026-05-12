param(
  [Parameter(Mandatory = $true, Position = 0)]
  [ValidatePattern('^[A-Za-z0-9._-]+$')]
  [string] $KeyName
)

$ErrorActionPreference = 'Stop'

$sshKeygen = Get-Command ssh-keygen.exe -ErrorAction SilentlyContinue
if (-not $sshKeygen) {
  throw 'ssh-keygen.exe is required. Install OpenSSH Client from Windows Optional Features.'
}

$sshDir = Join-Path $HOME '.ssh'
$keyPath = Join-Path $sshDir "${KeyName}_ed25519"
$pubPath = "${keyPath}.pub"

New-Item -ItemType Directory -Force -Path $sshDir | Out-Null

if ((Test-Path -LiteralPath $keyPath) -or (Test-Path -LiteralPath $pubPath)) {
  throw "Key already exists: $keyPath"
}

& $sshKeygen.Source -t ed25519 -a 100 -f $keyPath -C $KeyName -N ''
if ($LASTEXITCODE -ne 0) {
  throw 'ssh-keygen.exe failed.'
}

Write-Host ''
Write-Host 'Private key:'
Write-Host "  $keyPath"
Write-Host ''
Write-Host 'Public key to pass into setup-vps.sh:'
Get-Content -LiteralPath $pubPath
Write-Host ''
Write-Host 'Example login after server setup:'
Write-Host "  ssh -i $keyPath -p 2222 deploy@YOUR_SERVER_IP"
