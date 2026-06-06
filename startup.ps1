Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object System.Windows.Forms.Form
$form.Text = "Startup..."
$form.Size = New-Object System.Drawing.Size(480, 510)
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
    "2. Launch TradingView (CDP 9222)",
    "3. Verify TradingView CDP ready",
    "4. Start monitor server (port 3000)",
    "5. Wait port 3000 -> start ngrok",
    "6. Start WiFi switcher (port 8765)",
    "7. Start LINE family bot (port 5000)",
    "8. Start Claude"
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
$status.Location = New-Object System.Drawing.Point(14, 414)
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

# Step 2
Set-Step 1 "running" "Launching TradingView..."
Stop-Process -Name "TradingView" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2; Refresh-UI
# Find real TradingView exe in WindowsApps
$pkg = Get-AppxPackage -Name "TradingView.Desktop" -ErrorAction SilentlyContinue
if ($pkg) {
    $tvExe = Get-ChildItem -Path $pkg.InstallLocation -Filter "TradingView.exe" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
    if ($tvExe) { Start-Process -FilePath $tvExe -ArgumentList "--remote-debugging-port=9222" }
}
Set-Step 1 "ok" "TradingView launched"
Start-Sleep -Seconds 5; Refresh-UI

# Step 3
Set-Step 2 "running" "Waiting for CDP (max 90s)..."
$cdpReady = $false
for ($i = 0; $i -lt 45; $i++) {
    Start-Sleep -Seconds 2; Refresh-UI
    try {
        $r = Invoke-WebRequest -Uri "http://localhost:9222/json/version" -TimeoutSec 2 -UseBasicParsing -ErrorAction Stop
        if ($r.StatusCode -eq 200) { $cdpReady = $true; break }
    } catch {}
}
if ($cdpReady) { Set-Step 2 "ok" "CDP ready"; Start-Sleep -Milliseconds 500 }
else { Set-Step 2 "fail" "CDP timeout, continuing..."; Start-Sleep -Seconds 3; Refresh-UI }

# Step 4 - kill any existing port 3000 first
$portPid = (netstat -ano | Select-String ":3000\s.*LISTENING").ToString().Trim().Split()[-1]
if ($portPid -and $portPid -ne "0") { Stop-Process -Id $portPid -Force -ErrorAction SilentlyContinue; Start-Sleep -Seconds 1 }
Set-Step 3 "running" "Starting monitor server..."
$mcpDir = "$env:USERPROFILE\Coocolab-Tradingview-MCP"
Start-Process -FilePath "C:\Program Files\nodejs\node.exe" -ArgumentList "src/webhook-server.js" -WorkingDirectory $mcpDir -WindowStyle Hidden
Set-Step 3 "ok" "Monitor server started"
Start-Sleep -Milliseconds 500

# Step 5 - wait port 3000, then start ngrok for port 3000 + static domain for port 5000
Set-Step 4 "running" "Waiting port 3000..."
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
    Set-Step 4 "ok" "ngrok started (port 3000 + 5000)"
} else {
    Set-Step 4 "fail" "port 3000 not ready, skip ngrok"
}
Start-Sleep -Milliseconds 500

# Step 6
Set-Step 5 "running" "Starting WiFi switcher..."
$wifiScript = "$env:USERPROFILE\wifi-switcher\server.js"
Start-Process -FilePath "C:\Program Files\nodejs\node.exe" -ArgumentList $wifiScript -WindowStyle Hidden
Set-Step 5 "ok" "WiFi switcher started"
Start-Sleep -Milliseconds 500

# Step 7 - LINE family bot (Python Flask, port 5000)
Set-Step 6 "running" "Starting LINE family bot..."
$botDir = "$env:USERPROFILE\line-family-bot"
Start-Process -FilePath "python" -ArgumentList "app.py" -WorkingDirectory $botDir -WindowStyle Hidden
Set-Step 6 "ok" "LINE family bot started"
Start-Sleep -Milliseconds 500

# Step 8
Set-Step 7 "running" "Starting Claude..."
Start-Process "shell:AppsFolder\Claude_pzs8sxrjxfjjc!Claude"
Set-Step 7 "ok" "Claude started"
Start-Sleep -Milliseconds 500

# Open browser
Start-Process "http://localhost:3000"
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
$closeBtn.Location = New-Object System.Drawing.Point(175, 444)
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
