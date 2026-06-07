Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$form = New-Object System.Windows.Forms.Form
$form.Text = "系統啟動中..."
$form.Size = New-Object System.Drawing.Size(480, 546)
$form.StartPosition = "CenterScreen"
$form.TopMost = $true
$form.BackColor = [System.Drawing.Color]::FromArgb(15, 15, 26)
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.MinimizeBox = $false

$title = New-Object System.Windows.Forms.Label
$title.Text = ">> 系統啟動中..."
$title.Font = New-Object System.Drawing.Font("Microsoft JhengHei", 13, [System.Drawing.FontStyle]::Bold)
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
    "1. 等待網路連線",
    "2. 連線家中 WiFi (蓁蓁)",
    "3. 啟動 TradingView (CDP 9222)",
    "4. 確認 TradingView CDP 就緒",
    "5. 啟動監控伺服器 (port 3000)",
    "6. 等待 port 3000 -> 啟動 ngrok",
    "7. 啟動 WiFi 切換器 (port 8765)",
    "8. 啟動 LINE 家庭 bot (port 5000)",
    "9. 啟動 Claude",
    "10. 啟動 Daikin + Dyson + WiFi 管理 + Sony TV"
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
    $lb.Font = New-Object System.Drawing.Font("Microsoft JhengHei", 9)
    $lb.ForeColor = [System.Drawing.Color]::Gray
    $lb.Location = New-Object System.Drawing.Point(58, $ypos)
    $lb.Size = New-Object System.Drawing.Size(400, 24)
    $form.Controls.Add($lb)
    $labels += $lb
    $y += 36
}

$status = New-Object System.Windows.Forms.Label
$status.Text = "初始化中..."
$status.Font = New-Object System.Drawing.Font("Microsoft JhengHei", 9)
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
Set-Step 0 "running" "等待網路連線中..."
$t = 0
while ($t -lt 60) {
    if (Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet -ErrorAction SilentlyContinue) { break }
    Start-Sleep -Seconds 2; $t += 2; Refresh-UI
}
Set-Step 0 "ok" "網路已就緒"
Start-Sleep -Milliseconds 500

# Step 2 - Connect home WiFi (蓁蓁溫暖的家)
Set-Step 1 "running" "連線家中 WiFi 中..."
# 設定 UTF-8，確保中文 SSID 不亂碼
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 | Out-Null

function Get-CurrentSSID {
    try {
        $ps = [System.Diagnostics.ProcessStartInfo]::new("netsh", "wlan show interfaces")
        $ps.UseShellExecute = $false
        $ps.RedirectStandardOutput = $true
        $ps.StandardOutputEncoding = [System.Text.Encoding]::UTF8
        $proc = [System.Diagnostics.Process]::Start($ps)
        $out = $proc.StandardOutput.ReadToEnd()
        $proc.WaitForExit()
        foreach ($line in $out -split "`r?`n") {
            if ($line -match '^\s+SSID\s+:\s+(.+)$' -and $line -notmatch 'BSSID') {
                return $matches[1].Trim()
            }
        }
    } catch {}
    return ""
}

$curSSID = Get-CurrentSSID
if ($curSSID -like "蓁蓁*") {
    Set-Step 1 "ok" "已連線：$curSSID"
} else {
    # 用 ProcessStartInfo 確保 UTF-8 傳遞中文名稱
    $ci = [System.Diagnostics.ProcessStartInfo]::new("netsh", 'wlan connect name="蓁蓁溫暖的家_MLO"')
    $ci.UseShellExecute = $false; $ci.RedirectStandardOutput = $true; $ci.RedirectStandardError = $true
    $ci.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $cp = [System.Diagnostics.Process]::Start($ci)
    $cp.WaitForExit()

    $wifiOk = $false
    for ($wi = 0; $wi -lt 15; $wi++) {
        Start-Sleep -Seconds 2; Refresh-UI
        $curSSID = Get-CurrentSSID
        if ($curSSID -like "蓁蓁*") { $wifiOk = $true; break }
    }
    if ($wifiOk) { Set-Step 1 "ok" "已連線：$curSSID" }
    else { Set-Step 1 "fail" "WiFi 連線逾時，繼續..."; Start-Sleep -Seconds 2; Refresh-UI }
}
Start-Sleep -Milliseconds 500

# Step 3
Set-Step 2 "running" "啟動 TradingView 中..."
Stop-Process -Name "TradingView" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2; Refresh-UI
# Find real TradingView exe in WindowsApps
$pkg = Get-AppxPackage -Name "TradingView.Desktop" -ErrorAction SilentlyContinue
if ($pkg) {
    $tvExe = Get-ChildItem -Path $pkg.InstallLocation -Filter "TradingView.exe" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
    if ($tvExe) { Start-Process -FilePath $tvExe -ArgumentList "--remote-debugging-port=9222" }
}
Set-Step 2 "ok" "TradingView 已啟動"
Start-Sleep -Seconds 5; Refresh-UI

# Step 4
Set-Step 3 "running" "等待 CDP 就緒 (最多 90 秒)..."
$cdpReady = $false
for ($i = 0; $i -lt 45; $i++) {
    Start-Sleep -Seconds 2; Refresh-UI
    try {
        $r = Invoke-WebRequest -Uri "http://localhost:9222/json/version" -TimeoutSec 2 -UseBasicParsing -ErrorAction Stop
        if ($r.StatusCode -eq 200) { $cdpReady = $true; break }
    } catch {}
}
if ($cdpReady) { Set-Step 3 "ok" "CDP 已就緒"; Start-Sleep -Milliseconds 500 }
else { Set-Step 3 "fail" "CDP 逾時，繼續..."; Start-Sleep -Seconds 3; Refresh-UI }

