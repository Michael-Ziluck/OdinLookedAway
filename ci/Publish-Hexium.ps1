[CmdletBinding(SupportsShouldProcess)]
param([string]$PackageFile = '', [switch]$SkipExisting)
& (Join-Path $PSScriptRoot 'Publish.ps1') -Registry Hexium -PackageFile $PackageFile -SkipExisting:$SkipExisting -WhatIf:$WhatIfPreference
