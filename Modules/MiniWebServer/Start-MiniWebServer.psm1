#
#  Copyright (c) 2023 Konstantin Gorshkov (see https://github.com/rcilogic). All Rights Reserved
#  This code is licensed under MIT license (see LICENSE.txt for details)
#

function Start-MiniWebServer {
   
    # Loading MiniWebServer classes
    . "$PSScriptRoot/MiniWebServer.ps1"
    . "$PSScriptRoot/MWSRequest.ps1"

    $configPath = './mws-config.json'
    $routesPath = './mws-routes.ps1'
    
    foreach ($requiredFile in @($configPath, $routesPath)) {
        if (-not (Test-Path $requiredFile -PathType Leaf)) {
            Write-Host  "To start the server, the file '$requiredFile' must be present in the working directory."
            return
        }
    }
    
    # Loading server config
    $serverConfig = Get-Content -Path $configPath | ConvertFrom-Json
    $webServer = [MiniWebServer]::new($serverConfig.httpURL)
    $webServer.MWSRequestType = [MWSRequest]
    $serverConfig.PSObject.Properties | ForEach-Object {
        $webServer.($_.Name) = $_.Value
    }
    
    # Loading routes
    . $routesPath
    
    # Starting server
    $webServer.run()
}

New-Alias -Name mwst -Value Start-MiniWebServer

Export-ModuleMember -Function Start-MiniWebServer -Alias mwst

