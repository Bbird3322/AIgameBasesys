param(
  [string]$Root = "",
  [int]$Port = 4173
)

$ErrorActionPreference = "Stop"

if (-not $Root) {
  $Root = [string](Resolve-Path (Join-Path $PSScriptRoot ".."))
}

$healthUrl = "http://127.0.0.1:$Port/__health"
$gameUrl = "http://127.0.0.1:$Port/index.html"
$serveScript = Join-Path $PSScriptRoot "serve-game.ps1"

function Test-Health([string]$Url) {
  try {
    $response = Invoke-WebRequest -UseBasicParsing $Url -TimeoutSec 2
    return $response.StatusCode -eq 200
  } catch {
    return $false
  }
}

if (-not (Test-Health $healthUrl)) {
  $args = @(
    '-NoProfile',
    '-WindowStyle', 'Hidden',
    '-ExecutionPolicy', 'Bypass',
    '-File', $serveScript,
    '-Root', $Root,
    '-Port', $Port
  )

  Start-Process -FilePath "powershell.exe" -ArgumentList $args -WindowStyle Hidden | Out-Null

  $ok = $false
  1..20 | ForEach-Object {
    if (Test-Health $healthUrl) {
      $ok = $true
      return
    }
    Start-Sleep -Milliseconds 500
  }

  if (-not $ok) {
    throw "Game server did not become ready."
  }
}

Start-Process $gameUrl | Out-Null
