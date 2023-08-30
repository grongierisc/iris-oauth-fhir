Class FHIR.Python.Interactions Extends (HS.FHIRServer.Storage.Json.Interactions, FHIR.Python.Helper)
{

Parameter OAuth2TokenHandlerClass As %String = "FHIR.Python.OAuth2Token";

Method %OnNew(pStrategy As HS.FHIRServer.Storage.Json.InteractionsStrategy) As %Status
{
	// %OnNew is called when the object is created.
	// The pStrategy parameter is the strategy object that created this object.
	// The default implementation does nothing
	// Frist set the python path from an env var
	set ..PythonPath = $system.Util.GetEnviron("INTERACTION_PATH")
	// Then set the python class name from the env var
	set ..PythonClassname = $system.Util.GetEnviron("INTERACTION_CLASS")
	// Then set the python module name from the env var
	set ..PythonModule = $system.Util.GetEnviron("INTERACTION_MODULE")

	if (..PythonPath = "") || (..PythonClassname = "") || (..PythonModule = "") {
		set ..PythonPath = "/irisdev/app/src/python/"
		set ..PythonClassname = "CustomInteraction"
		set ..PythonModule = "custom"
	}
    
	// Then set the python class
	do ..SetPythonPath(..PythonPath)
	set ..PythonClass = ##class(FHIR.Python.Interactions).GetPythonInstance(..PythonModule, ..PythonClassname)

	quit ##super(pStrategy)
}

Method OnAfterRequest(
	pFHIRService As HS.FHIRServer.API.Service,
	pFHIRRequest As HS.FHIRServer.API.Data.Request,
	pFHIRResponse As HS.FHIRServer.API.Data.Response)
{
	// OnAfterRequest is called after each request is processed.
	if $ISOBJECT(..PythonClass) {
		set body = ##class(%SYS.Python).None()
		if pFHIRResponse.Json '= "" {
			set jsonLib = ##class(%SYS.Python).Import("json")
			set body = jsonLib.loads(pFHIRResponse.Json.%ToJSON())
		}
		do ..PythonClass."on_after_request"(pFHIRService, pFHIRRequest, pFHIRResponse, body)
	}
}

}