# Step 5 - kill any existing port 3000 first (可能有多筆 IPv4/IPv6 監聽)
$pids3000 = netstat -ano | Select-String ":3000\s.*LISTENING" | ForEach-Object {
    ($_.ToString().Trim() -split '\s+')[-1]
} | Where-Object { $_ -match '^\d+$' -and $_ -ne '0' } | Select-Object -Unique
foreach ($p in $pids3000) { Stop-Process -Id ([int]$p) -Force -ErrorAction SilentlyContinue }
if ($pids3000) { Start-Sleep -Seconds 1 }
Set-Step 4 "running" "啟動監控伺服器中..."
$mcpDir = "$env:USERPROFILE\Coocolab-Tradingview-MCP"
Start-Process -FilePath "C:\Program Files\nodejs\node.exe" -ArgumentList "src/webhook-server.js" -WorkingDirectory $mcpDir -WindowStyle Hidden
Set-Step 4 "ok" "監控伺服器已啟動"
Start-Sleep -Milliseconds 500

# Step 6 - wait port 3000, then start ngrok for port 3000 + static domain for port 5000
Set-Step 5 "running" "等待 port 3000..."
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
    Set-Step 5 "ok" "ngrok 已啟動 (port 3000 + 5000)"
} else {
    Set-Step 5 "fail" "port 3000 未就緒，略過 ngrok"
}
Start-Sleep -Milliseconds 500

# Step 7
Set-Step 6 "running" "啟動 WiFi 切換器中..."
$wifiScript = "$env:USERPROFILE\wifi-switcher\server.js"
Start-Process -FilePath "C:\Program Files\nodejs\node.exe" -ArgumentList $wifiScript -WindowStyle Hidden
Set-Step 6 "ok" "WiFi 切換器已啟動"
Start-Sleep -Milliseconds 500

# Step 8 - LINE family bot (Python Flask, port 5000)
Set-Step 7 "running" "啟動 LINE 家庭 bot 中..."
$botDir = "$env:USERPROFILE\line-family-bot"
Start-Process -FilePath "python" -ArgumentList "app.py" -WorkingDirectory $botDir -WindowStyle Hidden
Set-Step 7 "ok" "LINE 家庭 bot 已啟動"
Start-Sleep -Milliseconds 500

# Step 9
Set-Step 8 "running" "啟動 Claude 中..."
Start-Process "shell:AppsFolder\Claude_pzs8sxrjxfjjc!Claude"
Set-Step 8 "ok" "Claude 已啟動"
Start-Sleep -Milliseconds 500

# Step 10 - Daikin + Dyson + WiFi manager + Sony TV
Set-Step 9 "running" "啟動 Daikin + Dyson + WiFi 管理 + Sony TV 中..."
$daikinDir = "$env:USERPROFILE\daikin-controller"
Start-Process -FilePath "C:\Program Files\nodejs\node.exe" -ArgumentList "server.js" -WorkingDirectory $daikinDir -WindowStyle Hidden
$dysonDir = "$env:USERPROFILE\dyson-controller"
Start-Process -FilePath "python" -ArgumentList "app.py" -WorkingDirectory $dysonDir -WindowStyle Hidden
Start-Process -FilePath "python" -ArgumentList "wifi_manager.py" -WorkingDirectory $dysonDir -WindowStyle Hidden
# Sony TV (port 9000) - 先清掉舊行程，避免重開機後重複疊加
$pids9000 = netstat -ano | Select-String ":9000\s.*LISTENING" | ForEach-Object {
    ($_.ToString().Trim() -split '\s+')[-1]
} | Where-Object { $_ -match '^\d+$' -and $_ -ne '0' } | Select-Object -Unique
foreach ($p in $pids9000) { Stop-Process -Id ([int]$p) -Force -ErrorAction SilentlyContinue }
$sonyDir = "$env:USERPROFILE\tradingview\sony-tv-control"
Start-Process -FilePath "python" -ArgumentList "app.py" -WorkingDirectory $sonyDir -WindowStyle Hidden
Set-Step 9 "ok" "Daikin + Dyson + WiFi 管理 + Sony TV 已啟動"
Start-Sleep -Milliseconds 500

# Open browsers
Start-Process "http://localhost:3000"
Start-Process "http://localhost:8081/apps"
Start-Sleep -Milliseconds 500

# Done
$form.Text = "啟動完成！"
$title.Text = "*** 所有服務已就緒 ***"
$title.ForeColor = [System.Drawing.Color]::FromArgb(63, 185, 80)
Refresh-UI

$closeBtn = New-Object System.Windows.Forms.Button
$closeBtn.Text = "關閉"
$closeBtn.Font = New-Object System.Drawing.Font("Microsoft JhengHei", 10, [System.Drawing.FontStyle]::Bold)
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
    $status.Text = "全部完成！$i 秒後自動關閉。"
    Refresh-UI
    if (-not $form.Visible) { break }
}
if ($form.Visible) { $form.Close() }
