# Remove the module, if it exists in the current session.
Remove-Module PoshAws -ErrorAction SilentlyContinue

$_profileDirectory = Split-Path $profile

if (!(Test-Path $_profileDirectory)) {
    Write-Host "Creating profile directory at '$_profileDirectory'."
    New-Item -Path $_profileDirectory -ItemType directory
}

$_modulesDirectory = Join-Path $_profileDirectory Modules

if (!(Test-Path $_modulesDirectory)) {
    Write-Host "Creating modules directory at '$_modulesDirectory'."
    New-Item -Path $_modulesDirectory -ItemType directory
}

$_modulesMatch = $env:PSModulePath -like "*$_modulesDirectory*"

if (!$_modulesMatch) {
    Write-Warning "'$_modulesDirectory' does not seem to appear in your PSModulePath environment variable. ($env:PSModulePath)"
}

$_poshAwsDirectory = Join-Path $_modulesDirectory PoshAws

if (!(Test-Path $_poshAwsDirectory)) {
    Write-Host "Creating PoshAws directory at '$_poshAwsDirectory'."
    New-Item -Path $_poshAwsDirectory -ItemType directory
}

Write-Host "Copying files."
Copy-Item $PSScriptRoot\*.* $_poshAwsDirectory -Force

Write-Host "Installed PoshAws."