<#
.SYNOPSIS
  Refreshes Docker's ECR login credential (tokens expire after ~12 hours).

.DESCRIPTION
  Manually writes a base64 "AWS:<token>" auth entry directly into
  ~/.docker/config.json's `auths` map for the ECR registry - exactly what a
  working `docker login` would normally do.

  This exists because on this machine both `docker login` (fails with a 400
  from a Docker Desktop client-side bug) and the official
  amazon-ecr-credential-helper (fails with "credentials not found in native
  keychain", a separate Windows-specific bug) are broken. The token itself
  and the network path are fine - verified independently via a raw curl
  Basic-auth request against the ECR endpoint.

  Also strips `credsStore` from the Docker config if present: Docker ignores
  plaintext `auths` entries entirely whenever a credsStore is configured, so
  the two are mutually exclusive for this workaround to function.

.EXAMPLE
  .\scripts\ecr-login.ps1
#>
param(
    [string]$AwsProfile = "uptime-monitor",
    [string]$Region = "ap-south-1",
    [string]$AccountId = "816069171489"
)

$registry = "$AccountId.dkr.ecr.$Region.amazonaws.com"

$token = (aws ecr get-login-password --profile $AwsProfile --region $Region).Trim()
if (-not $token) {
    Write-Error "Failed to get ECR login token. Is your SSO session still valid? Try: aws sso login --profile $AwsProfile"
    exit 1
}

$authString = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("AWS:$token"))

$configPath = "$env:USERPROFILE\.docker\config.json"
$config = Get-Content $configPath -Raw | ConvertFrom-Json

if (-not $config.auths) {
    $config | Add-Member -MemberType NoteProperty -Name "auths" -Value ([PSCustomObject]@{}) -Force
}
$config.auths | Add-Member -MemberType NoteProperty -Name $registry -Value ([PSCustomObject]@{ auth = $authString }) -Force

if ($config.PSObject.Properties.Name -contains "credsStore") {
    Write-Warning "Removing 'credsStore' from Docker config - Docker ignores plaintext auth entries while it's set."
    $config.PSObject.Properties.Remove("credsStore")
}

$json = $config | ConvertTo-Json -Depth 10
# Windows PowerShell 5.1's `-Encoding utf8` writes a BOM, which Docker's Go
# JSON parser can't handle - write BOM-less UTF-8 directly instead.
[System.IO.File]::WriteAllText($configPath, $json, [System.Text.UTF8Encoding]::new($false))

Write-Host "ECR login refreshed for $registry"
