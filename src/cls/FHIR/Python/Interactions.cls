Class FHIR.Python.Interactions Extends (HS.FHIRServer.Storage.Json.Interactions, FHIR.Python.Helper)
{

Parameter OAuth2TokenHandlerClass As %String = "FHIR.Python.OAuth2Token";

Method OnBeforeRequest(
	pFHIRService As HS.FHIRServer.API.Service,
	pFHIRRequest As HS.FHIRServer.API.Data.Request,
	pTimeout As %Integer)
{
    set tHeader = "HEADER:X-Goog-Authenticated-User-Id"
    // Upper case the header name
    set tHeader = $zconvert(tHeader,"U")
    set toto = "t"_$char(34)_tHeader_$char(34)
    // replace - with _
    set tHeader = $TRANSLATE(tHeader,"-","_")
    if pFHIRRequest.AdditionalInfo.GetAt(tHeader)'= "" {
        do ##class(%SYS.System).WriteToConsoleLog(pFHIRRequest.AdditionalInfo.GetAt(tHeader),0,0,"FHIR.Server")
    }
}

}
