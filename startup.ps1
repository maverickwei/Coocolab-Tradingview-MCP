Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object System.Windows.Forms.Form
$form.Text = "Startup..."
$form.Size = New-Object System.Drawing.Size(480, 546)
$form.StartPosition = "CenterScreen"
$form.TopMost = $true
$form.BackColor = [System.Drawing.Color]::FromArgb(15, 15, 26)
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.MinimizeBox = $false

$title = New-Object System.Windows.Forms.Label
$title.Text = ">> System Starting..."
$title.Font = New-Object System.Drawing.Font("Consolas", 13, [System.Drawing.FontStyle]::Bold)
$title.ForeColor = [System.Drawing.Color]::FromArgb(88, 166, 255)
$title.Location = New-Object System.Drawing.Point(20, 18)
$title.Size = New-Object System.Drawing.Size(440, 36)
$form.Controls.Add($title)

$sep = New-Object System.Windows.Forms.Label
$sep.BackColor = [System.Drawing.Color]::FromArgb(48, 54, 61)
$sep.Location = New-Object System.Drawing.Point(0, 60)
$sep.Size = New-Object System.Drawing.Size(480, 1)
$form.Controls.Add($sep)

$stepTexts = @(
    "1. Wait for network",
    "2. Connect home WiFi (蓁蓁)",
    "3. Launch TradingView (CDP 9222)",
    "4. Verify TradingView CDP ready",
    "5. Start monitor server (port 3000)",
    "6. Wait port 3000 -> start ngrok",
    "7. Start WiFi switcher (port 8765)",
    "8. Start LINE family bot (port 5000)",
    "9. Start Claude",
    "10. Start Daikin + Dyson + WiFi manager"
)

$labels = @()
$icons = @()
$y = 72
foreach ($s in $stepTexts) {
    $ypos = $y + 2
    $ic = New-Object System.Windows.Forms.Label
    $ic.Text = "[ ]"
    $ic.Font = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)
    $ic.ForeColor = [System.Drawing.Color]::Gray
    $ic.Location = New-Object System.Drawing.Point(14, $ypos)
    $ic.Size = New-Object System.Drawing.Size(40, 24)
    $form.Controls.Add($ic)
    $icons += $ic

    $lb = New-Object System.Windows.Forms.Label
    $lb.Text = $s
    $lb.Font = New-Object System.Drawing.Font("Consolas", 9)
    $lb.ForeColor = [System.Drawing.Color]::Gray
    $lb.Location = New-Object System.Drawing.Point(58, $ypos)
    $lb.Size = New-Object System.Drawing.Size(400, 24)
    $form.Controls.Add($lb)
    $labels += $lb
    $y += 36
}

$status = New-Object System.Windows.Forms.Label
$status.Text = "Initializing..."
$status.Font = New-Object System.Drawing.Font("Consolas", 9)
$status.ForeColor = [System.Drawing.Color]::FromArgb(126, 255, 212)
$status.Location = New-Object System.Drawing.Point(14, 450)
$status.Size = New-Object System.Drawing.Size(440, 24)
$form.Controls.Add($status)

$form.Show()
[System.Windows.Forms.Application]::DoEvents()

function Refresh-UI {
    [System.Windows.Forms.Application]::DoEvents()
    $form.Refresh()
    Start-Sleep -Milliseconds 100
    [System.Windows.Forms.Application]::DoEvents()
}

function Set-Step {
    param([int]$idx, [string]$state, [string]$msg)
    switch ($state) {
        "running" { $icons[$idx].Text = ">>>"; $icons[$idx].ForeColor = [System.Drawing.Color]::FromArgb(255,198,0); $labels[$idx].ForeColor = [System.Drawing.Color]::White }
        "ok"      { $icons[$idx].Text = "[OK]"; $icons[$idx].ForeColor = [System.Drawing.Color]::FromArgb(63,185,80); $labels[$idx].ForeColor = [System.Drawing.Color]::FromArgb(63,185,80) }
        "fail"    { $icons[$idx].Text = "[!!]"; $icons[$idx].ForeColor = [System.Drawing.Color]::FromArgb(255,123,114); $labels[$idx].ForeColor = [System.Drawing.Color]::FromArgb(255,123,114) }
        "skip"    { $icons[$idx].Text = "[--]"; $icons[$idx].ForeColor = [System.Drawing.Color]::Gray; $labels[$idx].ForeColor = [System.Drawing.Color]::Gray }
    }
    $status.Text = $msg
    Refresh-UI
}

