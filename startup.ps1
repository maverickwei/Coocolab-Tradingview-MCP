# 等待網路連線就緒
$timeout = 30
$elapsed = 0
while ($elapsed -lt $timeout) {
    if (Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet -ErrorAction SilentlyContinue) { break }
    Start-Sleep -Seconds 2
    $elapsed += 2
}

# 啟動 TradingView（含 CDP port 9222）
Start-Process -FilePath "C:\Program Files\nodejs\node.exe" -ArgumentList "src/cli/index.js launch" -WorkingDirectory "C:\Users\顏家涵\Coocolab-Tradingview-MCP" -WindowStyle Hidden

# 啟動台指期監控網頁（port 3000）
Start-Process -FilePath "C:\Program Files\nodejs\node.exe" -ArgumentList "src/webhook-server.js" -WorkingDirectory "C:\Users\顏家涵\Coocolab-Tradingview-MCP" -WindowStyle Hidden

# 啟動 Wi-Fi 切換器（port 8765）
Start-Process -FilePath "C:\Program Files\nodejs\node.exe" -ArgumentList "C:\Users\顏家涵\wifi-switcher\server.js" -WindowStyle Hidden

# 啟動 Claude
Start-Process "shell:AppsFolder\Claude_pzs8sxrjxfjjc!Claude"

# 等 port 3000 就緒後啟動 ngrok
Start-Sleep -Seconds 8
Start-Process -FilePath "C:\Users\顏家涵\AppData\Local\Microsoft\WinGet\Packages\Ngrok.Ngrok_Microsoft.Winget.Source_8wekyb3d8bbwe\ngrok.exe" -ArgumentList "http 3000" -WindowStyle Hidden
