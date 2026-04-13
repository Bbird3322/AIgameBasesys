param(
  [string]$Root = "",
  [int]$Port = 4173
)

$ErrorActionPreference = "Stop"

if (-not $Root) {
  $Root = [string](Resolve-Path (Join-Path $PSScriptRoot ".."))
}

$rootFullPath = [System.IO.Path]::GetFullPath($Root)
$runtimeProfilePath = Join-Path $rootFullPath "config\runtimeProfile.json"
$defaultLlamaUrl = "http://127.0.0.1:8080"

function Get-ContentType([string]$Path) {
  switch ([System.IO.Path]::GetExtension($Path).ToLowerInvariant()) {
    ".html" { return "text/html; charset=utf-8" }
    ".js"   { return "text/javascript; charset=utf-8" }
    ".json" { return "application/json; charset=utf-8" }
    ".css"  { return "text/css; charset=utf-8" }
    ".svg"  { return "image/svg+xml" }
    ".png"  { return "image/png" }
    ".jpg"  { return "image/jpeg" }
    ".jpeg" { return "image/jpeg" }
    ".gif"  { return "image/gif" }
    ".ico"  { return "image/x-icon" }
    default  { return "application/octet-stream" }
  }
}

function Write-StringResponse {
  param(
    [System.Net.HttpListenerResponse]$Response,
    [int]$StatusCode,
    [string]$Body,
    [string]$ContentType = "text/plain; charset=utf-8"
  )

  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
  $Response.StatusCode = $StatusCode
  $Response.ContentType = $ContentType
  $Response.ContentLength64 = $bytes.Length
  $Response.OutputStream.Write($bytes, 0, $bytes.Length)
}

function Get-LlamaBaseUrl {
  if (Test-Path -LiteralPath $runtimeProfilePath -PathType Leaf) {
    try {
      $runtimeCfg = Get-Content -LiteralPath $runtimeProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
      if ($runtimeCfg.llamaCppUrl) {
        return [string]$runtimeCfg.llamaCppUrl
      }
    } catch {}
  }

  return $defaultLlamaUrl
}

function Invoke-LlamaProxy {
  param([string]$JsonBody)

  $llamaBaseUrl = Get-LlamaBaseUrl
  $llamaChatUrl = "$llamaBaseUrl/v1/chat/completions"

  try {
    $res = Invoke-WebRequest -UseBasicParsing -Method Post -Uri $llamaChatUrl -Body $JsonBody -ContentType "application/json; charset=utf-8" -TimeoutSec 90
    return @{ status = [int]$res.StatusCode; body = [string]$res.Content }
  } catch {
    $statusCode = 502
    $upstreamBody = ""
    if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
      $statusCode = [int]$_.Exception.Response.StatusCode
      try {
        $stream = $_.Exception.Response.GetResponseStream()
        if ($null -ne $stream) {
          $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8)
          try {
            $upstreamBody = $reader.ReadToEnd()
          } finally {
            $reader.Dispose()
          }
        }
      } catch {}
    }

    $errorBody = (@{
      error = "llama_proxy_failed"
      detail = $_.Exception.Message
      llamaBaseUrl = $llamaBaseUrl
      upstreamBody = if ($upstreamBody.Length -gt 800) { $upstreamBody.Substring(0, 800) } else { $upstreamBody }
    } | ConvertTo-Json -Depth 4)

    return @{ status = $statusCode; body = $errorBody }
  }
}

function Invoke-DelayedStop([string]$StopArgs) {
  $stopScript = Join-Path $PSScriptRoot "stop-runtime.ps1"
  $command = "Start-Sleep -Milliseconds 500; & '$stopScript' $StopArgs"
  Start-Process -FilePath "powershell.exe" -ArgumentList @("-NoProfile", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass", "-Command", $command) -WindowStyle Hidden | Out-Null
}

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://127.0.0.1:$Port/")
$listener.Start()

try {
  while ($listener.IsListening) {
    $context = $listener.GetContext()
    $request = $context.Request
    $response = $context.Response

    try {
      $method = $request.HttpMethod
      $path = [System.Uri]::UnescapeDataString($request.Url.AbsolutePath)

      if ($path -eq "/__health") {
        Write-StringResponse -Response $response -StatusCode 200 -Body "ok"
        continue
      }

      if ($path -eq "/__control/stop-game") {
        Write-StringResponse -Response $response -StatusCode 200 -Body '{"ok":true,"scope":"game"}' -ContentType "application/json; charset=utf-8"
        Invoke-DelayedStop -StopArgs "-GameOnly"
        continue
      }

      if ($path -eq "/__control/stop-all") {
        Write-StringResponse -Response $response -StatusCode 200 -Body '{"ok":true,"scope":"all"}' -ContentType "application/json; charset=utf-8"
        Invoke-DelayedStop -StopArgs ""
        continue
      }

      if ($path -eq "/api/chat") {
        if ($method -ne "POST") {
          Write-StringResponse -Response $response -StatusCode 405 -Body "Method Not Allowed"
          continue
        }

        # Force UTF-8 for browser JSON payloads to avoid mojibake and upstream parse failures.
        $reader = [System.IO.StreamReader]::new($request.InputStream, [System.Text.Encoding]::UTF8, $true)
        try {
          $requestBody = $reader.ReadToEnd()
        } finally {
          $reader.Dispose()
        }

        if ([string]::IsNullOrWhiteSpace($requestBody)) {
          Write-StringResponse -Response $response -StatusCode 400 -Body '{"error":"empty_request_body"}' -ContentType "application/json; charset=utf-8"
          continue
        }

        $proxyResult = Invoke-LlamaProxy -JsonBody $requestBody
        Write-StringResponse -Response $response -StatusCode $proxyResult.status -Body $proxyResult.body -ContentType "application/json; charset=utf-8"
        continue
      }

      if ($method -ne "GET") {
        Write-StringResponse -Response $response -StatusCode 405 -Body "Method Not Allowed"
        continue
      }

      if ($path -eq "/") {
        $path = "/index.html"
      }

      $relativePath = $path.TrimStart('/') -replace '/', '\\'
      $candidatePath = Join-Path $rootFullPath $relativePath
      $localPath = [System.IO.Path]::GetFullPath($candidatePath)

      if (-not $localPath.StartsWith($rootFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-StringResponse -Response $response -StatusCode 403 -Body "Forbidden"
        continue
      }

      if (-not (Test-Path -LiteralPath $localPath -PathType Leaf)) {
        Write-StringResponse -Response $response -StatusCode 404 -Body "Not Found"
        continue
      }

      $bytes = [System.IO.File]::ReadAllBytes($localPath)
      $response.StatusCode = 200
      $response.ContentType = Get-ContentType -Path $localPath
      $response.ContentLength64 = $bytes.Length
      $response.OutputStream.Write($bytes, 0, $bytes.Length)
    } catch {
      Write-StringResponse -Response $response -StatusCode 500 -Body "Internal Server Error"
    } finally {
      $response.Close()
    }
  }
} finally {
  $listener.Stop()
  $listener.Close()
}
