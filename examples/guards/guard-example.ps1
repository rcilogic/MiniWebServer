#
#  Copyright (c) 2023 Konstantin Gorshkov (see https://github.com/rcilogic). All Rights Reserved
#  This code is licensed under MIT license (see LICENSE.txt for details)
#

# This simple guard checks that the correct API key value was passed in the query string.
# You are free to use any other available methods, such as the Authorization header or cookies, in your guards.
# Additionally, you can also modify the request here.

# The server provides a MWSRequest object as an input variable.
$request = @($input)[0]


$apiKey = $request.context.Request.queryString['apiKey']

if ( $apiKey -ne '12345' ) {
    #Write-Host guard
    # Output info to the console
    $request.log("[guard-example] $($request.context.Request.RemoteEndPoint.Address) => Access denied!", 'red')
   
    # Throw an error and close the connection. So the rest of the request will not be executed.
    $request.throwError(403, 'Access denied!')
}