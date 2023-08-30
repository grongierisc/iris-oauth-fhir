Class FHIR.Python.Interactions Extends (HS.FHIRServer.Storage.Json.Interactions, FHIR.Python.Helper)
{

Parameter OAuth2TokenHandlerClass As %String = "FHIR.Python.OAuth2Token";

Method OnAfterRequest(
	pFHIRService As HS.FHIRServer.API.Service,
	pFHIRRequest As HS.FHIRServer.API.Data.Request,
	pFHIRResponse As HS.FHIRServer.API.Data.Response)
{
    // extract the token from the header
    set tHeader = "HEADER:X-Goog-Authenticated-User-Id"
    // Upper case the header name
    set tHeader = $zconvert(tHeader,"U")
    // replace - with _
    set tHeader = $TRANSLATE(tHeader,"-","_")
    set tHeaderValue = pFHIRRequest.AdditionalInfo.GetAt(tHeader)
    if pFHIRRequest.AdditionalInfo.GetAt(tHeader) = "" {
        set tHeaderValue = "None"
    }

    // Get the resource verb
    set tVerbe = pFHIRRequest.RequestMethod

    // Get the URL
    // Extract the URL from the request
    set tUrl = "/"_pFHIRRequest.RequestPath
    if pFHIRRequest.QueryString '= "" {
        set tUrl = tUrl_"?"_pFHIRRequest.QueryString
    }

    // Get protocol
    set tProtocol = "HTTP/1.1"

    // Response code
    set tResponseCode = pFHIRResponse.Status

    // Get the IP address
    set tIP = pFHIRRequest.AdditionalInfo.GetAt("ClientAddr")
    
    // Create log entry
    // Format ClientAddr "GET /fhir/r4/Patient?Name=toto HTTP/1.1" 200 token
    set line = tIP_" """_tVerbe_" "_tUrl_" "_tProtocol_""" "_tResponseCode_" "_tHeaderValue
    do ##class(%SYS.System).WriteToConsoleLog(line,0,0,"FHIR.Server")
}

}
