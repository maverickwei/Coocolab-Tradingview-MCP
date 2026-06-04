# =============================================
# 蓁蓁開機啟動腳本（含進度視窗）
# =============================================
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
"$(Get-Date -Format 'HH:mm:ss')  startup.ps1 開始執行" | Out-File "C:\Users\顏家涵\Coocolab-Tradingview-MCP\startup.log" -Append -Encoding UTF8

# ── 建立主視窗 ────────────────────────────────
$form = New-Object System.Windows.Forms.Form
$form.Text        = "蓁蓁系統啟動中..."
$form.Size        = New-Object System.Drawing.Size(480, 440)
$form.StartPosition = "CenterScreen"
$form.TopMost     = $true
$form.BackColor   = [System.Drawing.Color]::FromArgb(15, 15, 26)
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.MinimizeBox = $false

# 標題
$title = New-Object System.Windows.Forms.Label
$title.Text      = ">>  蓁蓁系統啟動中"
$title.Font      = New-Object System.Drawing.Font("Microsoft JhengHei UI", 14, [System.Drawing.FontStyle]::Bold)
$title.ForeColor = [System.Drawing.Color]::FromArgb(88, 166, 255)
$title.Location  = New-Object System.Drawing.Point(20, 18)
$title.Size      = New-Object System.Drawing.Size(440, 36)
$form.Controls.Add($title)

# 分隔線
$sep = New-Object System.Windows.Forms.Label
$sep.BackColor = [System.Drawing.Color]::FromArgb(48, 54, 61)
$sep.Location  = New-Object System.Drawing.Point(0, 60)
$sep.Size      = New-Object System.Drawing.Size(480, 1)
$form.Controls.Add($sep)

# 步驟清單
$steps = @(
    "1.  等待網路就緒",
    "2.  啟動 TradingView（CDP 9222）",
    "3.  確認 TradingView 有資料",
    "4.  啟動台指期監控網頁（port 3000）",
    "5.  等待 port 3000  ->  啟動 ngrok",
    "6.  啟動 Wi-Fi 切換器（port 8765）",
    "7.  啟動 Claude"
)
$labels = @()
$icons  = @()
$y = 72
foreach ($step in $steps) {
    $icon = New-Object System.Windows.Forms.Label
    $icon.Text      = "[ ]"
    $icon.Font      = New-Object System.Drawing.Font("Consolas", 10, [System.Drawing.FontStyle]::Bold)
    $icon.ForeColor = [System.Drawing.Color]::Gray
    $icon.Location  = New-Object System.Drawing.Point(14, $y + 2)
    $icon.Size      = New-Object System.Drawing.Size(38, 24)
    $form.Controls.Add($icon)
    $icons += $icon

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text      = $step
    $lbl.Font      = New-Object System.Drawing.Font("Microsoft JhengHei UI", 10)
    $lbl.ForeColor = [System.Drawing.Color]::Gray
    $lbl.Location  = New-Object System.Drawing.Point(56, $y + 2)
    $lbl.Size      = New-Object System.Drawing.Size(400, 24)
    $form.Controls.Add($lbl)
    $labels += $lbl

    $y += 36
}

# 底部狀態列
$status = New-Object System.Windows.Forms.Label
$status.Text      = "初始化中..."
$status.Font      = New-Object System.Drawing.Font("Microsoft JhengHei UI", 9)
$status.ForeColor = [System.Drawing.Color]::FromArgb(126, 255, 212)
$status.Location  = New-Object System.Drawing.Point(14, 378)
$status.Size      = New-Object System.Drawing.Size(440, 24)
$form.Controls.Add($status)

# 顯示視窗
$form.Show()
[System.Windows.Forms.Application]::DoEvents()

# ── 輔助函式 ──────────────────────────────────
function Set-Step {
    param([int]$i, [string]$state, [string]$msg)
    switch ($state) {
        "running" { $icons[$i].Text = ">>>";  $icons[$i].ForeColor = [System.Drawing.Color]::FromArgb(255, 198, 0);   $labels[$i].ForeColor = [System.Drawing.Color]::White }
        "ok"      { $icons[$i].Text = "[OK]"; $icons[$i].ForeColor = [System.Drawing.Color]::FromArgb(63, 185, 80);   $labels[$i].ForeColor = [System.Drawing.Color]::FromArgb(63, 185, 80) }
        "fail"    { $icons[$i].Text = "[!!]"; $icons[$i].ForeColor = [System.Drawing.Color]::FromArgb(255, 123, 114); $labels[$i].ForeColor = [System.Drawing.Color]::FromArgb(255, 123, 114) }
        "skip"    { $icons[$i].Text = "[--]"; $icons[$i].ForeColor = [System.Drawing.Color]::Gray;                    $labels[$i].ForeColor = [System.Drawing.Color]::Gray }
    }
    $status.Text = $msg
    [System.Windows.Forms.Application]::DoEvents()
}

# ── 啟動流程 ──────────────────────────────────

