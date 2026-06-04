# =============================================
# 蓁蓁開機啟動腳本
# 順序：網路 → TradingView CDP → 確認有資料 → 監控網頁 → 其他
# =============================================

# 1. 等待網路就緒
$timeout = 60; $elapsed = 0
while ($elapsed -lt $timeout) {
    if (Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet -ErrorAction SilentlyContinue) { break }
    Start-Sleep -Seconds 2; $elapsed += 2
}

# 2. 啟動 TradingView（CDP port 9222）
Start-Process -FilePath "C:\Program Files\nodejs\node.exe" `
    -ArgumentList "src/cli/index.js launch" `
    -WorkingDirectory "C:\Users\顏家涵\Coocolab-Tradingview-MCP" `
    -WindowStyle Hidden

# 3. 等待 TradingView CDP 就緒（最多 60 秒）
$cdpReady = $false
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 2
    try {
        $res = Invoke-WebRequest -Uri "http://localhost:9222/json/version" -TimeoutSec 2 -UseBasicParsing -ErrorAction Stop
        if ($res.StatusCode -eq 200) { $cdpReady = $true; break }
    } catch {}
}

if (-not $cdpReady) {
    # CDP 還沒好，多等幾秒
    Start-Sleep -Seconds 10
}

# 4. ✅ TradingView 已就緒 → 啟動台指期監控網頁（port 3000）
Start-Process -FilePath "C:\Program Files\nodejs\node.exe" `
    -ArgumentList "src/webhook-server.js" `
    -WorkingDirectory "C:\Users\顏家涵\Coocolab-Tradingview-MCP" `
    -WindowStyle Hidden

# 5. 等 port 3000 就緒後啟動 ngrok
$ngrokStarted = $false
for ($i = 0; $i -lt 15; $i++) {
    Start-Sleep -Seconds 2
    $conn = Test-NetConnection -ComputerName localhost -Port 3000 -WarningAction SilentlyContinue
    if ($conn.TcpTestSucceeded) { $ngrokStarted = $true; break }
}

if ($ngrokStarted) {
    Start-Process -FilePath "C:\Users\顏家涵\AppData\Local\Microsoft\WinGet\Packages\Ngrok.Ngrok_Microsoft.Winget.Source_8wekyb3d8bbwe\ngrok.exe" `
        -ArgumentList "http 3000" -WindowStyle Hidden
}

# 6. 啟動 Wi-Fi 切換器（port 8765）
Start-Process -FilePath "C:\Program Files\nodejs\node.exe" `
    -ArgumentList "C:\Users\顏家涵\wifi-switcher\server.js" `
    -WindowStyle Hidden

# 7. 啟動 Claude
Start-Process "shell:AppsFolder\Claude_pzs8sxrjxfjjc!Claude"
