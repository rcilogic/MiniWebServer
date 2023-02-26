#
#  Copyright (c) 2023 Konstantin Gorshkov (see https://github.com/rcilogic). All Rights Reserved
#  This code is licensed under MIT license (see LICENSE.txt for details)
#

# Main route
$webServer.staticRoutes['/'] = @{
    path  = "./htdocs" 
    index = "index.html" # , "index.ps1"

    # Guards. Guards are executed first. They can modify the response and also abort the request execution. 
    # Provide guard with a script block
    # guard = { $request = @($input) ; ... }
    
    # Provide guard with a script file ('.ps1'). Guard's can modify the response and also abort the request execution.
    # guardFiles = './path/to/guard-file.ps1' # ,  './path/to/guard-file2.ps1'

    # Enable script execution (only '.ps1' files are supported)
    # executableScripts = $true
   
    # Enable directory browsing if the index file is not found.
    # directoryBrowse   = $true
    
    # If single ingex is enabled, all child route directories will reference the index file in the route's root directory.
    # singleIndex       = $false
    
    # Disable response compression
    # useCompression    = $false
}


# -------------------- Examples -------------------- #

# Uncomment to enable example routes.
<# 

# Static route:
$webServer.staticRoutes['/examples'] = @{
    path              = "./examples/htdocs" 
    useCompression    = $true
    executableScripts = $true
    directoryBrowse   = $true
    index             = "index.html", "index.ps1"
    singleIndex       = $false
}


# Static route with a guard file:
$webServer.staticRoutes['/examples/secured-by-guard/'] = @{
    path            = "./examples/htdocs/secured-by-guard/" 
    guardFiles      = './examples/guards/guard-example.ps1'
    directoryBrowse = $true
}

# Static route with single index:
$webServer.staticRoutes['/examples/single-index'] = @{
    path              = "./examples/htdocs/single-index/" 
    index             = "index.html", "index.ps1"
    singleIndex       = $true
    executableScripts = $true
}


# Scripted route with parameters
$webServer.routes['get /examples/greet/:name'] = { $request = @($input)[0]
    $name = $request.params['name']
    "Hello, $name!"
}


# Scripted route with a guard
$webServer.routes['get /examples/context-info'] = { $request = @($input)[0] 
    # Apply the guard file
    if (-not $request.guardCheck('./examples/guards/guard-example.ps1')) { return }

    # Set a custom MIME type. You can also use 'text/json' instead of the preloaded server MIME types.
    $request.mimeType = $request.server.mimeTypes['.json']

    # Return context in JSON format
    $request.context | ConvertTo-Json  -Depth 3
}

#>
