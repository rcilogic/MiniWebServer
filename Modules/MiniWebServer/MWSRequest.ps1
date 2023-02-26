#
#  Copyright (c) 2023 Konstantin Gorshkov (see https://github.com/rcilogic). All Rights Reserved
#  This code is licensed under MIT license (see LICENSE.txt for details)
#

class MWSRequest {
    $server
    $context
    [string]$requestID
    [string]$urlPath 
    [hashtable]$params = @{}
    [bool]$useCompression
    [string]$mimeType 
    [int]$requestTimeout
    
    hidden [int]$activeRequestsCount
    hidden [bool]$isClosed = $false
    hidden [hashtable]$cache = @{}

    MWSRequest($server, $context) {        
        $this.server = $server
        $this.context = $context
        $this.requestID = New-Guid
        $this.urlPath = [System.Web.HttpUtility]::UrlDecode(($context.Request.RawUrl -replace '\?.*', ''))
        $this.useCompression = $server.useCompression
        $this.requestTimeout = $server.requestTimeout
    } 
    
    # Console logging
    [void]log([string]$message, [string]$color) {
        $timeStamp = Get-Date -format "dd.MM.yyyy - HH:mm:ss" 
        $currentConsoleForegroundColor = [System.Console]::ForegroundColor
        [System.Console]::ForegroundColor = $color
        [System.Console]::WriteLine("$timeStamp | $($this.requestID) | $message")
        [System.Console]::ForegroundColor = $currentConsoleForegroundColor 
        
        # The following way does not for correctly:
        # Write-Host $timeStamp, $this.requestID, $message -Separator ' | ' -ForegroundColor $color
    }

    [bool]guardCheck([string]$guardPath) {
        $fileContent = Get-Content $guardPath -Raw -ErrorAction SilentlyContinue 
        $guardScriptBlock = $null -ne $fileContent ? [scriptblock]::Create($fileContent) : { $_.throwError(500, 'Internal server error:') }
        $this.executeScriptBlockWithJob( $guardScriptBlock) | Out-Null
        return $this.isClosed ? $false : $true
    }


    # Processing the request
    [void]process () {  
        $this.log("$($this.activeRequestsCount)/$($this.server.requestThrottleLimit) | $($this.context.Request.RemoteEndPoint.Address) $($this.context.Request.HttpMethod) => $($this.context.Request.Url)", 'Yellow') 

        if ( $this.isClosed -or $this.searchAndApplyScriptedRoute() ) { return }
        if ( $this.isClosed -or $this.searchAndApplyStaticRoute() ) { return }
        $this.throwError(404, 'Not found')
        
    }
    # Searching and applying scripted routes. The function returns 'true' if the route was found. Otherwise, it returns 'false'.
    [bool]searchAndApplyScriptedRoute() {
        $requestString = "$($this.context.Request.HttpMethod) $($this.urlPath)"  
        
        $regexRouteScriptBlock = $null
        foreach ($routeRegex in $this.server.routesRegex.Keys) {
            if ($requestString -match $routeRegex) {
                $this.params = $Matches
                $regexRouteScriptBlock = $this.server.routesRegex[$routeRegex]                
            }
        }
        if ($null -eq $regexRouteScriptBlock) { return $false }

        $responseBody = $this.executeScriptBlockWithJob($regexRouteScriptBlock)
        
        if (-not $this.isClosed) {
            $this.sendResponseString($responseBody)
        }
        return $true
    }