# Step 1
Set-Step 0 "running" "Waiting for network..."
$t = 0
while ($t -lt 60) {
    if (Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet -ErrorAction SilentlyContinue) { break }
    Start-Sleep -Seconds 2; $t += 2; Refresh-UI
}
Set-Step 0 "ok" "Network ready"
Start-Sleep -Milliseconds 500

# Step 2 - Connect home WiFi (蓁蓁溫暖的家)
Set-Step 1 "running" "Connecting to home WiFi..."
function Get-CurrentSSID {
    try {
        $out = & netsh wlan show interfaces 2>$null
        foreach ($line in $out) {
            if ($line -match '^\s+SSID\s+:\s+(.+)$') { return $matches[1].Trim() }
        }
    } catch {}
    return ""
}
$curSSID = Get-CurrentSSID
if ($curSSID -like "蓁蓁*") {
    Set-Step 1 "ok" "Already on home WiFi: $curSSID"
} else {
    & netsh wlan connect name="蓁蓁溫暖的家" 2>$null | Out-Null
    $wifiOk = $false
    for ($wi = 0; $wi -lt 15; $wi++) {
        Start-Sleep -Seconds 2; Refresh-UI
        $curSSID = Get-CurrentSSID
        if ($curSSID -like "蓁蓁*") { $wifiOk = $true; break }
    }
    if ($wifiOk) { Set-Step 1 "ok" "Connected: $curSSID" }
    else { Set-Step 1 "fail" "WiFi timeout, continuing..."; Start-Sleep -Seconds 2; Refresh-UI }
}
Start-Sleep -Milliseconds 500

# Step 3
Set-Step 2 "running" "Launching TradingView..."
Stop-Process -Name "TradingView" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2; Refresh-UI
# Find real TradingView exe in WindowsApps
$pkg = Get-AppxPackage -Name "TradingView.Desktop" -ErrorAction SilentlyContinue
if ($pkg) {
    $tvExe = Get-ChildItem -Path $pkg.InstallLocation -Filter "TradingView.exe" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
    if ($tvExe) { Start-Process -FilePath $tvExe -ArgumentList "--remote-debugging-port=9222" }
}
Set-Step 2 "ok" "TradingView launched"
Start-Sleep -Seconds 5; Refresh-UI

# Step 4
Set-Step 3 "running" "Waiting for CDP (max 90s)..."
$cdpReady = $false
for ($i = 0; $i -lt 45; $i++) {
    Start-Sleep -Seconds 2; Refresh-UI
    try {
        $r = Invoke-WebRequest -Uri "http://localhost:9222/json/version" -TimeoutSec 2 -UseBasicParsing -ErrorAction Stop
        if ($r.StatusCode -eq 200) { $cdpReady = $true; break }
    } catch {}
}
if ($cdpReady) { Set-Step 3 "ok" "CDP ready"; Start-Sleep -Milliseconds 500 }
else { Set-Step 3 "fail" "CDP timeout, continuing..."; Start-Sleep -Seconds 3; Refresh-UI }

# Step 5 - kill any existing port 3000 first
$portPid = (netstat -ano | Select-String ":3000\s.*LISTENING").ToString().Trim().Split()[-1]
if ($portPid -and $portPid -ne "0") { Stop-Process -Id $portPid -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 1 }
Set-Step 4 "running" "Starting monitor server..."
$mcpDir = "$env:USERPROFILE\Coocolab-Tradingview-MCP"
Start-Process -FilePath "C:\Program Files\nodejs\node.exe" -ArgumentList "src/webhook-server.js" -WorkingDirectory $mcpDir -WindowStyle Hidden
Set-Step 4 "ok" "Monitor server started"
Start-Sleep -Milliseconds 500

