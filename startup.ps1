# 等待網路連線就緒
$timeout = 30
$elapsed = 0
while ($elapsed -lt $timeout) {
    if (Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet -ErrorAction SilentlyContinue) { break }
    Start-Sleep -Seconds 2
    $elapsed += 2
}

# 啟動 TradingView（含 CDP，讓 MCP 可以讀取即時價格）
Start-Process -FilePath "C:\Program Files\nodejs\node.exe" -ArgumentList "src/cli/index.js launch" -WorkingDirectory "C:\Users\顏家涵\Coocolab-Tradingview-MCP" -WindowStyle Hidden

# 啟動 Claude（Claude 會透過 .mcp.json 自動啟動 MCP server，並開啟 port 3000）
Start-Process "shell:AppsFolder\Claude_pzs8sxrjxfjjc!Claude"

# 等 port 3000 就緒後再啟動 ngrok
Start-Sleep -Seconds 10
Start-Process -FilePath "C:\Users\顏家涵\AppData\Local\Microsoft\WinGet\Packages\Ngrok.Ngrok_Microsoft.Winget.Source_8wekyb3d8bbwe\ngrok.exe" -ArgumentList "http 3000" -WindowStyle Hidden
