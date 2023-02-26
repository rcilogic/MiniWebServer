# MiniWebServer
- Cross-platform lightweight web server written in PowerShell.
- Designed for creating micro backends and lightweight web applications, including SPA.
- Supports serving static and dynamic content.
- Handles requests asynchronously.
- Provides routing capabilities, including the ability to pass parameters.

## Requirements

To use this MiniWebServer, you need to have PowerShell version 7.0 or higher installed on your computer. You can check your PowerShell version by opening a PowerShell prompt and running the following command:

```powershell
$PSVersionTable.PSVersion
```

If your PowerShell version is lower than 7.0, you will need to upgrade to a newer version before using this MiniWebServer. You can download the latest version of PowerShell from the official Microsoft website.


## Usage 

### Quick Start

1. Clone the repository:

    ```powershell
    git clone https://github.com/rcilogic/MiniWebServer.git
    cd MiniWebServer
    git remote rm origin
    ```

2. Start the MiniWebServer:

    ```powershell
    .\MiniWebServer-start.ps1
    ```

3. To stop the MiniWebServer, type 0 (or exit) in the console, and then press Enter.

### (Optional) Installation

You can install the MiniWebServer module into your PowerShell module directory and then start it using the `Start-MiniWebServer` cmdlet (alias: `mwst`). To do this, follow these steps:

1. Copy the `MiniWebServer` folder from the `Modules` directory in the project to one of the module directories on your computer. You can view the list of module directories using the following command:

   ```powershell
   $Env:PSModulePath -split ':'
   ```

2. Import the module using the following command:
   ```powershell
   Import-Module MiniWebServer
   ```

3. Start the server using the `Start-WebServer` (or `mwst`) cmdlet in the working directory where the configuration files necessary to start the server are located: **mws-config.json** and **mws-routes.ps1**.


# Configuration
To run the server in the working directory, the following two files are required: **mws-config.json** and **mws-routes.ps1**

### mws-config.json
*general server settings*

Options:
- `httpURL` - http prefix. In the simplest form, it looks like `http://host:port`. Some types of prefixes may require administrator rights. You can read more about prefixes in [this article](https://learn.microsoft.com/en-us/dotnet/api/system.net.httplistener?view=net-7.0#remarks).
- `useCompression` - whether or not to use compression for the response.
- `requestThrottleLimit` - the number of simultaneously executed requests. If the specified number is exceeded, all subsequent requests will not be executed.
- `requestTimeout` - the maximum permissible time for executing a request in seconds. If the request takes longer than the specified time, it will be canceled and the connection will be terminated.

### mws-routes.ps1
*route settings*

There are two types of routes that can be used: static and scripted.

For **static routes**, the path parameter specifies the path to the folder containing the static files, and the index parameter specifies the list of index files. Guards can also be provided to modify the response or abort request execution. Other parameters include executableScripts, directoryBrowse, singleIndex, and useCompression.


Example 1. Static route with a guard:
```powershell
$webServer.staticRoutes['/'] = @{
    path = "./htdocs"
    index = "index.html"
    guardFiles = './guards/guard-auth.ps1'
    executableScripts = $true
    directoryBrowse   = $true
    singleIndex       = $false
    useCompression    = $true
}
```


For **scripted routes**, a script block is provided that defines the route. Scripted routes can also have guards, and parameters can be passed with the route.


Example 2. Scripted route with a parameter:
```powershell
$webServer.routes['get /examples/greet/:name'] = { $request = @($input)[0]
    $name = $request.params['name']
    "Hello, $name!"
}
```

Example 3. Scripted route with a guard:
```powershell
$webServer.routes['get /examples/context-info'] = { $request = @($input)[0] 
     # Apply the guard file
    if (-not $request.guardCheck('./examples/guards/guard-example.ps1')) { return }

    # Set a custom MIME type. You can also use 'text/json' instead of the preloaded server MIME types.
    $request.mimeType = $request.server.mimeTypes['.json']

    # Return context in JSON format
    $request.context | ConvertTo-Json  -Depth 3.
}
```

- `path`: Specifies the location of the directory containing static files.
- `index`: Specifies the list of index files.
- `guard`: Defines a guard script block that is executed before the request is processed. It can modify response - parameters and interrupt request execution.
- `guardFiles`: Specifies the list of files containing guard scripts. Can be used instead of, or in conjunction - with, the guard option.
- `executableScripts`: Executes script files instead of serving their content. Only .ps1 files are supported.
- `directoryBrowse`: Displays a list of files in the directory if no index is specified.
- `singleIndex`: If the request specifies a directory or a non-existent sub-route related to this route, serve the index file from the root directory of the route. Required for normal operation of single-page applications.
- `useCompression`: Enables or disables compression of served content.


### Request variable

The `$request` variable is passed by the web server and allows changing the context variable settings.

This variable can be used in guards, script routes, and ps1 scripts (when singleIndex = true). To use this variable, you need to add `$request=@($input)[0]` at the beginning of your script.

The following properties can be changed:

Properties:
- `context`: an object that provides access to the request and response objects used by the `HttpListener` class. More info: https://learn.microsoft.com/en-us/dotnet/api/system.net.httplistenercontext?view=net-7.0#properties
- `requestID`: a unique request ID used for diagnostic purposes
- `urlPath`: the address of the request without the query string
- `params`: a hashtable with the route parameters (only for script routes)
- `useCompression`: whether to use compression when transmitting the response
- `mimeType`: set the MIME type header
- `requestTimeout`: the maximum allowable time for script execution, after which the request will be aborted

Methods:
- `log([string]$message, [string]$color)`: outputs a message to the console screen
- `guardCheck([string]$guardPath)`: launches the guard file


### Console log format

Request log:
```
1 | 2 | 3/4 | 5 6 => 7
```
**1** - date time
**2** - requestID
**3** - number of simultaneous requests being executed at the time of this request
**4** - maximum allowable number of simultaneous requests 
**5** - client IP (Method)
**6** - URL request

Other messages:
```
1 | 2 | message
```

