#Requires -Version 7.6
<#
.SYNOPSIS
    Installs the exact tool versions the gate needs: PSScriptAnalyzer, Pester and
    gitleaks.

.DESCRIPTION
    Installs each tool only when the required version is not already present, so it is
    safe to run on a machine that has them.

      PSScriptAnalyzer 1.25.0   from PSGallery, CurrentUser scope
      Pester 5.7.1              from PSGallery, CurrentUser scope
      gitleaks 8.30.1           the windows_x64 release zip from GitHub, into
                                -Destination. The zip's SHA-256 must equal the hash
                                pinned below, from the release's checksums file; any
                                other file is deleted unread and the script stops

    gitleaks is added to PATH for this PowerShell session only, so run the gate in the
    same session (CI does: .github\workflows\gate.yml runs both scripts in one step).

    Windows only for now: the unit tier is not yet run on Linux (TODO.md, Post-Project
    Notes).

.PARAMETER Destination
    The folder gitleaks is unpacked into. Created when missing.

.EXAMPLE
    .\Scripts\Install-GateTool.ps1 -Destination (Join-Path -Path $env:RUNNER_TEMP -ChildPath 'gate-tools')
    .\Scripts\Invoke-Gate.ps1 -Unit -Base origin/master

    Installs the tools, then runs the gate in the same session, as CI does.

.NOTES
    Copyright © TACE Data Management Inc.
    **Invocation:** Standalone — self-contained; dot-source or call with `&` so the PATH
    change reaches the gate run that follows. Needs network access to PSGallery and
    github.com.
    [SEC] Versions are pinned and the gitleaks download is checked against a pinned
    SHA-256 before it is unpacked. When the gitleaks version changes, take the new hash
    from the release's gitleaks_<version>_checksums.txt and update both here and in
    Scripts\Invoke-Gate.ps1.
#>
[CmdletBinding(SupportsShouldProcess)]
[OutputType([string])]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Destination
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $IsWindows) { throw '[Install-GateTool] Windows only for now: the gate is not yet run on Linux.' }

$modules = @(
    @{ Name = 'PSScriptAnalyzer'; Version = '1.25.0' }
    @{ Name = 'Pester'; Version = '5.7.1' }
)
$gitleaksVersion = '8.30.1'
$gitleaksAsset   = "gitleaks_${gitleaksVersion}_windows_x64.zip"
$gitleaksSha256  = 'd29144deff3a68aa93ced33dddf84b7fdc26070add4aa0f4513094c8332afc4e'
$gitleaksUrl     = "https://github.com/gitleaks/gitleaks/releases/download/v$gitleaksVersion/$gitleaksAsset"

# -- Modules -----------------------------------------------------------------

foreach ($module in $modules) {
    $present = @(Get-Module -Name $module.Name -ListAvailable | Where-Object { $PSItem.Version -eq [version]$module.Version })
    if ($present.Count -gt 0) {
        Write-Output "[INFO] $($module.Name) $($module.Version) already installed"
        continue
    }
    if ($PSCmdlet.ShouldProcess("$($module.Name) $($module.Version)", 'Install from PSGallery')) {
        $installParams = @{
            Name            = $module.Name
            Version         = $module.Version
            Repository      = 'PSGallery'
            Scope           = 'CurrentUser'
            TrustRepository = $true
        }
        Install-PSResource @installParams
        Write-Output "[INFO] $($module.Name) $($module.Version) installed"
    }
}

# -- gitleaks ----------------------------------------------------------------

$existing = Get-Command -Name gitleaks -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if ($null -ne $existing -and ((& $existing.Source version) | Select-Object -First 1).Trim() -eq $gitleaksVersion) {
    Write-Output "[INFO] gitleaks $gitleaksVersion already on PATH"
    return
}

if (-not $PSCmdlet.ShouldProcess($Destination, "Download, verify and unpack gitleaks $gitleaksVersion")) { return }

$null = New-Item -Path $Destination -ItemType Directory -Force
$zip = Join-Path -Path $Destination -ChildPath $gitleaksAsset
Invoke-WebRequest -Uri $gitleaksUrl -OutFile $zip

$actual = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actual -ne $gitleaksSha256) {
    Remove-Item -LiteralPath $zip -Force
    throw "[Install-GateTool] $gitleaksAsset failed its SHA-256 check; the download was deleted."
}

Expand-Archive -LiteralPath $zip -DestinationPath $Destination -Force
Remove-Item -LiteralPath $zip -Force

$env:PATH = $Destination + [System.IO.Path]::PathSeparator + $env:PATH
$installed = ((& (Join-Path -Path $Destination -ChildPath 'gitleaks.exe') version) | Select-Object -First 1).Trim()
if ($installed -ne $gitleaksVersion) { throw "[Install-GateTool] gitleaks reports $installed; $gitleaksVersion was expected." }
Write-Output "[INFO] gitleaks $gitleaksVersion verified and added to PATH for this session"
