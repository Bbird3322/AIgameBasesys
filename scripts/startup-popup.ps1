param(
  [string]$SignalPath,
  [string]$Message = "Launcher starting"
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

if ([string]::IsNullOrWhiteSpace($SignalPath)) {
  throw "SignalPath is required."
}

$signalDir = Split-Path -Parent $SignalPath
if (-not (Test-Path -LiteralPath $signalDir -PathType Container)) {
  New-Item -ItemType Directory -Path $signalDir -Force | Out-Null
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "LLM Game Base"
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$form.ControlBox = $false
$form.TopMost = $true
$form.ShowInTaskbar = $false
$form.Width = 360
$form.Height = 140
$form.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 24)
$form.ForeColor = [System.Drawing.Color]::Gainsboro

$label = New-Object System.Windows.Forms.Label
$label.Left = 18
$label.Top = 18
$label.Width = 310
$label.Height = 30
$label.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Regular)
$label.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$form.Controls.Add($label)

$bar = New-Object System.Windows.Forms.ProgressBar
$bar.Left = 18
$bar.Top = 58
$bar.Width = 310
$bar.Height = 18
$bar.Minimum = 0
$bar.Maximum = 100
$bar.Value = 0
$bar.Style = [System.Windows.Forms.ProgressBarStyle]::Continuous
$form.Controls.Add($bar)

$status = New-Object System.Windows.Forms.Label
$status.Left = 18
$status.Top = 84
$status.Width = 310
$status.Height = 20
$status.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$status.ForeColor = [System.Drawing.Color]::Silver
$status.Text = "Starting..."
$form.Controls.Add($status)

$dots = @(".", "..", "...", "....")
$script:index = 0
$script:barValue = 0
$script:barStep = 4
$script:isClosingPhase = $false
$script:shownAt = Get-Date
$minimumVisibleMs = 1200
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 350
$timer.Add_Tick({
  $script:index = ($script:index + 1) % $dots.Count
  $label.Text = $Message + $dots[$script:index]

  $elapsedMs = ([datetime]::Now - $script:shownAt).TotalMilliseconds
  if (-not $script:isClosingPhase -and $elapsedMs -ge $minimumVisibleMs -and (Test-Path -LiteralPath $SignalPath -PathType Leaf)) {
    $script:isClosingPhase = $true
    $script:barStep = 20
    $status.Text = "Finalizing..."
  }

  $script:barValue += $script:barStep
  if ($script:isClosingPhase) {
    if ($script:barValue -ge 100) {
      $script:barValue = 100
      $bar.Value = $script:barValue
      $form.Close()
      return
    }
  } else {
    if ($script:barValue -ge 100) {
      $script:barValue = 100
      $script:barStep = -4
    } elseif ($script:barValue -le 0) {
      $script:barValue = 0
      $script:barStep = 4
    }
  }
  $bar.Value = $script:barValue
})

$form.Add_Shown({ $timer.Start() })
$form.Add_FormClosed({
  try { $timer.Stop() } catch {}
  try { $timer.Dispose() } catch {}
})

$label.Text = $Message + $dots[0]
[System.Windows.Forms.Application]::Run($form)
