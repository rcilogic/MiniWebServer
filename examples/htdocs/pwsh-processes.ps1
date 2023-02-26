Get-Process *pwsh* | Select-Object Id, ProcessName, WS, CPU | ConvertTo-Json
