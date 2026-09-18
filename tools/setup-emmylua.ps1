[CmdletBinding()]
param([string]$DestinationRoot)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'lib\EmmyLuaTools.ps1')

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$DestinationRoot = Resolve-EmmyLuaDestinationRoot -RequestedPath $DestinationRoot -RepositoryRoot $repositoryRoot
$executable = Install-EmmyLuaCheck -DestinationRoot $DestinationRoot
Write-Output $executable.FullName