# Step 6 - wait port 3000, then start ngrok for port 3000 + static domain for port 5000
Set-Step 5 "running" "Waiting port 3000..."
$ng = $false
for ($i = 0; $i -lt 15; $i++) {
    Start-Sleep -Seconds 2; Refresh-UI
    $c = Test-NetConnection -ComputerName localhost -Port 3000 -WarningAction SilentlyContinue
    if ($c.TcpTestSucceeded) { $ng = $true; break }
}
$ngrokPath = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\Ngrok.Ngrok_Microsoft.Winget.Source_8wekyb3d8bbwe\ngrok.exe"
if ($ng) {
    Start-Process -FilePath $ngrokPath -ArgumentList "http 3000" -WindowStyle Hidden
    Start-Process -FilePath $ngrokPath -ArgumentList "http --domain=pushup-removing-tribesman.ngrok-free.dev 5000" -WindowStyle Hidden
    Set-Step 5 "ok" "ngrok started (port 3000 + 5000)"
} else {
    Set-Step 5 "fail" "port 3000 not ready, skip ngrok"
}
Start-Sleep -Milliseconds 500

# Step 7
Set-Step 6 "running" "Starting WiFi switcher..."
$wifiScript = "$env:USERPROFILE\wifi-switcher\server.js"
Start-Process -FilePath "C:\Program Files\nodejs\node.exe" -ArgumentList $wifiScript -WindowStyle Hidden
Set-Step 6 "ok" "WiFi switcher started"
Start-Sleep -Milliseconds 500

# Step 8 - LINE family bot (Python Flask, port 5000)
Set-Step 7 "running" "Starting LINE family bot..."
$botDir = "$env:USERPROFILE\line-family-bot"
Start-Process -FilePath "python" -ArgumentList "app.py" -WorkingDirectory $botDir -WindowStyle Hidden
Set-Step 7 "ok" "LINE family bot started"
Start-Sleep -Milliseconds 500

# Step 9
Set-Step 8 "running" "Starting Claude..."
Start-Process "shell:AppsFolder\Claude_pzs8sxrjxfjjc!Claude"
Set-Step 8 "ok" "Claude started"
Start-Sleep -Milliseconds 500

# Step 10 - Daikin + Dyson + WiFi manager
Set-Step 9 "running" "Starting Daikin + Dyson + WiFi manager..."
$daikinDir = "$env:USERPROFILE\daikin-controller"
Start-Process -FilePath "C:\Program Files\nodejs\node.exe" -ArgumentList "server.js" -WorkingDirectory $daikinDir -WindowStyle Hidden
$dysonDir = "$env:USERPROFILE\dyson-controller"
Start-Process -FilePath "python" -ArgumentList "app.py" -WorkingDirectory $dysonDir -WindowStyle Hidden
Start-Process -FilePath "python" -ArgumentList "wifi_manager.py" -WorkingDirectory $dysonDir -WindowStyle Hidden
Set-Step 9 "ok" "Daikin + Dyson + WiFi manager started"
Start-Sleep -Milliseconds 500

# Open browsers
Start-Process "http://localhost:3000"
Start-Process "http://localhost:8081/apps"
Start-Sleep -Milliseconds 500

# Done
$form.Text = "Startup Complete!"
$title.Text = "*** All Services Ready ***"
$title.ForeColor = [System.Drawing.Color]::FromArgb(63, 185, 80)
Refresh-UI

$closeBtn = New-Object System.Windows.Forms.Button
$closeBtn.Text = "Close"
$closeBtn.Font = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)
$closeBtn.BackColor = [System.Drawing.Color]::FromArgb(63, 185, 80)
$closeBtn.ForeColor = [System.Drawing.Color]::Black
$closeBtn.FlatStyle = "Flat"
$closeBtn.Location = New-Object System.Drawing.Point(175, 480)
$closeBtn.Size = New-Object System.Drawing.Size(120, 32)
$closeBtn.Add_Click({ $form.Close() })
$form.Controls.Add($closeBtn)
Refresh-UI

for ($i = 30; $i -gt 0; $i--) {
    Start-Sleep -Seconds 1
    $status.Text = "All done! Auto-close in $i sec."
    Refresh-UI
    if (-not $form.Visible) { break }
}
if ($form.Visible) { $form.Close() }