    # Searching and applying static route. The function returns 'true' if the route was found. Otherwise, it returns 'false'.
    [bool]searchAndApplyStaticRoute() {
        $staticRoutes = $this.server.staticRoutes

        $searchResults = $staticRoutes.keys | Where-Object { $this.urlPath -match $staticRoutes.$_.routeRegex } | ForEach-Object -Parallel {
            $staticRoute = ($using:staticRoutes).$_
            $rootPath = $staticRoute.path
            $relativeURL = ($using:this).urlPath -replace $staticRoute.routeRegex, "" 
            $resultPath = "$rootPath/$relativeURL"
    
            # Searching index pages
            if ( 
                ($null -ne $staticRoute.index) -and ($staticRoute.index.count -gt 0) -and 
                ( -not (Test-Path $resultPath -PathType Leaf) ) 
            ) {
                $indexDirectory = $staticRoute.singleIndex ? $rootPath : $resultPath
                foreach ($indexFile in $staticRoute.index) {
                    $indexPath = "$indexDirectory/$indexFile"
                    if (Test-Path  $indexPath -PathType Leaf) {
                        # Replacing a result with the found index file path.
                        $resultPath = $indexPath
                        break
                    }
                }
            }
            return @{
                routeString = $_
                path        = (Test-Path $resultPath) ? $resultPath : $null
                regexLength = $staticRoute.routeRegex.Length
            }
        }

        # The more distinguished route is preferred.
        # For example with a template [/route]/path: [/dir1]/file1 has a more distinguished route than [/]/dir1/file1.
        # The most distinguished route obviously has the longest routeRegex length
        $foundItem = $null
        foreach ($item in $searchResults) {
            if (($null -eq $foundItem) -or ($item.regexLength -gt $foundItem.regexLength)) {
                $foundItem = $item
            }
        }

        if ($null -eq $foundItem) { return $false }

        if ($null -eq $foundItem.path) {
            $this.throwError('404', 'File not found')
            return $true
        }

        $foundStaticRoute = $staticRoutes[$foundItem.routeString]
        $this.useCompression = $foundStaticRoute.useCompression
        
        # Applying guards
        if ($null -ne $foundStaticRoute.guard) {
            $this | ForEach-Object -Parallel $foundStaticRoute.guard
            if ($this.isClosed) { return $true }
        }
        if ($null -ne $foundStaticRoute.guardFiles) {
            foreach ($filePath in $foundStaticRoute.guardFiles) {
                if (-not $this.guardCheck($filePath)) { return $true }
            }
        }
    
 
        Get-Item $foundItem.path | ForEach-Object {
            # Item is a directory
            if ($_.PSIsContainer) {
                if ($foundStaticRoute.directoryBrowse -eq $true) {
                    $childItems = Get-ChildItem $_
                    $parentLink = ($this.urlPath -replace '/$', '' -replace '/[^/]+$') + "/"
                    $queryParams = $this.context.Request.RawUrl -replace '^[^\?]+(\?)?', '?' -replace '\?$', ''
                    $responseBody = -join @( 
                        "<html><style>th,td{text-align: left;}table{min-width: 16rem}tr:first-child th{font-size: 1.3rem;margin-bottom: 1.3rem}h1,h3{margin-bottom: 1.5rem;}</style><body>"
                        "<h1>$($this.urlPath)</h1><hr>"
                        "<h3><a href=`"$parentLink$queryParams`">[To parent directory]</a></h3><table><tr><th>Name</th><th>Size</th></tr>"
                        $childItems | ForEach-Object {                         
                            "<tr><th><a href=`"$($this.urlPath -replace '/$','')/$($_.Name)$queryParams`">$($_.Name)</a></th><td>$($_.PSIsContainer -eq $true ? '&ltdir&gt': "$($_.Length) bytes")</td></tr>"
                        }
                        "</table><hr style=`"margin-top: 8rem;`"><h3>Items count: $($childItems.count)<h3></body></html>"
                    )
                    $this.sendResponseString($responseBody)
                }
                else { $this.throwError(403, 'Forbidden') }
            }
            # Item is a file
            else {
                $fileExtension = $this.getFileExtensionByPath($foundItem.path) 
                
                # If file is a script it must be executed
                if ($foundStaticRoute.executableScripts -and $fileExtension -eq '.ps1') {
                    $fileContent = Get-Content $foundItem.path  -Raw
                    $responseBody = $this.executeScriptBlockWithJob([scriptblock]::Create($fileContent))
                    if (-not $this.isClosed) {
                        $this.sendResponseString($responseBody)
                    }
                }
                # Otherwise, only the contents of the file will be sent
                else { $this.sendResponseFile($foundItem.path) }  
            }
        }
        return $true
    }

    hidden [string]executeScriptBlockWithJob([scriptblock]$scriptBlock) {
        $job = $this | Start-ThreadJob $scriptBlock | Wait-Job -Timeout $this.requestTimeout
        if ($job.State -eq 'Completed') {
            $result = Receive-Job $job | Out-String
        }
        else {
            $this.log('Request Timout', 'red')
            $this.throwError(500, 'Internal Server Error')
            $result = ''
        }
        Remove-Job $job -Force
        return $result
    }

    hidden [string]getFileExtensionByPath($path) {
        if ($null -eq $this.cache.resolvedExtension) {
            $this.cache.resolvedExtension = $path -match '\.[^\./]+($|\?)' ? $Matches[0] : $null 
        }
        return $this.cache.resolvedExtension
    }

    [void]throwError([Int32]$code, [string]$description) {
        $this.context.Response.StatusCode = $code
        $this.context.Response.StatusDescription = $description
        $this.context.Response.OutputStream.Close()
        $this.isClosed = $true
    }

    [void]sendResponseString($body) {
        $buffer = [System.Text.Encoding]::UTF8.GetBytes($body)
        $this.sendResponseData($buffer)
    }

    [void]sendResponseData($buffer) {

        if ($null -ne $this.mimeType) { $this.context.response.ContentType = $this.mimeType }

        try {
            # Sending response with Compression
            if ($this.useCompression -eq $true) {
                $this.context.Response.AddHeader("Content-Encoding", "gzip")
                $gzipStream = [System.IO.Compression.GZipStream]::new($this.context.Response.OutputStream, [System.IO.Compression.CompressionMode]::Compress, $false)
                $gzipStream.Write($buffer, 0, $buffer.Length)
                $gzipStream.Flush()
            }
            # Sending response without Compression
            else {
                $this.context.Response.ContentLength64 = $buffer.Length
                $this.context.Response.OutputStream.Write($buffer, 0, $buffer.Length) 
            }
        }
        catch {
            $this.log("Error: the connection was closed unexpectedly" , 'Red')
        } 

        $this.context.Response.OutputStream.Close()
        $this.isClosed = $true
    }

    [void]sendResponseFile($filePath) {
        $filePath = (Get-Item $filePath).FullName
        $fileExtension = $this.getFileExtensionByPath($filePath)
        $this.context.response.ContentType = $this.mimeType ?? $this.server.mimeTypes.$fileExtension ?? 'application/octet-stream' 
        try {
            $fileStream = [System.IO.File]::OpenRead($filePath)
            $maxBufferSize = 4096 
            $bufferSize = [System.Math]::Min($maxBufferSize, $fileStream.Length)
            $buffer = New-Object byte[] $bufferSize

            # Sending file with Compression
            if ($this.useCompression -eq $true) {
                $this.context.Response.AddHeader("Content-Encoding", "gzip")
                $gzipStream = [System.IO.Compression.GZipStream]::new($this.context.Response.OutputStream, [System.IO.Compression.CompressionMode]::Compress, $false)                
                while (($len = $fileStream.Read($buffer, 0, $bufferSize)) -gt 0) {
                    $gzipStream.Write($buffer, 0, $len)
                }
                $gzipStream.Flush()
            }
            # Sending file without Compression
            else {
                $this.context.Response.ContentLength64 = $fileStream.Length  
                while (($len = $fileStream.Read($buffer, 0, $bufferSize)) -gt 0) {
                    $this.context.Response.OutputStream.Write($buffer, 0, $len) 
                }
            }
        }
        catch {
            $this.log("Error: the connection was closed unexpectedly" , 'Red')
        } 

        $this.context.Response.OutputStream.Close()
        $this.isClosed = $true
    }
}
