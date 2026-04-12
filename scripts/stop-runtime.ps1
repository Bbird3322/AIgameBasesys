param(
  [switch]$LlamaOnly,
  [switch]$GameOnly
)

$ErrorActionPreference = "Stop"

function Read-JsonFile {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) {
    return $null
  }

  try {
    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
  } catch {
    return $null
  }
}

function Remove-StateFile {
  param([string]$Path)

  if (Test-Path -LiteralPath $Path) {
    Remove-Item -LiteralPath $Path -Force
  }
}

function Stop-TrackedProcess {
  param(
    [string]$Name,
    [string]$StateFile
  )

  $state = Read-JsonFile -Path $StateFile
  if (-not $state -or -not $state.pid) {
    Write-Output "[INFO] $Name was not tracked."
    return
  }

  try {
    $process = Get-Process -Id ([int]$state.pid) -ErrorAction Stop
    Stop-Process -Id $process.Id -Force -ErrorAction Stop
    Write-Output "[OK] Stopped $Name (PID $($process.Id))."
  } catch {
    Write-Output "[INFO] $Name was already stopped."
  } finally {
    Remove-StateFile -Path $StateFile
  }
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$llamaStateFile = Join-Path $scriptDir "llama-server.state.json"
$gameStateFile = Join-Path $scriptDir "game-server.state.json"

if (-not $GameOnly) {
  Stop-TrackedProcess -Name "llama-server" -StateFile $llamaStateFile
}

if (-not $LlamaOnly) {
  Stop-TrackedProcess -Name "game server" -StateFile $gameStateFile
}
