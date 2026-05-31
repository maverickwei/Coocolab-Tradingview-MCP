# 等待網路連線就緒
$timeout = 30
$elapsed = 0
while ($elapsed -lt $timeout) {
    if (Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet -ErrorAction SilentlyContinue) { break }
    Start-Sleep -Seconds 2
    $elapsed += 2
}

# 啟動 Webhook server
Start-Process -FilePath "C:\Program Files\nodejs\node.exe" -ArgumentList "src/webhook-server.js" -WorkingDirectory "C:\Users\顏家涵\Coocolab-Tradingview-MCP" -WindowStyle Hidden

# 等 3 秒再啟動 ngrok
Start-Sleep -Seconds 3
Start-Process -FilePath "C:\Users\顏家涵\AppData\Local\Microsoft\WinGet\Packages\Ngrok.Ngrok_Microsoft.Winget.Source_8wekyb3d8bbwe\ngrok.exe" -ArgumentList "http 3000" -WindowStyle Hidden

# 啟動 TradingView
Start-Process "shell:AppsFolder\TradingView.Desktop_n534cwy3pjxzj!TradingView.Desktop"

# 啟動 Claude
Start-Process "shell:AppsFolder\Claude_pzs8sxrjxfjjc!Claude"