# Step 1：等待網路
Set-Step 0 "running" "正在等待網路連線..."
$timeout = 60; $elapsed = 0
while ($elapsed -lt $timeout) {
    if (Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet -ErrorAction SilentlyContinue) { break }
    Start-Sleep -Seconds 2; $elapsed += 2
    [System.Windows.Forms.Application]::DoEvents()
}
Set-Step 0 "ok" "網路就緒"

# Step 2：啟動 TradingView
Set-Step 1 "running" "正在啟動 TradingView..."
Stop-Process -Name "TradingView" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
[System.Windows.Forms.Application]::DoEvents()
Start-Process -FilePath "C:\Users\顏家涵\AppData\Local\TradingView\TradingView.exe" `
    -ArgumentList "--remote-debugging-port=9222"
Set-Step 1 "ok" "TradingView 啟動指令已送出"

# Step 3：等待 CDP 就緒
Set-Step 2 "running" "等待 TradingView CDP 回應（最多 60 秒）..."
$cdpReady = $false
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 2
    [System.Windows.Forms.Application]::DoEvents()
    try {
        $res = Invoke-WebRequest -Uri "http://localhost:9222/json/version" -TimeoutSec 2 -UseBasicParsing -ErrorAction Stop
        if ($res.StatusCode -eq 200) { $cdpReady = $true; break }
    } catch {}
}
if ($cdpReady) {
    Set-Step 2 "ok" "TradingView CDP 就緒"
} else {
    Set-Step 2 "fail" "CDP 等待逾時，繼續..."
    Start-Sleep -Seconds 5
    [System.Windows.Forms.Application]::DoEvents()
}

# Step 4：啟動監控網頁
Set-Step 3 "running" "正在啟動台指期監控網頁..."
Start-Process -FilePath "C:\Program Files\nodejs\node.exe" `
    -ArgumentList "src/webhook-server.js" `
    -WorkingDirectory "C:\Users\顏家涵\Coocolab-Tradingview-MCP" `
    -WindowStyle Hidden
Set-Step 3 "ok" "監控網頁已啟動"

# Step 5：等 port 3000 -> ngrok
Set-Step 4 "running" "等待 port 3000 就緒..."
$ngrokStarted = $false
for ($i = 0; $i -lt 15; $i++) {
    Start-Sleep -Seconds 2
    [System.Windows.Forms.Application]::DoEvents()
    $conn = Test-NetConnection -ComputerName localhost -Port 3000 -WarningAction SilentlyContinue
    if ($conn.TcpTestSucceeded) { $ngrokStarted = $true; break }
}
if ($ngrokStarted) {
    Start-Process -FilePath "C:\Users\顏家涵\AppData\Local\Microsoft\WinGet\Packages\Ngrok.Ngrok_Microsoft.Winget.Source_8wekyb3d8bbwe\ngrok.exe" `
        -ArgumentList "http 3000" -WindowStyle Hidden
    Set-Step 4 "ok" "ngrok 已啟動"
} else {
    Set-Step 4 "fail" "port 3000 未就緒，跳過 ngrok"
}

# Step 6：Wi-Fi 切換器
Set-Step 5 "running" "啟動 Wi-Fi 切換器..."
Start-Process -FilePath "C:\Program Files\nodejs\node.exe" `
    -ArgumentList "C:\Users\顏家涵\wifi-switcher\server.js" `
    -WindowStyle Hidden
Set-Step 5 "ok" "Wi-Fi 切換器已啟動"

# Step 7：Claude
Set-Step 6 "running" "啟動 Claude..."
Start-Process "shell:AppsFolder\Claude_pzs8sxrjxfjjc!Claude"
Set-Step 6 "ok" "Claude 已啟動"

# 全部完成
$form.Text       = "蓁蓁系統啟動完成！"
$title.Text      = "***  蓁蓁系統已就緒  ***"
$title.ForeColor = [System.Drawing.Color]::FromArgb(63, 185, 80)
[System.Windows.Forms.Application]::DoEvents()

# 加入關閉按鈕
$closeBtn = New-Object System.Windows.Forms.Button
$closeBtn.Text      = "關閉"
$closeBtn.Font      = New-Object System.Drawing.Font("Microsoft JhengHei UI", 10, [System.Drawing.FontStyle]::Bold)
$closeBtn.BackColor = [System.Drawing.Color]::FromArgb(63, 185, 80)
$closeBtn.ForeColor = [System.Drawing.Color]::Black
$closeBtn.FlatStyle = "Flat"
$closeBtn.Location  = New-Object System.Drawing.Point(175, 335)
$closeBtn.Size      = New-Object System.Drawing.Size(120, 34)
$closeBtn.Add_Click({ $form.Close() })
$form.Controls.Add($closeBtn)
[System.Windows.Forms.Application]::DoEvents()

# 30 秒倒數自動關閉
for ($i = 30; $i -gt 0; $i--) {
    Start-Sleep -Seconds 1
    $status.Text = "所有服務啟動完成！$i 秒後自動關閉。"
    [System.Windows.Forms.Application]::DoEvents()
    if (-not $form.Visible) { break }
}
if ($form.Visible) { $form.Close() }
