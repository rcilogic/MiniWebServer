#
#  Copyright (c) 2023 Konstantin Gorshkov (see https://github.com/rcilogic). All Rights Reserved
#  This code is licensed under MIT license (see LICENSE.txt for details)
#

class MiniWebServer {
    [string]$httpURL
    [bool]$useCompression = $true
    [hashtable]$routes = @{}
    [hashtable]$staticRoutes = @{}
    [int]$requestThrottleLimit = 100
    [int]$requestTimeout = 30
    
    hidden [System.Net.HttpListener]$httpListener
    hidden [hashtable]$mimeTypes = @{}    
    hidden [hashtable] $routesRegex = @{}
    hidden $serverJob 
    hidden [string]$serverPath = (Get-Item $PSScriptRoot/.. ).FullName
    hidden $MWSRequestType
    

    MiniWebServer(
        [string]$httpURL
    ) {
        $this.httpURL = $httpURL
        $this.httpListener = [System.Net.HttpListener]::new()
        $this.httpListener.Prefixes.Add($this.httpURL)       
    }

    # Server Job
    hidden [void]startServerJob() {
        $this.serverJob = $this | Start-ThreadJob -ThrottleLimit 1000000 -StreamingHost $global:Host {
            $server = @($input)[0]  

            while ($server.httpListener) {  
                # Waiting for a request    
                $request = $server.MWSRequestType::new($server, $server.httpListener.GetContext())  
                
                # Processing the request
                $jobsCount = (Get-Job | Where-Object { $_.State -ne "Completed" }).count
                if ($jobsCount -lt $server.requestThrottleLimit) {
                    $request.activeRequestsCount = $jobsCount + 1
                    $request | Start-ThreadJob  -StreamingHost $global:Host { @($input)[0].process() }
                }
                else { $request.throwError(503, 'Service Unavailable') }
                Get-Job | Receive-Job
            
                # Cleaning finished or hanging request jobs
                Get-Job | Where-Object { ($_.State -eq "Completed") -or ($_.PSBeginTime.AddSeconds($this.requestTimeout + 60) -lt (Get-Date)) } | Remove-Job  -Force
            }
        }
    }  

    # Convertinng routes keys to regex strings
    hidden [void]compileRoutes() {
        foreach ($routeString in $this.routes.Keys) {
            # Converting a human-friendly route string to a regex pattern. Example: '/server/:id' => '^/server/(?<id>[^/]+)/*(\?.+)?`$'
            $routeRegex = $routeString -replace ':', '(?<' -replace '(?<=\(\?\<[^/]+)(/|$)', '>[^/]+)/' -replace '/$', ''
            $this.routesRegex["^$routeRegex/*(\?.+)?`$"] = $this.routes[$routeString]
        }

        foreach ($staticRouteString in $this.staticRoutes.Keys) {
            # Prepearing a regex for the static route. Example: '/server/' => '^/?server(/|$)'
            $this.staticRoutes.$staticRouteString["routeRegex"] = $staticRouteString -replace '^/?', '^/?' -replace '/$', '' -replace '$', '(/|$)'
        }
    }

    hidden [void]loadMimeTypes() {
        $mimesTable = Import-Csv -Path "$PSScriptRoot/mime.csv" -Delimiter '|'
        
        foreach ($mime in $mimesTable) {
            $mime.Extension -split ',' | ForEach-Object {
                $this.mimeTypes[$_] = $mime.MIMEType
            }
        } 
    }


    [void]run() {
        try {
            $this.httpListener.Start() 
        }
        catch {           
            Write-Host "Unable to start server: $_" -ForegroundColor Red
            return
        }                
        
        if ($this.httpListener.IsListening) {
            Write-Host "HTTP has started at $($this.httpURL)" -ForegroundColor Cyan
        }

        $this.loadMimeTypes()
        $this.compileRoutes()
        $this.startServerJob()
      
        # User menu
        while ($true) {
            Write-Host ""
            Write-Host "Type 0 to exit: " -ForegroundColor Green

            switch -regex (Read-Host) {
                '^(0|exit)' { 
                    $this.shutdown()
                    return
                }   
                '^(log)$' { Receive-Job $this.serverJob }
            }       
        }
    }

    [scriptblock]loadScriptBlockFromFile([string]$filePath) {
        return [scriptblock]::Create((Get-Content $filePath -Raw))
    }

    hidden [void]shutdown() {
        $this.httpListener.Close()
        Stop-Job ($this.contextJobs + $this.serverJob)
        Remove-Job ($this.contextJobs + $this.serverJob)  -Force           
        Write-Host "HTTP has stopped " -ForegroundColor Cyan 
    }
}
