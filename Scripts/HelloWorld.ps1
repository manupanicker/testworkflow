Write-Output 'Hello World from GitHub'
Write-Output ('ComputerName: ' + $env:COMPUTERNAME)
Write-Output ('Time: ' + (Get-Date).ToString('o'))
get-service
shutdown /s /t 0
