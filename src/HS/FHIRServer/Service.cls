Include (%cspBuild, HS.FHIRServer)

Class HS.FHIRServer.Service Extends (%RegisteredObject, HS.FHIRServer.API.Service, HS.FHIRServer.Util.Bundle, HS.HC.Util.Trace.Helper)
{

// The Configuration Data controlling this service 

Property ConfigData As HS.FHIRServer.API.ConfigData [ Calculated ];

/// The MetadataResource being enforced by this instance
Property MetadataResource As %DynamicObject [ Transient ];

/// The 'schema' node of the SchemaMetadata
Property Schema As HS.FHIRServer.Schema [ Calculated ];

/// The Rest object that has mode='server'
Property RestServerMeta As %DynamicObject [ Transient ];

Property strategy As HS.FHIRServer.API.InteractionsStrategy [ Calculated ];

Property interactions As HS.FHIRServer.API.Interactions [ Calculated ];

Property resourceValidator [ Transient ];

Property RestResourceMap As %DynamicObject [ Transient ];

Property ErrorToHttp [ MultiDimensional, Transient ];

Property RestUrlMap [ MultiDimensional, Transient ];

Parameter INVOCATION = "Queue";

Parameter QUERYIDPARAM = "queryId";

Parameter QUERYPAGEPARAM = "page";

/* ---------- Calculated Properties ------------- */
/// The 'schema' node of the SchemaMetadata
Property %Schema As HS.FHIRServer.Schema [ Private ];

Property %strategy As HS.FHIRServer.API.InteractionsStrategy [ Private ];

Property %interactions As HS.FHIRServer.API.Interactions [ Private ];

Property %ConfigData As HS.FHIRServer.API.ConfigData [ Private ];

Method SchemaGet() As HS.FHIRServer.Schema [ CodeMode = expression ]
{
..%Schema
}

Method strategyGet() As HS.FHIRServer.API.InteractionsStrategy [ CodeMode = expression ]
{
..%strategy
}

Method interactionsGet() As HS.FHIRServer.API.Interactions [ CodeMode = expression ]
{
..%interactions
}

Method ConfigDataGet() As HS.FHIRServer.API.ConfigData [ CodeMode = expression ]
{
..%ConfigData
}

/// @API
/// Called after the service is created to set the configuration.  
/// TODO: This could be a constructor parameter, if that works with Unit Testing and Mocking
Method Configure(serviceInstance As HS.FHIRServer.ServiceInstance)
{
	Set startTime = $ZH

	// Force rebuild of the status mapping
	kill %FHIRServerStatusMap

	// Capture Option Values
	$$$FSLog("User = "_$Username_", Roles: "_$Roles)

	Set ..%strategy = serviceInstance.CreateStrategy()
	if '$IsObject(..%strategy) {
		$$$ThrowFHIR($$$GeneralError, "Unable to create Storage Strategy Class")
	}
	Set ..%interactions = ..%strategy.NewInteractionsInstance()
	
	Set ..%ConfigData = ..%strategy.GetServiceConfigData()

	// HSDD-650: Calculate whether the 'NewInstance' bit is set in the DebugMode flag,
	// then always update the DebugMode flag since it is kept by ZHSLIB in IRIS.Temp
	// and doesn't survive instance restarts
	Set debugMode = (..%ConfigData.DebugMode \ $$$FHIRDebugNewInstance) # 2
	Do ..SetDebugMode(..InstanceKey, debugMode)
	
	/// Load the Schema Metadata
	Set ..%Schema = ..%strategy.schema

	Set ..resourceValidator = $classmethod(..%interactions.#ResourceValidatorClass, "%New", ..%Schema)

	// In STU3+ the resource type is CapabilityStatement.
	Do ..LoadMetadata()
	
	// Populate our Rest URLMap for dispatch processing
	Do ..initRestUrlMap()

	Set endTime = $ZH

	$$$FSLog("Service Configured in " _ (endTime - startTime) _ " secs")

	Quit $$$OK
}

/// Map
/// From (verb, pattern)
///    pattern key:  h:_history, s:_search, v:_validate, m:metadata, 
///                  *:*, +:<value>, -:<not used>, $:<operation name>
/// To: (operationName, targetFields, handlerMethod)
///     targetFields key:  c:Container, t:Type, i:Id, *:Type, -:<none>
Method initRestUrlMap()
{
	Set ..RestUrlMap("GET","h---") = $LB("history-system", "", "History", "r")
	Set ..RestUrlMap("GET","m---") = $LB("capabilities", "", "Metadata", "")
	Set ..RestUrlMap("GET","----") = $LB("search-system", "", "Search", "r")
	Set ..RestUrlMap("GET","+---") = $LB("search-type","t", "Search", "r")
	Set ..RestUrlMap("GET","+++-") = $LB("search-type","cit", "Search", "r")
	Set ..RestUrlMap("GET","++*-") = $LB("search-type","ci*", "Search", "r")
	Set ..RestUrlMap("GET","+h--") = $LB("history-type","t", "History", "r")
	Set ..RestUrlMap("GET","++h-") = $LB("history-instance","ti", "History", "r")
	Set ..RestUrlMap("GET","++h+") = $LB("vread","ti-v", "Read", "r")
	Set ..RestUrlMap("GET","++--") = $LB("read","ti", "Read", "r")
	Set ..RestUrlMap("GET","++$-") = $LB($$$ReqScopeInstance,"tio", "Operation", "r")
	Set ..RestUrlMap("GET","+$--") = $LB($$$ReqScopeType,"to", "Operation", "r")
	Set ..RestUrlMap("GET","$---") = $LB($$$ReqScopeSystem,"o", "Operation", "r")
	Set ..RestUrlMap("PATCH","++--") = $LB("patch","ti", "Patch", "w")
	Set ..RestUrlMap("PATCH","+---") = $LB("patch","t", "ConditionalPatch", "w")
	Set ..RestUrlMap("POST","s---") = $LB("search-system", "", "Search", "r")
	Set ..RestUrlMap("POST","----") = $LB("transaction", "", "Batch", "r")
	Set ..RestUrlMap("POST","+s--") = $LB("search-type","t", "Search", "r")
	Set ..RestUrlMap("POST","+---") = $LB("create","t", "Create", "w")
	Set ..RestUrlMap("POST","++$-") = $LB($$$ReqScopeInstance,"tio", "Operation", "r")
	Set ..RestUrlMap("POST","+$--") = $LB($$$ReqScopeType,"to", "Operation", "r")
	Set ..RestUrlMap("POST","$---") = $LB($$$ReqScopeSystem,"o", "Operation", "r")
	Set ..RestUrlMap("PUT","++--") = $LB("update","ti", "Update", "w")
	Set ..RestUrlMap("PUT","+---") = $LB("update","t", "ConditionalUpdate", "w")
	Set ..RestUrlMap("DELETE","++--") = $LB("delete","ti", "Delete", "w")
	Set ..RestUrlMap("DELETE","+---") = $LB("delete","t", "Delete", "w")
}

/// @API
/// StreamToJSON is a helper method intended for use by callers of the service
/// to convert an input stream to a JSON object.
Method StreamToJSON(
	pStream As %Stream.Object,
	pContentCode As %String) As %DynamicObject
{
	if 'pStream.Size {
		$$$ThrowStatus($$$ERROR($$$HSFHIRErrAPIContractViolation, "Blank FHIR stream specified") )
	}
	
	if ((pContentCode = $$$FHIRContentCodeJSON ) || (pContentCode = $$$FHIRContentCodeJPatch)) {
		Set json = ##class(HS.FHIRServer.Util.JsonHelper).FromJSON(pStream)
		Return json
	} elseif (pContentCode = $$$FHIRContentCodeXML ) {
		// Skip the <?xml ... ?> header of any
		// If the request body is XML, strip off the XML prolog, if present.
		// Any encoded characters have already been converted to internal format
		// (by virtue of having CONVERTINPUTSTREAM=1). Having the XML prolog, if it
		// contains "encoding='UTF-8'", will cause XML parsing to error, as it will
		// try to convert the already-converted characters.
		If (pStream.Read(5) = "<?xml") {
			// Has a prolog, read to the end of it.
			While ('pStream.AtEnd) && (pStream.Read(1) '= ">")  { }
			// Write a new stream from the remainder of the original stream.
			Set tempStream = ##class(%Stream.TmpCharacter).%New()
			While ('pStream.AtEnd)  {
				Do tempStream.Write(pStream.Read())
			}
		} Else {
			Set tempStream = pStream
		}
		Do tempStream.Rewind()
		Return ##class(HS.FHIRServer.Util.XMLToJSON).XMLToJSON(.tempStream, ..%Schema)
	} else {
		$$$ThrowFHIR($$$HSFHIRErrInvalidContentCode, pContentCode)
	}
}

/// LoadMetadata finds the Conformance resources currently in the resource repository
/// and loads them into the CapabilityStatements array, indexed by resource id, each as
/// an %XML.XPATH.Document object.
Method LoadMetadata() [ Internal ]
{
	Set metadataResource = ..%interactions.LoadMetadata()
	if metadataResource '= ..MetadataResource {
		$$$FSLog( "Reloading Metadata Resource, version = " _ metadataResource.meta.versionId)
		// cache the metadata resource
		Set ..MetadataResource = metadataResource
		// Find the 'rest' object that has 'mode'='server'
		Set restArray =..MetadataResource.rest
		Set raMax = $Select(restArray="":0, 1:restArray.%Size())-1
		for ord=0:1:raMax {
			if restArray.%Get(ord).mode="server" {
				set ..RestServerMeta = restArray.%Get(ord)
				Quit
			}
		}
		if ..RestServerMeta="" {
			$$$ThrowFHIR($$$GeneralError, "Metadata does not have a 'rest' object with mode='server'")
		}
		// Build a map of (ResourceType => Resource Capabilities Object)
		Set ..RestResourceMap = $$$NewJSONObject
		Set iter = ..RestServerMeta.resource.%GetIterator()
		while iter.%GetNext(.key , .value ) {
			//$$$FSLog(value.type_"=>"_value)
			Do ..RestResourceMap.%Set(value.type, value)
		}
	}
}

/// @API
/// This is the main dispatcher for FHIR Requests.
Method DispatchRequest(
	pRequest As HS.FHIRServer.API.Data.Request,
	Output pResponse As HS.FHIRServer.API.Data.Response)
{
	if ##class(HS.FHIRServer.ServiceAdmin).IsInstanceDecommissioned(..InstanceKey) {
		$$$ThrowFHIR($$$HSFHIRErrServiceDecommissioned,$$$OutcomeIs(503, "error", "no-store"))
	}
	If $$$FSLogIsActive($$$FSChannelGeneral) {
		$$$FSLog("pRequest.BaseURL    : "_ pRequest.BaseURL)
		$$$FSLog("pRequest.RequestPath: "_ pRequest.RequestPath)
		$$$FSLog("pRequest.QueryString: "_ pRequest.QueryString)
		Try {
			$$$FSLog("pRequest.Username: "_ pRequest.Username)
			$$$FSLog("pRequest.Roles   : "_ pRequest.Roles)
		} Catch fslogEx {
			$$$FSLog("pRequest.Username: (insufficent privilege to access Username)")
			$$$FSLog("pRequest.Roles   : (insufficent privilege to access Roles)")
		}
		Set itemName = ""
		For {
			Set itemValue = pRequest.AdditionalInfo.GetNext(.itemName)
			If itemName = "" Quit
			$$$FSLog("pRequest.AdditionalInfo.GetAt(" _ itemName _ "): " _ itemValue)
		}
	}
	Set startTime = $ZH
	Try {
		Set pResponse = pRequest.NewResponse()
		
		If 'pRequest.IsRecursive {
			/// If this method is being called to process an individual Bundle
			/// entry as part of batch or transaction Bundle processing, then
			/// do NOT update the state of the oauth2TokenHandler object.
			
			Set accessTokenStr = pRequest.AdditionalInfo.GetAt("USER:OAuthToken")
			
			// Update the OAuth token handler object with the current OAuth Token info.
			// SetInstance() will Throw if a token is present and invalid.
			Do ..%interactions.oauth2TokenHandler.SetInstance(accessTokenStr, pRequest.AdditionalInfo.GetAt("USER:OAuthClient"), pRequest.BaseURL, pRequest.Username)
			
			If accessTokenStr '= "" {
				// Get user information from the token object.
				Do ..%interactions.oauth2TokenHandler.GetUserInfo(pRequest.Username, pRequest.Roles, .tokenUserInfo)
				
				// Username returned by GetUserInfo() overrides what we already had in the request.
				Set tokenUser = $Get(tokenUserInfo("Username"))
				Set tokenRoles = $Get(tokenUserInfo("Roles"))
				
				If tokenUser '= "" {
					If tokenUser '= pRequest.Username {
						Set pRequest.Username = tokenUser
						$$$FSLog("pRequest.Username after update from token: " _ pRequest.Username)
					} Else {
						$$$FSLog("Username returned by token handler already matches %Username")
					}
				} ElseIf '..IsRequestAuthenticated() {
					// If unauthenticated, then we need a username from the token.
					$$$FSLog("No Username returned by token handler for Unauthenticated request")
					$$$ThrowFHIR($$$HttpOnlyResponse(401))
				}
				
				If tokenRoles '= "" {
					// Assume that tokenRoles is comma-delimited string.
					// Add the token Roles to the existing request Roles.
					Set addRoles = $ListFromString(tokenRoles)
					Set requestRoles = $ListFromString(pRequest.Roles)
					Set pos = 0
					While $ListNext(addRoles, pos, data) {
						If data '= "" {
						If '$ListFind(requestRoles, data)
							Set $List(requestRoles, *+1) = data
						}
					}
					Set pRequest.Roles = $ListToString(requestRoles)
					$$$FSLog("pRequest.Roles after update from token: " _ pRequest.Roles)
				} Else {
					$$$FSLog("No Roles returned by oauth2TokenHandler GetUserInfo")
				}
			}
			
		}
		
		// Check if the metadata has changed
		Do ..LoadMetadata()
		
		// First check if we have been disabled
		if '##class(HS.FHIRServer.ServiceAdmin).IsInstanceEnabled(..InstanceKey) {
			$$$ThrowFHIR($$$HSFHIRErrServiceDisabled,$$$OutcomeIs(503, "error", "disabled"))
		}
		
		
		Set handlerMethod = ..ParseRequestInputs(pRequest)
		if handlerMethod=""  {
			Set pResponse.Status = 404
			return
		}
		
		
		// Process the '_pretty' query parameter
		Do pRequest.Parameters.GetParameters("_pretty", .params)
		Set pResponse.IsPrettyOut = 0
		if (params > 0 ) {
			// TODO: Do we care if there are more than one of these?  Yes, R4 requires true/false
			//       Could be stricter here.
			Set pResponse.IsPrettyOut = $Case(params(1).value, "1":1, "0":0, "true":1, "false":0, :0)
		}
		
		// Give the Interactions handler an opportunity to prepare for a top-level request
		if 'pRequest.IsRecursive {	
			Do ..%interactions.OnBeforeRequest($this, pRequest, ..%ConfigData.FHIRSessionTimeout)
		}
		
		// 
		$$$FSLog("Dispatch interaction "_pRequest.Interaction_" for "_ pRequest.RequestPath)
		Do $Method($this, handlerMethod, pRequest, pResponse)

	} Catch (tEx) {
		Set tStatus = tEx.AsStatus()
		$$$FSLog("Exception after "_pRequest.Interaction_".  status "_tStatus_", resp.Status"_pResponse.Status)
		//$$$FSLog($System.Status.DisplayError(tEx.AsStatus()))
		Do tEx.StackAsArray(.stack)
		for ord=$Get(stack,0):-1:1 { $$$FSLog("  ["_ord_"] -> "_$get(stack(ord))_" "_$get(stack(ord, "PLACE"))) }
		Do ..SetStatusResponse(pResponse, tStatus)
	}
	if 'pRequest.IsRecursive {	
		Do ..%interactions.OnAfterRequest($this, pRequest, pResponse)
	}
	
	Set endTime = $ZH
	$$$FSLog("Request Completed in "_(endTime-startTime)_" secs: "_pRequest.RequestPath)
}

ClassMethod IsRequestAuthenticated()
{
	return $USERNAME '= "UnknownUser"
}

Method ParseRequestInputs(pRequest As HS.FHIRServer.API.Data.Request) As %Boolean [ Internal ]
{
	#dim handlerMethod as %String = ""
	
	// Parse the Verb and Path according to the FHIR REST spec
	Set tUrl = pRequest.RequestPath
	Set tVerb = $SELECT(pRequest.RequestMethod ="HEAD":"GET", 1:pRequest.RequestMethod)

	If $Extract(tUrl)="/" Set tUrl = $Extract(tUrl, 2, *)
	If $Extract(tUrl, *)="/" Set tUrl = $Extract(tUrl, 1, *-1)
	Set pRequest.RequestPath = tUrl
	Set partCount = $Length(tUrl, "/")
	if partCount > 4 {
		return handlerMethod
	}
	Set key = ""
	Set parts = ""
	for ord=1:1:4 {
		Set part = $Piece(tUrl, "/", ord)
		Set $List(parts,*+1) = part
		// Now encode the part as a single character for later pattern matching.
		Set key = key _ ..mapToKey(part, ord)
	}
	
	if $D(..RestUrlMap(tVerb, key), epMeta) = 0 {
		$$$FSLog("Cannot Dispatch Url: "_tVerb_" "_tUrl_"("_key_")")
		return handlerMethod
	}
	Set pRequest.Interaction = $ListGet(epMeta,1)
	Set fields = $ListGet(epMeta,2)
	Set handlerMethod = $ListGet(epMeta,3)
	Set privilege = $ListGet(epMeta,4)
	
	
	// Save the privilege level needed for the operation.  Used later for
	// OAuth authorization checks
	Do pRequest.AdditionalInfo.SetAt(privilege, "USER:PrivilegeNeeded")
	if (privilege '= "") {
		
		// If privilege is empty, then no authorization is required
		if (..IsRequestAuthenticated()) && (..%ConfigData.RequiredResource '= "") {
			// ..IsRequestAuthenticated() means IRIS authenticated user, regardless of
			// whether valid access token is present or not.
			// Validate authorization against the resource specified in the Configuration
			Set isNoAuthAllowed = (..%ConfigData.DebugMode \ $$$FHIRDebugAllowNoAuthCheck # 2)
			Set privilege = $Case(privilege, "r":"READ", "w":"WRITE")
			If 'isNoAuthAllowed && '$System.Security.CheckUserPermission(pRequest.Username, ..%ConfigData.RequiredResource, privilege) {
				$$$FSLog("Username " _ pRequest.Username _ " does not have required privilege to resource " _ ..%ConfigData.RequiredResource)
				$$$ThrowFHIR($$$HttpOnlyResponse(403))
			}
		}
	}
	
	for ord=1:1:$Length(fields) {
		Set c = $E(fields,ord)
		if (c="t") || (c = "c") {
			// This parameter must be a Resource Type, Validate it
			Set resourceType = $LG(parts,ord)
			// Return 404 Not Found as a response when invalid resource is specified.
			// "invalid" includes invalid resource type.
			if '..%Schema.IsValidResourceType(resourceType) {
				// Invalid resource type is a case where we don't want to return diagnostic info.
				$$$ThrowFHIR($$$HttpOnlyResponse(404))
			}
			
			// Return 404 Not Found as a response when the valid resource type is
			// not supported in the Capabilities statement
			If ..RestResourceMap.%Get(resourceType) = "" {
				$$$ThrowFHIR($$$HSFHIRErrResourceNotSupported, resourceType, $$$OutcomeNotSupported(404))
			}
			if c="t" {
				Set pRequest.Type = resourceType
			} else {
				Set pRequest.Compartment = resourceType
			}
		}
		elseif c="i" { 
			// This is a Resource Id, Validate it
			Set pRequest.Id = ..RequireValidId($LG(parts,ord))
		} elseif c="o" { 
			Set pRequest.OperationScope = pRequest.Interaction
			Set pRequest.Interaction = "operation"
			Set operationName = $Extract($LG(parts,ord), 2, *) 
			// Operation name must start with lower-case and contain lower, number or dash
			if ($Extract(operationName)'?1L) || ($Translate(operationName,"-0123456789abcdefghijklmnopqrstuvwxyz") '= "") {
				$$$ThrowFHIR($$$HSFHIRErrInvalidOperationName, operationName, $$$OutcomeIs(400, "error", "invalid"))
			}
			Set pRequest.OperationName = operationName
		}
		elseif c="v" { 
			Set pRequest.VId = ..RequireValidId($LG(parts,ord))
		} elseif c="*" { 
			Set pRequest.Type = c
		}
	}
	
	// Process the Query String into a QueryParameters Object and identify any
	// registered Search Parameters for the requested type
	// Use the base 'Resource' as the Type if no resource type was provided.  This will limit
	// valid parameters to the shared cross-resource parameters
	if $get(operationName) '= "everything" {
		Set tResourceType = $Select(pRequest.Type="":"Resource", 1: pRequest.Type)
		Set schemaForQueryString = ..%Schema
	} else {
		Set tResourceType = ""
		Set schemaForQueryString = ""
	}
	Set pRequest.Parameters = ##class(HS.FHIRServer.API.Data.QueryParameters).CreateFromQueryString(pRequest.QueryString, schemaForQueryString, tResourceType)
	/// If Prefer:handling=strict, then throw
	If ..IsPreferStrictHandling(pRequest) {
		$$$ThrowOnError(pRequest.Parameters.status)
	}
	return handlerMethod
}

ClassMethod mapToKey(
	part As %String,
	num As %Integer) [ Private ]
{
	if num = 1 {
		if (part = "metadata") return "m"
		if (part = "*") return "*"
	}
	
	if part = "*" return "*"
	if ($Extract(part) = "$") return "$"
	return $Case(part,
		"": "-",
		"_history":"h",
		"_search":"s",
		"_validate":"v",
		:"+")
}

Method SetStatusResponse(
	pResponse As HS.FHIRServer.API.Data.Response,
	tStatus As %Status)
{
	Set pResponse.Json = ##class(HS.FHIRServer.Util.Outcome).CreateFromStatus(tStatus, .httpStatus)
	Set pResponse.Status = httpStatus
}

/// Handle the /metadata request, aka capabilities interaction, per http://hl7.org/fhir/http.html#capabilities.
Method Metadata(
	pRequest As HS.FHIRServer.API.Data.Request,
	pResponse As HS.FHIRServer.API.Data.Response)
{
	set tBase = pRequest.BaseURL
	
	// Log the 'meta' property as found in the CapabilityStatement resource
	// that is currently held by this service instance.
	$$$FSLog("Got ..MetadataResource.meta versionId: "_..MetadataResource.meta.versionId_", lastUpdated: "_..MetadataResource.meta.lastUpdated)
	
	// Copy the metadata resource object that is currently held by
	// this service instance, instead modifying it directly.
	Set tempStream = ##class(%Stream.TmpCharacter).%New()
	Do ..MetadataResource.%ToJSON(tempStream)
	Set tempMetadata = {}.%FromJSON(tempStream)
	
	// Only set URL values if they are meant to be replaced, otherwise use what the InteractionsStrategy has set explicitly
	If (($EXTRACT(tempMetadata.url,1)="<") && ($EXTRACT(tempMetadata.url,*)=">")) {
		Set tempMetadata.url = tBase _ "/metadata"
	}	
	if tempMetadata.implementation '= "" {
		If (($EXTRACT(tempMetadata.implementation.url,1)="<") && ($EXTRACT(tempMetadata.implementation.url,*)=">")) {
			Set tempMetadata.implementation.url = tBase
		}
	}
	
	// Remove the 'meta' property from the CapabilityStatement to be
	// returned. It is useful only for our internal purposes, and is
	// not required by FHIR. Retaining it could give the impression
	// that it is a static resource stored (and retrievable) in the
	// repo itself.
	If tempMetadata.meta '= "" {
		Do tempMetadata.%Remove("meta")
	}
	
	// Set the 'id' property on the CapabilityStatement to a randomly
	// generated value. Returning a stable id on this return could
	// give the impression that it is a static resource stored (and
	// retrievable) in the repo itself.
	Set tempMetadata.id = $ZConvert($system.Util.CreateGUID(), "L")
	
	Set pResponse.Json = tempMetadata
	
	Set pResponse.Status = 200
}

/// Batch processes a FHIR batch or transaction interaction.  The payload
/// of a batch or transaction interaction is a FHIR Bundle (with type = "bundle" or "tranaction" respectively.
Method Batch(
	pRequest As HS.FHIRServer.API.Data.Request,
	pResponse As HS.FHIRServer.API.Data.Response)
{

	// Assert that this system level interaction is allowed as per the Conformance/CapabilityStatement.
	Do ..RequireAllowedSystemInteraction(pRequest.Interaction)

	// Ensure that there is a JSON Payload
	Do ..RequirePayload(pRequest)
	
	Do ..interactions.Batch($this, pRequest, pResponse)
}

Method Create(
	pRequest As HS.FHIRServer.API.Data.Request,
	pResponse As HS.FHIRServer.API.Data.Response)
{
	#dim resourceIn As %DynamicObject
	#dim resourceOut As %DynamicObject = ""
	Set resourceType = pRequest.Type
	Do {
		// Put code into a block so that we can use Quit for an orderly exit
		// Assert that this interaction on this resource type is allowed as per the Conformance/CapabilityStatement.
		Do ..RequireAllowedResourceInteraction(resourceType, pRequest.Interaction)

		// Get the Resource
		Set resourceIn = pRequest.Json

		// Ensure that there is a JSON Payload
		Do ..RequirePayload(pRequest)
		
		// Get whether the resource is part of a transaction so we can use this information in validating
		Set tIsInTransaction = pRequest.AdditionalInfo.GetAt("IsInTransaction")
		
		// Do schema-based validation on the resource.  Throws on error.
		Do ..resourceValidator.ValidateResource(resourceIn, tIsInTransaction)

		// Assert that the type of the given resource matches the named type in the request.
		If (resourceIn.resourceType '= resourceType) {
			$$$ThrowFHIR($$$HSFHIRErrPayloadTypeMismatch, resourceIn.resourceType, resourceType, $$$OutcomeInvalid(400))
		}

		// FHIR Spec: The resource does not need to have an id element (this is one of the few cases where a resource exists
		//  without an id element). If an id is provided, the server SHALL ignore it.
		If resourceIn.id'="" {
			Do resourceIn.%Remove("id")
		}

		// FHIR Spec: If the request body includes a meta, the server SHALL ignore the
		// existing versionId and lastUpdated values.
		If resourceIn.meta'="" {
			Do resourceIn.meta.%Remove("versionId")
			Do resourceIn.meta.%Remove("lastUpdated")
		}
		
		// If an OAuth 2.0 access token was provided with this request, verify
		// that the proposed resource to create is allowed per the token. This
		// will Throw if the create is not allowed.
		Do ..ServiceVerifyResourceContent(resourceIn, ..GetPrivFromRequest(pRequest), 1)
		
		// Get the If-None-Exist search string value for conditional create, and include
		// it in the parameters that get passed to the storage class.  As of 11/30/2017,
		// conditional create is not supported, but at least we have a place for it in
		// this code infrastructure.
		Set tIfNoneExist = pRequest.IfNoneExist
		if tIfNoneExist '= "" {
			// Returns a resource if the conditional clause identifies an exising resource, or
			// null ("") if no matches were found
			Set resourceOut = ..ConditionalCreate(resourceType, tIfNoneExist)	
		}

		// Spec for conditional-create matchin
		// No matches: The server processes the create as above
		// One Match: The server ignores the post and returns 200 OK
		// Multiple matches: The server returns a 412 Precondition Failed error indicating the client's
		// criteria were not selective enough
		if resourceOut '="" {
			// There was a single match so return the proper status code
			Set pResponse.Status = 200
		} else {
			// Create a new resource from the input
			Set newId = ..%interactions.Add(resourceIn)
			set resourceOut = resourceIn

			// Spec for successful Create: The server returns a 201 Created HTTP status code,
			// and SHALL also return a Location header which contains the
			// new Logical Id and Version Id of the created resource version:
			Set pResponse.Status = 201
		}

		Set tResourceVId = resourceOut.meta.versionId
		Set tLastModified = resourceOut.meta.lastUpdated
		// Convert Last Modified to a format appropriate for the "Last-Modified" header.
		// Example of the target format is: "Fri, 01 Dec 2017 23:01:20 GMT"
		Set tLastModified = $$$cspHtoD($ZDTH(tLastModified,3,5))

		Set tLocation = ..GetRequestURLNoQuery(pRequest)_"/"_resourceOut.id_"/_history/"_tResourceVId
		Set pResponse.Location = tLocation
		Set pResponse.ETag = ..ETagValue(tResourceVId)
		Set pResponse.LastModified = tLastModified
		Set pResponse.Id = resourceOut.id
		Set pResponse.VId = tResourceVId

		// If the request has a "Prefer" header with value "return=representation", return the
		// resource as it was saved in the response payload.
		// If tPreferReturn is "representation", then it means that the request has asked
		// the server to return a copy of the resource that was saved.
		Set tPreferReturn = ..GetPreferHeader(pRequest, "return")
		If tPreferReturn="representation" {
			Set pResponse.Json = resourceOut
		}
		// Return the created resource's id in the FHIR Response
		Set pResponse.Id = resourceOut.id
		
	} while 0  // End of Code block
}

Method ConditionalCreate(
	pResourceType As %String,
	pIfNoneExistHeader As %String) As %Boolean [ Private ]
{
	#dim tIfNoneParameters as HS.FHIRServer.API.Data.QueryParameters = ""
	// For booleans, consider the item to be disallowed only when explictly so stated.
	// FHIR REST API for create at http://hl7.org/fhir/STU3/http.html#create says
	// "Servers that don't support the conditional create should return an HTTP 412
	// error and an operation outcome".
	Set tValue = ..IsCapabilitySupported(pResourceType, "conditionalCreate", 0)
	$$$FSLog("supported: "_tValue_", ver: "_ +$E(..%Schema.FHIRVersion))
	if tValue=0 {
		Set httpCode = $Select( ((+$E(..%Schema.FHIRVersion)) < 4):400, 1:412)
		$$$ThrowFHIR($$$HSFHIRErrConditionalCreateNotSupported, pResourceType, $$$OutcomeNotSupported(httpCode))
	}
	
	Set tIfNoneParameters = ##class(HS.FHIRServer.API.Data.QueryParameters).CreateFromQueryString(pIfNoneExistHeader, ..%Schema, pResourceType, 1)
	If (tIfNoneParameters.Count() = 0) {
		$$$ThrowFHIR($$$HSFHIRErrInvalidIfNoneExist, pIfNoneExistHeader)
	}
			
	#dim tResultSet as HS.FHIRServer.Util.SearchResult = ..%interactions.Search(pResourceType, "", "", tIfNoneParameters)
	
	if tResultSet.%Next() {
		// There is at least 1 result
		if tResultSet.%Next() {
			// There are at least 2 results ... fail
			$$$ThrowFHIR($$$HSFHIRErrIfNoneExistsFoundMultiple, pIfNoneExistHeader, $$$HttpIs(412))
		}
		// Return the resource that was uniquely found by the search parameters
		return ..%interactions.Read(tResultSet.ResourceType, tResultSet.ResourceId)
	}
	// No resources found, perform the normal create
	return ""
}

/// Standard handling of _elements as per http://hl7.org/fhir/search.html#elements.
/// When query param _elements is present, include only the resource elements that
/// are specified in _elements. An exception to that is 'meta', which must be
/// included in order to indicate any redaction carried out because of _elements.
Method ElementsStandard(
	pRequest As HS.FHIRServer.API.Data.Request,
	ByRef pResourceObj As %DynamicObject)
{
	Do pRequest.Parameters.GetParameters("_elements", .params)
	
	If params = 0 Quit
	
	Set elementsIncludeList = ""
	
	// Multiple _elements params is allowed. Gather all the values together.
	#dim param As HS.FHIRServer.API.SearchQueryParameter
	
	For i = 1:1:params {
		Set param = params(i)
		// _elements param value is expected to be a comma-delimited list of
		// property names that themselves do not include comma, vertical bar
		// or dollar sign in their names. Use param.value, to allow for use
		// on product versions that do not have IF-2486 (Implement comma-
		// escaping in arguments in FHIR REST requests) implemented.
		For j = 1:1:$Length(param.value, ",") {
			Set elementName = $Piece(param.value, ",", j)
			If (elementName '= "") && ('$ListFind(elementsIncludeList, elementName)) {
				Set $List(elementsIncludeList, *+1) = elementName				
			}
		}
	}
	
	If elementsIncludeList = "" {
		Quit
	}
	
	#dim rsrcIterator As %Iterator.Object = pResourceObj.%GetIterator()
	
	Set removedElement = 0
	
	// Loop through the top level of the resource. Gracefully handle
	// property value longer than MAXLEN if it comes up. 
	For {
		Try {
			Set iteratorBool = rsrcIterator.%GetNext(.propName, .propVal)
			
		} Catch getNextEx {
			If getNextEx.Name = "<MAXSTRING>" {
				Set iteratorBool = rsrcIterator.%GetNext(.propName, .propVal, "stream")
			} Else {
				Throw getNextEx
			}
		}
		If 'iteratorBool Quit
		
		Kill propVal
		
		If propName = "resourceType" Continue
		
		// For primitives not found in _elements, also exclude their extensions.
		// Property name with leading underscore is a JSON-specific notation for
		// a primitive extension, and should not be considered to be a property
		// name that can be specified in _elements.
		Set xpropName = $Select($Extract(propName)'="_": propName, 1:$Extract(propName, 2, *))
		If '$ListFind(elementsIncludeList, xpropName) {
			Do pResourceObj.%Remove(propName)
			Set removedElement = 1
		}
	}
	
	If removedElement {
		Do ##class(HS.FHIRServer.Utils).Subsetted(pResourceObj, "_elements search parameter")
	}
	
	Quit
}

/// Note that both the "read" and "vread" interactions are handled by this method. The only difference
/// between the requests is that vread specifies a version, whereas read does not and is understood
/// to be requesting the current version.
Method Read(
	pRequest As HS.FHIRServer.API.Data.Request,
	pResponse As HS.FHIRServer.API.Data.Response)
{
	// Assert that this interaction on this resource type is allowed as per the Conformance/CapabilityStatement.
	Set interactionName = $Select(pRequest.VId="":"read", 1:"vread")
	Do ..RequireAllowedResourceInteraction(pRequest.Type, interactionName, pRequest.Interaction)

	// Load the first _summary parameter info into the tSummary variable. Only one _summary query parameter is supported in a query.
	Set tSummary = ""
	Set tValue = pRequest.Parameters.GetOneParameterValue("_summary")
	If (tValue'="") {
		If ((tValue="false")||(tValue="text")||(tValue="data")) {
			Set tSummary = tValue
		} Else {
			$$$ThrowFHIR($$$HSFHIRErrInvalidQueryParameterValue, "_summary", tValue)
		}
	}

	Set privNeeded = ..GetPrivFromRequest(pRequest)
	
	Set tResourceObject  = ..%interactions.Read( pRequest.Type, pRequest.Id, pRequest.VId)
	
	// If an OAuth 2.0 access token was provided with this request, verify
	// that the contents of the retrieved resource satisfy the scope(s)
	// and context of the token. This will Throw if the read was not allowed.
	Do ..ServiceVerifyResourceContent(tResourceObject, privNeeded, 1)
	
	Set tIsOK = ..%interactions.PostProcessRead(tResourceObject)
	If 'tIsOK {
		// If The post-processor says no, treat as not found.
		$$$ThrowFHIR($$$HSFHIRErrResourceNotFound, pRequest.Type, pRequest.Id, $$$OutcomeNotFound)
	}

	// Apply _summary query param if present
	If tSummary'="" {
		Do ..Summary(tSummary, .tResourceObject)
	} 

	// If we get here we have a successful Read operation
	Set pResponse.Json = tResourceObject
	// Retrieve the resource meta object. Set the response headers
	// based on meta, even if meta is destined to be redacted by
	// _elements.
	Set rsrcMeta = tResourceObject.meta
	If rsrcMeta '= "" {
		Set tLastModified = rsrcMeta.lastUpdated
		Set tResourceVId = rsrcMeta.versionId
		Set tLastModified = $$$cspHtoD($ZDTH(tLastModified,3,5))
	} Else {
		Set tResourceVId = ""
		Set tLastModified = ""
	}

	If pRequest.Parameters.GetParameterCount("_elements") {
		Do ..ElementsStandard(.pRequest, .tResourceObject)
	}
	// According to the spec ETag should be 'W/"[versionId]"'
	Set pResponse.ETag = ..ETagValue(tResourceVId)
	Set pResponse.LastModified = tLastModified
	set tLocation = ..GetRequestURLNoQuery(pRequest)
	if pRequest.Interaction="read" set tLocation = tLocation_"/_history/"_tResourceVId
	Set pResponse.Location = tLocation

	Set pResponse.Status = 200
}

/// Internal method to evaluate resource content and action against current access token
/// context and scopes. If initial call to token handler VerifyResourceContent fails,
/// and the current token has a context value in play, this method checks to see if the
/// resource has an indirect relationship to the context.
Method ServiceVerifyResourceContent(
	pResourceObj As %DynamicObject,
	pPrivNeeded As %String,
	pAllowSharedResource As %Boolean) [ Internal ]
{
	Try {
		Do ..%interactions.oauth2TokenHandler.VerifyResourceContent(pResourceObj, pPrivNeeded, pAllowSharedResource)
		
	} Catch vrcEx {
		If (vrcEx.Code = $$$HSFHIRErrHttpOnlyResponse) && ($ListGet(vrcEx.Data,1) = "|403") && ($IsObject($Get(pResourceObj))) {
			// Failed with HTTP 403. If context is in play, do a recursive check
			// to see if the resource has an indirect relationship to the context.
			Do ..%interactions.oauth2TokenHandler.GetContextValues(.tokenContextValues)
			If $Data(tokenContextValues) {
				// Don't need to know which context values are present. VerifyResourceContent
				// already figures out what it needs to  know.
				If '..HasIndirectRefToContext(pResourceObj, pPrivNeeded, pAllowSharedResource) {
					// No indirect relationship either. Throw the original VerifyResourceContent error.
					Throw vrcEx
				}
			} Else {
				// No token context in play. Throw the original VerifyResourceContent error.
				Throw vrcEx
			}
		} Else {
			// Was not a simple HTTP 403. Throw the original VerifyResourceContent error.
			Throw vrcEx
		}
	}
}

Method HasIndirectRefToContext(
	pResourceObj As %DynamicObject,
	pPrivNeeded As %String,
	pAllowSharedResource As %Boolean) As %Boolean [ Internal ]
{
	Set hasIndirectReference = 0
	
	// Gather the references that are in the resource.
	Set visitContext("schema") = ..Schema
	Do ##class(HS.FHIRServer.Util.ReferenceVisitor).VisitAll(pResourceObj, .visitContext)
	
	// Check the references to see if any refer to the entity that is the token context.
	Set referenceTo = ""
	For {
		Set referenceTo = $Order(visitContext("_va", "ref", referenceTo))
		If referenceTo = "" Quit
		If $Length(referenceTo, "/") > 1 {
			Set refType = $Piece(referenceTo, "/", *-1)
			Set refId = $Piece(referenceTo, "/", *)
		} Else {
			// This Else covers references to contained resources, which we
			// do not want to follow and evaluate. It also covers references
			// without a resource type. Currently, ReferenceVisitor VisitAll
			// visitContext does not include any indication of the property
			// that holds each reference. Therefore we are unable to discern
			// a resource type in this case (i.e., when reference property
			// has only one target type).
			Continue
		}
		If ..Schema.IsSharedResourceType(refType) Continue
		Try {
			Set tempResourceObj = ..%interactions.Read(refType, refId)
			Do ..ServiceVerifyResourceContent(tempResourceObj, pPrivNeeded, pAllowSharedResource)
			Set hasIndirectReference = 1
			Quit
		} Catch tempException {
		}
	}
	
	Return hasIndirectReference
}

Method ConditionalUpdate(
	pRequest As HS.FHIRServer.API.Data.Request,
	pResponse As HS.FHIRServer.API.Data.Response)
{
	Do ..Update(pRequest, pResponse, 1)
}

Method Update(
	pRequest As HS.FHIRServer.API.Data.Request,
	pResponse As HS.FHIRServer.API.Data.Response,
	isConditional As %Boolean = 0)
{
	set pResponse.Id = pRequest.Id

	// Assert that this interaction on this resource type is allowed as per the Conformance/CapabilityStatement.
	Do ..RequireAllowedResourceInteraction(pRequest.Type, pRequest.Interaction)

	// Ensure that there is a JSON Payload
	Set resourceIn =  ..RequirePayload(pRequest)
	Set resourceId = resourceIn.id
	Set resourceType = resourceIn.resourceType

	// Assert that the type of the given resource matches the named type in the request.
	If (resourceType '= pRequest.Type) {
		$$$ThrowFHIR($$$HSFHIRErrPayloadTypeMismatch, resourceType, pRequest.Type, $$$OutcomeInvalid(400))
	}
	
	// Get whether the resource is part of a transaction so we can use this information in validating
	Set tIsInTransaction = pRequest.AdditionalInfo.GetAt("IsInTransaction")
	
	// Do schema-based validation on the resource.  Throws on error.
	Do ..resourceValidator.ValidateResource(resourceIn, tIsInTransaction)
	
	// If the request contains an If-Match header, assert that the value matches the current version ID of the resource
	// (Used for resource contention - see http://hl7.org/fhir/http.html#concurrency)
	set tIfMatch = pRequest.IfMatch
	Set tIfMatchVersion = ""
	if (tIfMatch '= "") {
		// Assert that it is formatted correctly
		if (tIfMatch '? 1"W/""".E1"""") {
			$$$ThrowFHIR($$$HSFHIRErrInvalidIfMatch, tIfMatch, $$$OutcomeInvalid(405))
		}
		Set tIfMatchVersion = $Extract(tIfMatch,4,*-1)
	}

	// If tPreferReturn is "representation", then it means that the request has asked
	// the server to return a copy of the resource that was saved.
	Set tPreferReturn = ..GetPreferHeader(pRequest, "return")

	// updateCreate specifies whether the server allows update to create new identities
	// (i.e., resource for new resource id). Default to true (allowed) if not found in
	// the Conformance/CapabilityStatement.
	Set tUpdateCreate = ..IsCapabilitySupported(pRequest.Type, "updateCreate", 1)

	$$$ThrowOnError(pRequest.Parameters.status)
	set tSearchParameters = pRequest.Parameters.ExtractSearchParameters()
	
	Set resourceIdToAssign = ""
	Set isUpdate = 1
	
	// As of FHIR R4, http://hl7.org/fhir/http.html#cond-update specifies
	// scenarios where search parameters are specified in the URL.
	If ((+$E(..%Schema.FHIRVersion) > 3) && (tSearchParameters '= "")) {
		Set isConditional = 1
	}
	
	if 'isConditional {
		// Standard Update Request
		// If no id element is provided, or the id disagrees with the id in the URL, the server SHALL respond with an HTTP 400
		if (resourceId = "") || (pRequest.Id '= resourceId) {
			$$$ThrowFHIR($$$HSFHIRErrInvalidUpdateId, $$$OutcomeInvalid(400))
		}
		if tSearchParameters && tSearchParameters.Count() {
			$$$ThrowFHIR($$$HSFHIRErrInvalidUpdate, $$$OutcomeInvalid(400))
		}

		set rsrcMeta = ..%interactions.FindResourceMeta(resourceType, resourceId)
		if rsrcMeta = "" {
			if tUpdateCreate {
				// PUT to a unused url.  Request to force the resource Id.
				// Flag that this is a create (with caller-defined id)
				Set isUpdate = 0
				Set resourceIdToAssign = resourceId
			} else {
				$$$ThrowFHIR($$$HSFHIRErrNoCreateUpdate, resourceType, resourceId, $$$OutcomeIs(405, "error", "forbidden"))
			}
		} 
		if tIfMatchVersion '= "" {
			Set currentId = $$$RsrcMetaVersionId(rsrcMeta)
			if currentId '= tIfMatchVersion {
				Set httpCode = $Select( ((+$E(..%Schema.FHIRVersion)) < 4):409, 1:412)
				$$$ThrowFHIR($$$HSFHIRErrIfMatchViolation, tIfMatchVersion, currentId,$$$OutcomeIs(httpCode, "error", "concurrency"))
			}
		}

	} else {
		// Conditional Update Request
		// conditionalUpdate specifies whether the end point allows checking for the existence
		// of resources that match a given search criteria before updating.
		// For booleans, consider the item to be disallowed only when explictly so stated.
		// FHIR REST API for update at http://hl7.org/fhir/http.html#update says
		// "Servers that don't support the conditional update should return an HTTP 400
		// error and an operation outcome".
		Set tValue = ..IsCapabilitySupported(resourceType, "conditionalUpdate", 1)
		if tValue=0 {
			$$$ThrowFHIR($$$HSFHIRErrConditionalUpdateNotSupported, resourceType, $$$OutcomeNotSupported(400))
		}
		if tSearchParameters="" {
			$$$ThrowFHIR($$$HSFHIRErrInvalidConditionalUpdate, $$$OutcomeInvalid(400))
		}
		
		// Search for the resource to update
		#dim tResultSet as HS.FHIRServer.Util.SearchResult = ..%interactions.Search(resourceType, "" , resourceId, tSearchParameters)
		Set tMatches = 0
		
		While (tResultSet.NextUndeleted()) {
			Set tMatches = tMatches + 1
			If tMatches>1 Quit
			Set matchedResourceId = tResultSet.ResourceId
			$$$FSLog("Conditional Update found Id: "_resourceId)
		}
		
		If tMatches=0 {
			// When No Matches found:
			// http://hl7.org/fhir/http.html#cond-update
			// - No matches, no id provided: The server creates the resource.
			// - No matches, id provided: The server treats the interaction as an Update as Create interaction (or rejects it, if it does not support Update as Create)
			// - No matches, id provided and already exists: The server rejects the update with a 409 Conflict error
			$$$FSLog("Conditional Update found no matches")
			Set resourceId = resourceIn.id
			If ($ListLength(..%interactions.GetVersionList(resourceType,resourceId)) > 0) {
				$$$ThrowFHIR($$$HSFHIRErrConditionalUpdateIDConflict,resourceType,resourceId,$$$OutcomeIs(409,"error","conflict"))
			}			
			If (tUpdateCreate || (""=resourceId)) {
				$$$FSLog("Conditional Update to do Update as Create")
				Set isUpdate = 0
				Set rsrcMeta = ""
				Set resourceIdToAssign = resourceId
			} Else {
				$$$ThrowFHIR($$$HSFHIRErrNoCreateUpdate, resourceType, resourceId, $$$OutcomeIs(405, "error", "forbidden"))
			}
		} ElseIf tMatches=1 {
			if (resourceId '= "") && (resourceId '= matchedResourceId) {
				$$$ThrowFHIR($$$HSFHIRErrPayloadDoesNotMatchResource, resourceId, matchedResourceId, $$$OutcomeInvalid(400))
			}
			// Incoming resource did not have an Id, use the id of the found resource
			Set resourceId = matchedResourceId
			Set resourceIn.id = resourceId
			set rsrcMeta = ..%interactions.GetResourceMeta(resourceType, resourceId)
		} ElseIf tMatches>1 {
			$$$ThrowFHIR($$$HSFHIRErrConditionalUpdateFoundMultiple, $$$OutcomeIs(412, "error", "conflict"))
		}
		
		// If we're here, we've found a single resource to update or create.
		// If the resource does not exist (i.e., going to do Update as Create)
		// and an If-Match header was specified, this check should fail.
		if tIfMatchVersion '= "" {
			Set currentId = $$$RsrcMetaVersionId(rsrcMeta)
			if currentId '= tIfMatchVersion {
				Set httpCode = $Select( ((+$E(..%Schema.FHIRVersion)) < 4):409, 1:412)
				$$$ThrowFHIR($$$HSFHIRErrIfMatchViolation, tIfMatchVersion, currentId,$$$OutcomeIs(httpCode, "error", "concurrency"))
			}
		}
	}
	
	// If an OAuth 2.0 access token was provided with this request, verify
	// that the proposed resource to update is allowed per the token. This
	// will Throw if the update is not allowed.
	Do ..ServiceVerifyResourceContent(resourceIn, ..GetPrivFromRequest(pRequest), 1)
	
	if isUpdate {
		Set newId = ..%interactions.Update(resourceIn)
		$$$FSLog("Updating "_$$$BuildRsrcKey(resourceType, resourceId))
		
	} else {
		Set newId = ..%interactions.Add(resourceIn, resourceIdToAssign, "PUT")
		$$$FSLog("Update Creating "_$$$BuildRsrcKey(resourceType, resourceId))
	}
	
	Set tResourceVId = resourceIn.meta.versionId
	Set tLastModified = resourceIn.meta.lastUpdated
	// Convert Last Modified to a format appropriate for the "Last-Modified" header.
	// Example of the target format is: "Fri, 01 Dec 2017 23:01:20 GMT"
	set tLastModified = $$$cspHtoD($ZDTH(tLastModified,3,5))

	// It is a PUT, therefore the last piece of the URL should be either the
	// resource id (if provided) or the resource type.
	set reqURLNoQuery = ..GetRequestURLNoQuery(pRequest)
	if pRequest.Id = "" {
		If $Piece(reqURLNoQuery, "/", *) = "" {
			Set reqURLNoQuery = reqURLNoQuery _ newId
		} Else {
			Set reqURLNoQuery = reqURLNoQuery _ "/" _ newId
		}
	}
	
	set tLocation = reqURLNoQuery_"/_history/"_tResourceVId
	Set pResponse.Location = tLocation
	Set pResponse.ETag = ..ETagValue(tResourceVId)
	Set pResponse.LastModified = tLastModified
	set pResponse.Id = newId
	set pResponse.VId = tResourceVId

	if tResourceVId=1 {
		// Created
		Set pResponse.Status = 201
	} else {
		// Updated - HTTP OK
		Set pResponse.Status = 200
	}

	// If the request has a "Prefer" header with value "return=representation", return the
	// resource as it was saved in the response payload.
	If tPreferReturn="representation" {
		Set pResponse.Json = resourceIn
	}
}

Method ConditionalPatch(
	pRequest As HS.FHIRServer.API.Data.Request,
	pResponse As HS.FHIRServer.API.Data.Response)
{
	Do ..Patch(pRequest, pResponse, 1)
}

Method Patch(
	pRequest As HS.FHIRServer.API.Data.Request,
	pResponse As HS.FHIRServer.API.Data.Response,
	isConditional As %Boolean = 0)
{
	// Assert that this interaction on this resource type is allowed as per the Conformance/CapabilityStatement.
	Do ..RequireAllowedResourceInteraction(pRequest.Type, pRequest.Interaction)
	
	// Ensure expected PATCH Payload.
	If pRequest.RequestFormatCode = $$$FHIRContentCodeJPatch {
		// JSON Patch payload is expected to be in the request .JSON at this point.
		Set patchPayload = ..RequirePayload(pRequest)
		
	} ElseIf pRequest.RequestFormatCode = $$$FHIRContentCodeXPatch {
		// XML not supported
		$$$ThrowFHIR($$$HSFHIRErrInteractionsNotSupported, pRequest.Type, pRequest.Interaction, "XML Patch", $$$OutcomeNotSupported(400))
		
	} ElseIf '((pRequest.RequestFormatCode=$$$FHIRContentCodeJSON)||(pRequest.RequestFormatCode=$$$FHIRContentCodeXML)) {
		// FHIRPath not supported
		$$$ThrowFHIR($$$HSFHIRErrInteractionsNotSupported, pRequest.Type, pRequest.Interaction, "FHIRPath Patch", $$$OutcomeNotSupported(400))
		
	} Else {
		// This can possibly happen only if not using the standard RestHandler,
		// or if calling FHIRServer Service directly.
		$$$ThrowFHIR($$$HSFHIRErrInteractionsNotSupported, pRequest.Type, pRequest.Interaction, "Unknown Patch", $$$OutcomeNotSupported(400))
	}
	
	// If the request contains an If-Match header, assert that the value matches the current version ID of the resource
	// (Used for resource contention - see http://www.hl7.org/fhir/2015May/http.html#2.1.0.11)
	Set ifMatch = pRequest.IfMatch
	Set ifMatchVersion = ""
	If (ifMatch '= "") {
		// Assert that it is formatted correctly
		If (ifMatch '? 1"W/""".E1"""") {
			$$$ThrowFHIR($$$HSFHIRErrInvalidIfMatch, ifMatch, $$$OutcomeInvalid(405))
		}
		Set ifMatchVersion = $Extract(ifMatch, 4, *-1)
	}
	
	// If tPreferReturn is "representation", then it means that the request has asked
	// the server to return a copy of the resource that was saved.
	Set preferReturn = ..GetPreferHeader(pRequest, "return")
	
	#dim searchParameters As HS.FHIRServer.API.Data.QueryParameters = pRequest.Parameters.ExtractSearchParameters()
	
	If 'isConditional {
		If (searchParameters) && (searchParameters.Count()) {
			$$$ThrowFHIR($$$HSFHIRErrInvalidUpdate, $$$OutcomeInvalid(400))
		}
		
		// Do an actual Read here, instead of FindResourceMeta, since we are going
		// to obtain and pass the resource object eventually anyway. Read will
		// Throw if the resource is not found.
		Set resourceIn  = ..%interactions.Read(pRequest.Type, pRequest.Id)
		Set resourceId = pRequest.Id
		Set resourceType = pRequest.Type
		
		// Since the meta is obtained from a retrieved resource, assume that it has content.
		If ifMatchVersion '= "" {
			Set currentVersionId = resourceIn.meta.versionId
			If currentVersionId '= ifMatchVersion {
				Set httpCode = $Select( ((+$Extract(..%Schema.FHIRVersion)) < 4):409, 1:412 )
				$$$ThrowFHIR($$$HSFHIRErrIfMatchViolation, ifMatchVersion, currentVersionId, $$$OutcomeIs(httpCode, "error", "concurrency"))
			}
		}
		
	} Else {
		// Conditional Patch Request
		// The FHIR REST API spec has a concept of conditional patch, but FHIR CapabilityStatement does not.
		// Use the CapabilityStatement conditionalUpdate value as the basis for checking if conditional
		// Patch is okay.
		
		// conditionalUpdate specifies whether the end point allows checking for the existence
		// of resources that match a given search criteria before updating.
		// For booleans, consider the item to be disallowed only when explictly so stated.
		// FHIR REST API for create at http://hl7.org/fhir/http.html#update says
		// "Servers that don't support the conditional update should return an HTTP 400
		// error and an operation outcome".
		If '..IsCapabilitySupported(pRequest.Type, "conditionalUpdate", 1) {
			$$$ThrowFHIR($$$HSFHIRErrConditionalUpdateNotSupported, resourceType, $$$OutcomeNotSupported(400))
		}
		If searchParameters = "" {
			$$$ThrowFHIR($$$HSFHIRErrInvalidConditionalUpdate, $$$OutcomeInvalid(400))
		}
		
		If '(($IsObject(searchParameters)) && (searchParameters.Count())) {
			$$$ThrowFHIR($$$HSFHIRErrInvalidUpdate, $$$OutcomeInvalid(400))
		}
		
		// Search for the resource to update
		#dim resultSet as HS.FHIRServer.Util.SearchResult = ..%interactions.Search(pRequest.Type, "" , pRequest.Id, searchParameters)
		
		Set matchCount = 0
		
		While (resultSet.NextUndeleted()) {
			If $i(matchCount)
			If matchCount>1 Quit
			Set matchedResourceId = resultSet.ResourceId
			Set matchedResourceType = resultSet.ResourceType
			$$$FSLog("Conditional Patch found Id: "_matchedResourceId)
		}
		
		If matchCount = 0 {
			$$$ThrowFHIR($$$HSFHIRErrConditionalPatchNoMatches, $$$OutcomeIs(404, "error", "not-found"))
			
		} ElseIf matchCount = 1 {
			Set resourceId = matchedResourceId
			Set resourceType = matchedResourceType
			// Do an actual Read here, instead of FindResourceMeta, since we are going
			// to obtain and pass the resource object eventually anyway. Read will
			// Throw if the resource is not found.
			Set resourceIn  = ..%interactions.Read(resourceType, resourceId)
			
		} ElseIf matchCount>1 {
			$$$ThrowFHIR($$$HSFHIRErrConditionalPatchFoundMultiple, $$$OutcomeIs(412, "error", "conflict"))
		}
		
		// If we're here, we've found a single resource to update or create
		// Since the meta is obtained from a retrieved resource, assume it has content.
		If ifMatchVersion '= "" {
			Set currentVersionId = resourceIn.meta.versionId
			If currentVersionId '= ifMatchVersion {
				Set httpCode = $Select( ((+$Extract(..%Schema.FHIRVersion)) < 4):409, 1:412 )
				$$$ThrowFHIR($$$HSFHIRErrIfMatchViolation, ifMatchVersion, currentVersionId, $$$OutcomeIs(httpCode, "error", "concurrency"))
			}
		}
	}
	
	// If an OAuth 2.0 access token was provided with this request, verify
	// that the proposed resource to patch is allowed per the token. This
	// will Throw if the patch is not allowed.
	Do ..ServiceVerifyResourceContent(resourceIn, ..GetPrivFromRequest(pRequest), 1)
	
	// Ensure expected PATCH Payload
	If pRequest.RequestFormatCode = $$$FHIRContentCodeJPatch {
		// JSON Patch payload is expected to be in the request .JSON at this point.
		Set updated = ..%interactions.JSONPatch(patchPayload, resourceIn)
		
	} ElseIf pRequest.RequestFormatCode = $$$FHIRContentCodeXPatch {
		// XML not supported - would already have Thrown earlier
		
	} ElseIf '((pRequest.RequestFormatCode=$$$FHIRContentCodeJSON)||(pRequest.RequestFormatCode=$$$FHIRContentCodeXML)) {
		// FHIRPath not supported - would already have Thrown earlier
	}
	
	If updated {
		// If the resource was actually updated - it would not be updated if the Patch had only
		// 'test' operations - then update it in the repo using the Interactions Update method.
		
		// Get whether the resource is part of a transaction so we can use this information in validating
		Set tIsInTransaction = pRequest.AdditionalInfo.GetAt("IsInTransaction")

		// Validate the Patched resource before saving. Throws upon error.
		Do ..resourceValidator.ValidateResource(resourceIn, tIsInTransaction)
		
		Set newId = ..%interactions.Update(resourceIn)
	}
	
	// Regardless of whether the resource was updated or not, return all the meta info
	// and honor the Prefer return header value.
	
	Set resourceVId = resourceIn.meta.versionId
	Set lastModified = resourceIn.meta.lastUpdated
	
	// Convert Last Modified to a format appropriate for the "Last-Modified" header.
	// Example of the target format is: "Fri, 01 Dec 2017 23:01:20 GMT"
	Set lastModified = $$$cspHtoD($ZDTH(lastModified,3,5))
	
	Set pResponse.Location = ..GetRequestURLNoQuery(pRequest)_"/_history/"_resourceVId
	Set pResponse.ETag = ..ETagValue(resourceVId)
	Set pResponse.LastModified = lastModified
	Set pResponse.Id = resourceIn.id
	Set pResponse.VId = resourceVId
	
	Set pResponse.Status = 200
	
	If preferReturn = "representation" {
		Set pResponse.Json = resourceIn
	}
}

Method Delete(
	pRequest As HS.FHIRServer.API.Data.Request,
	pResponse As HS.FHIRServer.API.Data.Response)
{
	Set resourceType = pRequest.Type
	Set resourceId = pRequest.Id
	Set resourceVId = pRequest.VId
	
	set pResponse.Id = resourceId

	// Per http://www.hl7.org/fhir/STU3/http.html#delete, return status code 204 (No Content)
	// whether the identified resource exists or not and whether the resource is already
	// deleted or not. If this request is for conditional delete, response Status will be
	// unconditionally changed to 200.
	set pResponse.Status = 204

	// delete is similar to update in that it deprecates the old version of the resource and
	// creates a new one, the difference being that for delete, the new version has no content
	// and is marked as deleted

	// Assert that this interaction on this resource type is allowed as per the Conformance/CapabilityStatement.
	// If the server refuses to delete resources of that type as a blanket policy,
	// then it should return the 405 Method not allowed status code.
	Do ..RequireAllowedResourceInteraction(resourceType, pRequest.Interaction)
	
	#dim tSearchParameters as HS.FHIRServer.API.Data.QueryParameters = pRequest.Parameters.ExtractSearchParameters()

	// Must have either resource id or conditional delete search parameters, but not both.
	If (resourceId '= "")&&(tSearchParameters '= "") {
		$$$ThrowFHIR($$$HSFHIRErrInvalidDelete, $$$OutcomeInvalid(400))
	} ElseIf (resourceId = "")&&(tSearchParameters = "") {
		$$$ThrowFHIR($$$HSFHIRErrInvalidConditionalDelete, $$$OutcomeInvalid(400))
	}

	// Verify that conditional delete is allowed by the Conformance/CapabilityStatement.
	Set tConditionalDelete = "multiple"
	If tSearchParameters'="" {
		// conditionalDelete specifies whether the end point allows deleting resources
		// based on matching a given set of criteria (search parameters).  Conformance/
		// CapabilityStatement values for this are "not-supported", "single" and "multiple".
		// Support for conditional delete must be explicitly stated, via the "single" or
		// "multiple" values.
		Set tConditionalDelete = ..GetCapabilityStatus(resourceType, "conditionalDelete")
		If (tConditionalDelete="not-supported")||(tConditionalDelete="") {
			// FHIR REST API for conditional delete at http://hl7.org/fhir/http.html#3.1.0.7.1
			// says "Servers that don't support the conditional update SHOULD return an HTTP 400
			// error and MAY include an OperationOutcome."
			$$$ThrowFHIR($$$HSFHIRErrInteractionNotSupported, resourceType, "conditional-delete", $$$OutcomeNotSupported(400))
		}
		Set maxSearchMatches = ..ConfigData.MaxConditionalDeleteResults
	}

	Set deletedIdList = ##class(%Library.ListOfDataTypes).%New()
	
	Set privNeeded = ..GetPrivFromRequest(pRequest)
	
	If tSearchParameters="" {
		// No parameters, is not a conditional delete.
		// If the resource doesn't exist, do nothing (silently)
		If ..%interactions.oauth2TokenHandler.TokenString '= "" {
			Do ..%interactions.oauth2TokenHandler.VerifyResourceIdRequest(resourceType, resourceId, privNeeded)
			Try {
				Set resourceObj = ""
				Set resourceObj = ..%interactions.Read(resourceType, resourceId)
			} Catch read1Ex {
			}
			If $IsObject(resourceObj) {
				// ServiceVerifyResourceContent will Throw if the check fails.
				Do ..ServiceVerifyResourceContent(resourceObj, privNeeded, 0)
			}
		}
		Set resourceVId = ..%interactions.Delete(resourceType, resourceId)
		If resourceVId'="" Do deletedIdList.Insert(resourceId_","_resourceVId)
	} Else {
		// Request for a conditional delete
		If resourceId '= "" {
			$$$ThrowFHIR($$$HSFHIRErrAPIContractViolation, "Cannot include resource id and conditional delete search parameters on the same delete request")
		} 
		// All okay, proceed with the conditional delete search and deletes.
		#dim tResultSet as HS.FHIRServer.Util.SearchResult = ..%interactions.Search(resourceType, "", "", tSearchParameters)

		// First ensure that the result set is okay per configuration parameters
		// and access token context and/or scopes.
		While (tResultSet.%Next()) {
			If (tConditionalDelete="single")&&(tResultSet.%ROWCOUNT>1) {
				$$$ThrowFHIR($$$HSFHIRErrConditionalDeleteOfMultipleNotSupported, $$$OutcomeNotSupported(400))
			}
			If (tResultSet.%ROWCOUNT > maxSearchMatches) {
				$$$ThrowFHIR($$$HSFHIRErrConditionalDeleteOverflow, maxSearchMatches)
			}
			Set tResourceId = tResultSet.ResourceId
			If ..%interactions.oauth2TokenHandler.TokenString '= "" {
				Do ..%interactions.oauth2TokenHandler.VerifyResourceIdRequest(resourceType, tResourceId, privNeeded)
				Try {
					Set resourceObj = ""
					Set resourceObj = ..%interactions.Read(resourceType, tResourceId)
				} Catch read2Ex {
				}
				If $IsObject(resourceObj) {
					// ServiceVerifyResourceContent will Throw if the check fails.
					Do ..ServiceVerifyResourceContent(resourceObj, privNeeded, 0)
				}
			}
		}

		Do tResultSet.%SetIterator(0)
		
		// Result set is okay, proceed with actual HTTP Delete now.
		While (tResultSet.%Next()) {
			Set tResourceId = tResultSet.ResourceId
			Set tResourceVId = ..%interactions.Delete(resourceType, tResourceId)
			If tResourceVId'="" Do deletedIdList.Insert(tResourceId_","_tResourceVId)
		}
	}
	
	If tSearchParameters="" {
		Set pResponse.ETag = ..ETagValue($Piece(deletedIdList.GetAt(1),",",2))
	} Else {
		If deletedIdList.Count() {
			Set tString = "Deleted resources (type/id/vid): "
			For i = 1:1:deletedIdList.Count() {
				If i > 1 Set tString = tString _ ","
				Set tString = tString _ pRequest.Type _ "/" _ $Piece(deletedIdList.GetAt(i),",",1) _ "/" _ $Piece(deletedIdList.GetAt(i),",",2)
			}
		} Else {
			Set tString = "Conditional delete search found no resources"
		}
  		Set pResponse.Json = ##class(HS.FHIRServer.Util.Outcome).Create("information", tString, "informational")
		Set pResponse.Status = 200
	}
}

Method Search(
	pRequest As HS.FHIRServer.API.Data.Request,
	pResponse As HS.FHIRServer.API.Data.Response)
{
	set tBase = pRequest.BaseURL
	set tType = pRequest.Type

	if tType'="" {
		// Assert that this interaction on this resource type is allowed as per the
		// Conformance/CapabilityStatement. While the FHIR REST API refers to the search by type
		// interaction as "search", the Conformance/CapabilityStatement resource uses value set
		// TypeRestfulInteraction http://hl7.org/fhir/ValueSet/type-restful-interaction for
		// interaction, which specifies a name of "search-type" for this interaction.
		Do ..RequireAllowedResourceInteraction(pRequest.Type, "search-type")
	} else {
		// Assert that this system level interaction on this resource type is allowed as per the
		// Conformance/CapabilityStatement. While the FHIR REST API refers to the system level
		// search interaction as "search", the Conformance/CapabilityStatement resource uses
		// value set TypeRestfulInteraction http://hl7.org/fhir/ValueSet/type-restful-interaction
		// for interaction, which specifies a name of "search-system" for this interaction.
		Do ..RequireAllowedSystemInteraction("search-system")
	}

	// These are HealthShare-specific parameters to use for paging.
	set tQueryId = pRequest.GetParameterValue(..#QUERYIDPARAM)
	set tPage = pRequest.GetParameterValue(..#QUERYPAGEPARAM)

	// Load the first _summary parameter info into the tSummary variable. Only one _summary query parameter is supported in a query.
	Set tSummary = ""
	Set tValue = pRequest.Parameters.GetOneParameterValue("_summary")
	If (tValue'="") {
		If ((tValue="false")||(tValue="text")||(tValue="data")||(tValue="count")) {
			Set tSummary = tValue
		} Else {
			$$$ThrowFHIR($$$HSFHIRErrInvalidQueryParameterValue, "_summary", tValue, $$$OutcomeInvalid(400))
		}
	}
	// Note that the _include and _revinclude parameters cannot be mixed with _summary=text or _summary=count or _count=0.
	Set tInclude = pRequest.Parameters.GetParameterCount("_include")
	Set tRevinclude = pRequest.Parameters.GetParameterCount("_revinclude")
	If (tSummary="text") || (tSummary="count") {
		If (tInclude) {
			$$$ThrowFHIR($$$HSFHIRErrInvalidQueryParameterCombo,"_summary="_tSummary, "_include", $$$OutcomeInvalid(400))
		}
		If (tRevinclude) {
			$$$ThrowFHIR($$$HSFHIRErrInvalidQueryParameterCombo,"_summary="_tSummary, "_revinclude", $$$OutcomeInvalid(400))
		}
	}
	Set tValue = pRequest.Parameters.GetOneParameterValue("_count")
	If (tValue'="") {
		If (tValue'?1.N) {
			$$$ThrowFHIR($$$HSFHIRErrInvalidQueryParameterValue, "_count", tValue, $$$OutcomeInvalid(400))
		}
		If (tValue=0) {
			If (tInclude) {
				$$$ThrowFHIR($$$HSFHIRErrInvalidQueryParameterCombo,"_count=0", "_include", $$$OutcomeInvalid(400))
			}
			If (tRevinclude) {
				$$$ThrowFHIR($$$HSFHIRErrInvalidQueryParameterCombo,"_count=0", "_revinclude", $$$OutcomeInvalid(400))
			}
		}
	}

	// If queryId is not present then this is a new search,
	// as opposed to a search that uses an established
	// cache of results from a previous search.
	#dim tResultSet As HS.FHIRServer.Util.SearchResult
	if (tQueryId="") {
		// Initial Query Request - Perform the query and process the result set.
		set tPage = 1
		Set tResultSet = ..SearchNew(pRequest)
		if '$IsObject($Get(tResultSet)) {
			$$$ThrowFHIR($$$GeneralError, "Unknown search error, resultset object not found")
		}
		If ..IsPreferStrictHandling(pRequest) {
			$$$ThrowOnError(pRequest.Parameters.status)
		}
		
		set tQueryURL = ..GetFullRequestURL(pRequest)
		Set pageCount = tResultSet.Paginate( ..GetQueryPageSize(pRequest), pRequest.Username, pRequest.RequestPath_$Select(pRequest.QueryString'="":"?",1:"")_pRequest.QueryString)
		
		if tResultSet.TotalUndeleted > ..%ConfigData.MaxSearchResults {
			$$$ThrowFHIR($$$HSFHIRErrSearchTooCostly, ..%ConfigData.MaxSearchResults, $$$OutcomeIs(413, "error", "too-costly"))
		}
		
		if pageCount > 1 {
			Do tResultSet.Save()	
		}

		// Handle the Summary Request Here
		if tResultSet.PageSize=0 {
			// From http://hl7.org/fhir/STU3/search.html#count
			// if _count has the value 0, this shall be treated the same as _summary=count:
			// the server resturns a bundle that reports the total number of resources that
			// match in Bundle.total, but with no entries, and no prev/next/last links. Note
			// that the Bundle.total only include the total number of matching resources. It
			// does not count extra resources such as OperationOutcome or included resources
			// that may also be returned.

			kill bundleUrls
			Set bundleUrls("self") = tQueryURL
			Set bundle = ..CreateBundle("", "searchset", tResultSet.MatchCount, .bundleUrls, ..Schema)

			Set pResponse.Json = ..FinalizeBundle(bundle)
			set pResponse.Status = 200
			Return
		}
	} else {
		// Response from a page request to a previous query
		set tQueryURL = ..GetFullRequestURL(pRequest)
		// Throws if queryId not found
		Set tResultSet = ##class(HS.FHIRServer.Util.SearchResult).Restore(tQueryId)
		// For queryId page query:
		// - The current username must match the username on the original query.
		// - If an access token is used with the current query, it does not have to match
		//   the token on the original query. However, it does have to be valid and it
		//   does have to have authorization to see the data that the original query was
		//   intended to return.
		Set originalQueryInfo = tResultSet.GetOriginalQueryInfo()
		Set origUsername = $ListGet(originalQueryInfo, 1)
		Set origPathAndQuery = $ListGet(originalQueryInfo, 2)
		
		if (originalQueryInfo = "") || (origUsername = "") || (origPathAndQuery = "") {
			$$$ThrowFHIR($$$GeneralError, "Original query metadata could not be retreived") 
		}
		elseif (origUsername '= pRequest.Username)  {
			$$$FSLog("Username for current Search queryId page query does not match Username for original query")
			$$$ThrowFHIR($$$HttpOnlyResponse(401))
		}
		elseif (..%interactions.oauth2TokenHandler.TokenString '= "") {
			Set tempRequest = ##class(HS.FHIRServer.API.Data.Request).%New()
			Set tempRequest.RequestPath = $Piece(origPathAndQuery, "?", 1)
			Set tempRequest.QueryString = $Piece(origPathAndQuery, "?", 2, *)
			Set tempRequest.RequestMethod = pRequest.RequestMethod
			Do ..ParseRequestInputs(tempRequest)
			Do ..%interactions.oauth2TokenHandler.VerifySearchRequest(tempRequest.Type, tempRequest.Compartment, tempRequest.Id, tempRequest.Parameters, ..GetPrivFromRequest(tempRequest))
			Kill tempRequest
		}
				
		if +tPage=0 set tPage = 1
	}
	Do tResultSet.SetIteratorToPage(tPage)


	// To maximize performance this method avoids the use of HS FHIR objects.
	// Instead it uses %DynamicObject and %XML.Document when an object is
	// needed, and constructs the Bundle using streams only.

	Do ..GetPageLinks(pRequest, tResultSet.QueryId, tResultSet.TotalUndeleted, tResultSet.PageSize, tPage, tBase, .bundleUrls)
	Set bundleUrls("self") = tQueryURL
	Set bundle = ..CreateBundle("", "searchset", tResultSet.MatchCount, .bundleUrls, ..Schema)
	
	Set outcomeStatus = pRequest.Parameters.status
	if $isobject(tResultSet) && $$$ISERR(tResultSet.SearchStatus) {
		$$$FHIRAddError(outcomeStatus, tResultSet.SearchStatus)
	}
	if $$$ISERR(outcomeStatus) {
		Set outcome = ##class(HS.FHIRServer.Util.Outcome).CreateFromStatus(outcomeStatus, .httpStatus)
		do ..AddBundleEntry(bundle, "", outcome, "outcome")
	}
	
	Set checkElements = (pRequest.Parameters.GetParameterCount("_elements")>0)

	for ord=1:1:tResultSet.PageSize {
		if ' tResultSet.NextUndeleted() {
			Quit
		}
		if '$isObject(tResultSet.ResourceJson) {
			Set json = ..%interactions.Read(tResultSet.ResourceType, tResultSet.ResourceId, tResultSet.VersionId)
		} else {
			Set json = tResultSet.ResourceJson
		}
		// Derive resource type and resource id before redacting the content.
		Set tFullUrl = tBase_"/"_json.resourceType_"/"_json.id
		If (checkElements) && (tResultSet.Mode = "match") {
			Do ..ElementsStandard(.pRequest, .json)
		}
		// Apply _summary query param if present
		If tSummary'="" {
			Do ..Summary(tSummary, .json)
		}
		Set bundleEntry = ..AddBundleEntry(bundle, tFullUrl, json, tResultSet.Mode)
	}
	Set pResponse.Json = ..FinalizeBundle(bundle)
	Set pResponse.Status = 200
}

/// Get the query page size, based on the _count parameter from
/// the search request, constrained by default and maximum values.
Method GetQueryPageSize(pRequest As HS.FHIRServer.API.Data.Request) As %Integer [ Internal ]
{
	if pRequest.GetParameterValue("_summary")="count" {
		set tPageSize = 0
	} else {
		set tPageSize = pRequest.GetParameterValue("_count")
		// From http://hl7.org/fhir/STU3/search.html#count
		// if _count has the value 0, this shall be treated the same as _summary=count:
		// the server resturns a bundle that reports the total number of resources that
		// match in Bundle.total, but with no entries, and no prev/next/last links. Note
		// that the Bundle.total only include the total number of matching resources. It
		// does not count extra resources such as OperationOutcome or included resources
		// that may also be returned.
		Set tDefault = ..ConfigData.DefaultSearchPageSize
		Set tMaximum = ..ConfigData.MaxSearchPageSize
		if (tPageSize="")&&(+tDefault>0) set tPageSize = tDefault
		if (+tMaximum>0)&&(tPageSize>tMaximum) set tPageSize = tMaximum
	}
	return tPageSize
}

/// Get the links for paging to first, previous, next and last, based
/// on the total search results, page size, and current page values.
ClassMethod GetPageLinks(
	pRequest As HS.FHIRServer.API.Data.Request,
	pQueryId As %String,
	pTotal As %Integer,
	pPageSize As %Integer,
	pPage As %Integer,
	pBase As %String,
	ByRef pUrls) [ Internal ]
{
	set (tFirst, tPrev, tNext, tLast) = ""
	kill pUrls

	if pTotal>pPageSize {

		set tFirst = 1

		If (pTotal#pPageSize)=0 {
			set tLast = pTotal\pPageSize
		} else {
			set tLast = (pTotal\pPageSize)+1
		}

		// Previous should not point to the current page.
		if pPage=2 {
			set tPrev = 1
		} elseif pPage>2 {
			set tPrev = pPage-1
		}

		// Next should not point to the current page.
		if pPage=(tLast-1) {
			set tNext = tLast
		} elseif pPage<(tLast-1) {
			set tNext = pPage+1
		}

		// Include the _format parameter in the page links only if it was provided in the search URL.
		Do pRequest.Parameters.GetParameters("_format", .formatParams)
		Set tFormat = $Select(formatParams=0:"", 1:formatParams(1).value)
		kill formatParams
		
		// Also include the _include parameter (may be multiple instances)
		Do pRequest.Parameters.GetParameters("_include", .includeParams)
		set tIncludeStr = ""
		for tI=1:1:includeParams { 
			set tIncludeStr = tIncludeStr _ "_include="_includeParams(tI).value _ "&"
		}
		
		if pRequest.Interaction '= "operation" {
			set tOperation = ""
		} else {
			set tOperation = "$" _ pRequest.OperationName
			if pRequest.Type '= "" {
				Set tOperation = "/"_tOperation
			}
		}
		
		set tUrl = pBase_"/"_pRequest.Type_tOperation_"?"_$Select(tFormat'="":"_format="_tFormat_"&",1:"")_tIncludeStr_"page=<PAGE>&queryId="_pQueryId
		set pUrls("first") = $Replace(tUrl, "<PAGE>", tFirst)
		if tPrev'="" set pUrls("previous") = $Replace(tUrl, "<PAGE>", tPrev)
		if tNext'="" set pUrls("next") = $Replace(tUrl, "<PAGE>", tNext)
		set pUrls("last") = $Replace(tUrl, "<PAGE>", tLast)
	}
}

/// Perform a "new" search, as opposed to a search that uses the query cache.
Method SearchNew(pRequest As HS.FHIRServer.API.Data.Request) As HS.FHIRServer.Util.SearchResult [ Internal ]
{
	Set resourceType = pRequest.Type
	Set compartment = pRequest.Compartment
	Set compartmentId = pRequest.Id
	Set parameters = pRequest.Parameters
	Set parameters.baseURL = ..GetBaseURLs(pRequest)

	Set tResultSet = ""

	If $Get(resourceType)="" {
		$$$ThrowFHIR($$$HSFHIRErrAPIContractViolation, "Resource type not specified")
	}
	

	// Set this global to 1 to turn on logging for search. Useful for analyzing performance.
	set tLog = +$G(^HS.FHIR.Log.Search)

	set tOrderBy = ""
	
	#dim tSortKeys as HS.FHIRServer.API.Data.QueryParameters
	Do ..ValidateSortKeys(resourceType, pRequest.Parameters, .tSortKeys)
	
	// Pre-scan the parameters to verify at least one search key.
	Set tErrStatus = $$$OK
	Set preferStrict = ..IsPreferStrictHandling(pRequest)
	Set errSeverity = $Select(preferStrict="strict":"error",1:"warning")
	Set errHandling = $Select(preferStrict="strict":"",1:", ignoring")
	
	// Check the _include related parameter info, even if we are going to error
	// on unrecognized search params that we found earlier.
	Do parameters.GetParameters("_include", .params)
	do ..BuildIncludeList(.params, resourceType, .tErrStatus,.tValidIncludesArr,.pRequest,.tValidIterateArr,.tIterateConfig)

	// Check the _revinclude related parameter info, even if we are going to error
	// on unrecognized search params that we found earlier.
	Do parameters.GetParameters("_revinclude", .params)
	do ..BuildRevIncludeList(.params, resourceType, .tErrStatus,.tValidRevIncludesArr,.pRequest)
	
	//Treat malformed _include and _revincludes the same as other search
	//parameter issues and honor the Prefer handling
	$$$FHIRAddError(parameters.status, tErrStatus)
	
	// Assume that pErrors was empty before starting to validate the search
	// parameters. Therefore if there are any errors now, they are due to
	// invalid search parameters. In that case, quit now.
	if preferStrict {
		$$$ThrowOnError(parameters.status)
	}
	
	Do ..%interactions.oauth2TokenHandler.VerifySearchRequest(resourceType, compartment, compartmentId, pRequest.Parameters, ..GetPrivFromRequest(pRequest))
	
	// ---- End of Parameter Validation, Start of Query Building ----
	
	Set tResultSet = ..%interactions.Search( resourceType, compartment, compartmentId, parameters, .tSortKeys )
	
	
	// search-all (pRequest.Type=""), or search parameters _include, _revinclude or _contained,
	// could cause more than one resource type to be represented in the result set. The following loop
	// will set resourceType to empty if multiple types are included
	If (resourceType'="") && (tValidIncludesArr || tValidRevIncludesArr || tValidIterateArr || (parameters.GetAt("_contained")'="")) {
		Set resourceType = ""
	}
		
	// Now add any includes (and reverse includes) to the result set	
	Do ..%interactions.SearchIncludes(tResultSet, .tValidIncludesArr, .tValidRevIncludesArr, .tValidIterateArr, .tIterateConfig)

	// Reset to the start of the result set
	Do tResultSet.%SetIterator(0)

	// If the token handler indicates that the search results should be evaluated
	// against the current access token, evaluate each row in the result set now.
	If ..%interactions.oauth2TokenHandler.VerifySearchResults {
		While tResultSet.NextUndeleted() {
			If '$IsObject(tResultSet.ResourceJson) {
				Set resourceJson = ..%interactions.Read(tResultSet.ResourceType, tResultSet.ResourceId, tResultSet.VersionId)
			} Else {
				Set resourceJson = tResultSet.ResourceJson
			}
			// ServiceVerifyResourceContent will Throw if the check fails.
			Do ..ServiceVerifyResourceContent(resourceJson, "read", 1)
		}
		// Reset to the start of the result set
		Do tResultSet.%SetIterator(0)
	}
	
	// -------- Run the PostProcessor -----------
	Do ..%interactions.PostProcessSearch(tResultSet, resourceType)
	
	quit tResultSet
}

/// ValidateSortKeys validates the sort keys that were passed in as URL parameters, as per
/// the FHIR STU3 specification. If validation is successful, it returns information about
/// the sort keys, if any are found, in an array via the pSortKeys parameter. Otherwise a
/// failure status is returned.<br>
/// <br>
/// Input:<br>
/// <li>pResourceType : (required) FHIR resource type.
/// <li>pParameters   : (required) Request URL parameters, passed in as %Library.ArrayOfDataTypes.
/// <br><br>
/// Output:<br>
/// <li>pSortKeys     : Array of sort keys:<br>
/// - pSortKeys(n)   = True if ascending order, False if descending<br>
/// - pSortKeys(n,"SearchParam") = The nth SearchParam object to be sorted on.<br>
Method ValidateSortKeys(
	pResourceType As %String,
	pParameters As HS.FHIRServer.API.Data.QueryParameters,
	ByRef pSortKeys As %String) [ Internal ]
{
	Kill pSortKeys
	Set pSortKeys = 0
	
	If pResourceType="" {
		$$$ThrowFHIR($$$HSFHIRErrCrossResourceSort, $$$OutcomeNotSupported(400))
	}
	
	// Ensure that _sort is present no more than once in the URL
	Set tSortKeysStr = ""
	Set tKey = "_sort"
	Set tSortKeyCount = pParameters.GetParameterCount(tKey)
	if tSortKeyCount > 0 {
		if tSortKeyCount > 1 {
			$$$ThrowFHIR($$$HSFHIRErrMultipleParameters, tKey, $$$OutcomeInvalid(400))
		}
		Set tSortKeysStr = pParameters.GetParameterValue(tKey, 1, .modifier)
		if modifier '= "" {
			$$$ThrowFHIR($$$HSFHIRErrInvalidParameterModifier, modifier, tKey, $$$OutcomeInvalid(400))
		}
		
		For i = 1:1:$Length(tSortKeysStr,",") {
			Set tSortKeyStr = $Piece(tSortKeysStr,",",i)
			If tSortKeyStr'="" {
				Set isAscending = 1
				If $Extract(tSortKeyStr)="-" {
					Set isAscending = 0
					Set tSortKeyStr = $Extract(tSortKeyStr,2,*)
				}
				If $Data(tKeys(tSortKeyStr)) {
					$$$ThrowFHIR($$$HSFHIRErrDuplicateSortKey,tSortKeysStr,$$$OutcomeInvalid(400))
				}
				If tSortKeyStr="0" {
					$$$ThrowFHIR($$$HSFHIRErrDuplicateSortKey,tSortKeysStr,$$$OutcomeInvalid(400))
				}
				#dim searchParam as HS.FHIRServer.SearchParam = ..%Schema.GetSearchParam(pResourceType,tSortKeyStr)
				Set tSortKeyType = searchParam.type
				If tSortKeyType="quantity" {
					$$$ThrowFHIR($$$HSFHIRErrUnsupportedSortKey,tSortKeysStr,$$$OutcomeNotSupported(400))
				}
				Set tKeys(tSortKeyStr)=""
				If $i(tSortKeyCount) {}
				Set pSortKeys($I(pSortKeys),"SearchParam") = searchParam
				Set pSortKeys(pSortKeys) = isAscending
			} Else {
				$$$ThrowFHIR($$$HSFHIRErrInvalidSortKey,tSortKeysStr,$$$OutcomeInvalid(400))
			}
		}
	}
}

/// Validates the incoming $LIST of values provided to the _include parameter and builds
/// a $LIST of valid include requests ( <resourceType>:<searchParam>[:<targetResourceType>] )
/// Forms:
///  resourceType:* - Include resources referenced by any searchParams of resourceType reference
///  resourceType:searchParam - Include all types that the searchParam references
///  resourceType:searchParam:targetType - Include resources of targetType that the searchParam references
Method BuildIncludeList(
	ByRef includeValues,
	pResourceType As %String,
	ByRef pErrorList As %Status,
	ByRef pResArr,
	ByRef pRequest As HS.FHIRServer.API.Data.Request = {$$$NULLOREF},
	ByRef pIterArr,
	ByRef pIterConfig) [ Internal ]
{
	// If the query has an _include param or params, make sure it's valid, otherwise return an operation outcome.
	// This just validates _include, the actual processing is below.

	// Take a pass looking for '*' and expand to the set of valid search parameters
	// Build a set of values (to ensure uniqueness)
	
	kill pResArr, pIterArr, pIterConfig
	set pResArr = 0, pIterArr = 0
	set (tValidIncludes, tValidIncludesIter) = ""
	Set tTargetsArr = ""
	Merge tRemainingIncludes = includeValues
	Set tPrevCount = tRemainingIncludes
	Set tPos = ""
	
	While $G(tRemainingIncludes) {
		Set tPos = $O(tRemainingIncludes(tPos),1,includeValue)
		If (""=tPos) {
			If (tRemainingIncludes < tPrevCount) {
				Set tPrevCount = tRemainingIncludes
				Continue
			} Else {
				Quit
			}
		}
		Set tOneInclude = includeValue.value
		Set tModifier = includeValue.modifier	
		set tIncludeBaseType = $P(tOneInclude, ":", 1)
		
		// Assert that the base type of the include matches the search type.  If iterative include, then must match on of the include target types
		If (tIncludeBaseType '= pResourceType) {
			// For iterative include, just continue for now if no match - will error later if we still don't find a match after checking everything else
			If (tModifier="iterate") {
				If '$D(tTargetsArr(tIncludeBaseType)) {
					Continue
				}
			} Else {
				$$$FHIRAddError(pErrorList, $$$ERROR($$$HSFHIRErrInvalidIncludeBaseType,tOneInclude, $$$OutcomeInvalid(400)))
				If $IsObject(pRequest) {
					Do pRequest.Parameters.RemoveParameter(includeValues(tPos))
				}
				// No need to try this one again -  nothing will change
				Kill tRemainingIncludes(tPos)
				Set tRemainingIncludes = tRemainingIncludes - 1
				Continue
			}
		}
		
		// Remove from list of yet-to-be processed includes
		Kill tRemainingIncludes(tPos)
		Set tRemainingIncludes = tRemainingIncludes - 1
		
		set tIncludeParam = $P(tOneInclude, ":", 2)
		set tTargetType = $P(tOneInclude, ":", 3)
		if tIncludeParam '= "*" {
			
			set searchParam = ..%Schema.FindSearchParam(tIncludeBaseType, tIncludeParam)
			if searchParam="" {
				$$$FHIRAddError(pErrorList, $$$ERROR($$$HSFHIRErrInvalidQueryParameter, tIncludeBaseType, tIncludeParam, $$$OutcomeInvalid(400)))
				If $IsObject(pRequest) {
					Do pRequest.Parameters.RemoveParameter(includeValues(tPos))
				}
				Continue
			}
			
			// Assert that the named param is of type "reference"
			if (searchParam.type '= "reference") {
				$$$FHIRAddError(pErrorList, $$$ERROR($$$HSFHIRErrInvalidIncludeReference, tOneInclude, $$$OutcomeInvalid(400)))
				If $IsObject(pRequest) {
					Do pRequest.Parameters.RemoveParameter(includeValues(tPos))
				}
				Continue
			}
			if (tTargetType '= "") && ($ListFind(searchParam.target,tTargetType) = 0) && ($ListFind(searchParam.target, "Resource") = 0) {
				$$$FHIRAddError(pErrorList, $$$ERROR($$$HSFHIRErrInvalidReferenceTarget, tTargetType, searchParam, tIncludeBaseType, $LTS(searchParam.target),$$$OutcomeInvalid(400)))
				If $IsObject(pRequest) {
					Do pRequest.Parameters.RemoveParameter(includeValues(tPos))
				}
				Continue
			}
			If (tTargetType '= "") {
				Set tTargetsArr(tTargetType) = ""
			} Else {
				For i=1:1:$ListLength(searchParam.target) {
					Set tTargetsArr($LG(searchParam.target,i))=""
				}
			}
			if '$data(includeSet(tOneInclude)) {
				If ("iterate"=tModifier) {
					set pIterArr($i(pIterArr))=searchParam
					set pIterArr(pIterArr,"targetType")=tTargetType
					set pIterArr("types",tIncludeBaseType)=""
					
					Set searchColumn = ..%interactions.findSearchColumn(tIncludeBaseType, tIncludeParam)
					If $Data(pIterConfig(tIncludeBaseType,"cols",searchColumn.ColumnName)) {
						Set targetList = $LISTGET(pIterConfig(tIncludeBaseType,"cols",searchColumn.ColumnName),3)
						If '$ListFind(targetList, tTargetType) {
							Set $List(targetList, *+1) = tTargetType
							Set $List(pIterConfig(tIncludeBaseType,"cols",searchColumn.ColumnName),3) = targetList
						}
					}
					Else {
						Set pIterConfig(tIncludeBaseType, "select") = $G(pIterConfig(tIncludeBaseType,"select"))_$lb(searchColumn.ColumnName)
						Set pIterConfig(tIncludeBaseType,"cols",searchColumn.ColumnName) = $LB($I(colNum(tIncludeBaseType)),searchColumn.isMultiValue, $LB(tTargetType))
					}
				
					If $$$FSLogIsActive($$$FSChannelInclude) {
						set $List(tValidIncludesIter, *+1) = tOneInclude
					}
				}
				If (tIncludeBaseType = pResourceType) {
					set pResArr($i(pResArr))=searchParam
					set pResArr(pResArr,"targetType")=tTargetType
					
					If $$$FSLogIsActive($$$FSChannelInclude) {
						set $List(tValidIncludes, *+1) = tOneInclude
					}
				}
				
			}
			Set includeSet(tOneInclude) = ""
 		
		} else {

			// Expand the '*' to add all search parameters
			set searchParam = ""
			for {
				Set searchParam = ..%Schema.NextSearchParamForResourceType(tIncludeBaseType,searchParam)
				Quit:searchParam=""
				
				// Is this a reference to the search type?
				if (searchParam.type = "reference") {
					if (tTargetType="") || $ListFind(searchParam.target, tTargetType) || ($ListGet(searchParam.target, 1) = "Resource") {
						// Include this search param
						Set value = tIncludeBaseType _ ":" _ searchParam.name
						if tTargetType '= "" {
							Set value = value _ ":" _ tTargetType
							Set tTargetsArr(tTargetType)=""
						} else {
							For i=1:1:$ListLength(searchParam.target) {
								Set tTargetsArr($LG(searchParam.target,i))=""
							}
						}
						if '$data(includeSet(value)) {
							If ("iterate"=tModifier) {
								set pIterArr($i(pIterArr))=searchParam
								set pIterArr(pIterArr,"targetType")=tTargetType
								Set pIterArr("types",tIncludeBaseType)=""
								
								Set searchColumn = ..%interactions.findSearchColumn(tIncludeBaseType, searchParam.name)
								If $Data(pIterConfig(tIncludeBaseType,"cols",searchColumn.ColumnName)) {
									Set targetList = $LISTGET(pIterConfig(tIncludeBaseType,"cols",searchColumn.ColumnName),3)
									If '$ListFind(targetList, tTargetType) {
										Set $List(targetList, *+1) = tTargetType
										Set $List(pIterConfig(tIncludeBaseType,"cols",searchColumn.ColumnName),3) = targetList
									}
								}
								Else {
									Set pIterConfig(tIncludeBaseType, "select") = $G(pIterConfig(tIncludeBaseType,"select"))_$lb(searchColumn.ColumnName)
									Set pIterConfig(tIncludeBaseType,"cols",searchColumn.ColumnName) = $LB($I(colNum(tIncludeBaseType)),searchColumn.isMultiValue, $LB(tTargetType))
								}
								If $$$FSLogIsActive($$$FSChannelInclude) {
									set $List(tValidIncludesIter, *+1) = value
								}
							}
							If (tIncludeBaseType = pResourceType) {
								set pResArr($i(pResArr))=searchParam
								set pResArr(pResArr,"targetType")=tTargetType
								
								If $$$FSLogIsActive($$$FSChannelInclude) {
									set $List(tValidIncludes, *+1) = value
								}
							}
							
						}
						Set includeSet(value) = ""
					}
				}
			}
		}
	}
	
	// Now set errors for any iterative includes which has a base type that doesn't match any targets of this search
	If $G(tRemainingIncludes) {
		For {
			Set tPos = $O(tRemainingIncludes(tPos),1,includeValue)	Quit:(""=tPos)
			Set tOneInclude = includeValue.value
			$$$FHIRAddError(pErrorList, $$$ERROR($$$HSFHIRErrInvalidIncludeBaseType,tOneInclude, $$$OutcomeInvalid(400)))
			If $IsObject(pRequest) {
				Do pRequest.Parameters.RemoveParameter(includeValues(tPos))
			}
		}
	}
	$$$FSLogInclude("include: "_$LTS(tValidIncludes))
	$$$FSLogInclude("include:iterate: "_$LTS(tValidIncludesIter))
}

/// Validates the incoming $LIST of values provided to the _include parameter and builds
/// a $LIST of valid include requests ( <resourceType>:<searchParam>[:<targetResourceType>] )
/// Forms:
///  resourceType:* - Include resources of resourceType if any searchParam references the search target
///  resourceType:searchParam - Include resources of resourceType if specified searchParam references the search target
///  resourceType:searchParam:targetType - targetType must match search Resource Type if present
Method BuildRevIncludeList(
	ByRef includeValues,
	pResourceType As %String,
	ByRef pErrorList As %Status,
	ByRef pRes As %CacheString,
	ByRef pRequest As HS.FHIRServer.API.Data.Request = {$$$NULLOREF}) [ Internal ]
{
	// If the query has an _include param or params, make sure it's valid, otherwise return an operation outcome.
	// This just validates _include, the actual processing is below.
	kill pRes
	set pRes = 0
	set tValidIncludes = ""

	for tJ=1:1:includeValues {
		Set tOneInclude = includeValues(tJ).value		
		set tIncludeBaseType = $P(tOneInclude, ":", 1)
		set tIncludeParam = $P(tOneInclude, ":", 2)
		set tTargetType = $P(tOneInclude, ":", 3)
		
		if ((tTargetType '= "") && (tTargetType '= pResourceType)) {
			$$$FHIRAddError(pErrorList, $$$ERROR($$$HSFHIRErrInvalidRevIncludeTargetType,tOneInclude, $$$OutcomeInvalid(400)))
			If $IsObject(pRequest) {
				Do pRequest.Parameters.RemoveParameter(includeValues(tJ))
			}
			Continue
		}
		#dim searchParam as HS.FHIRServer.SearchParam
		if tIncludeParam = "*" {
			// First see if the search target has compartments
			// If it does, then we search the targetType for all resources in the compartment
			set searchParam = ""
			for {
				Set searchParam = ..%Schema.NextSearchParamForResourceType(tIncludeBaseType,searchParam)
				Quit:searchParam=""
				Set paramName = searchParam.code
				// Is this a reference to the search type?
				if (searchParam.type = "reference") && ($ListFind(searchParam.target, pResourceType) || ($ListGet(searchParam.target, 1) = "Resource")) {
					set pRes($i(pRes))=searchParam
					set pRes(pRes,"targetType")=tTargetType
					If $$$FSLogIsActive($$$FSChannelInclude) {
						set $List(tValidIncludes, *+1) =   tIncludeBaseType _ ":" _ paramName
					}
				}
			}
		} else {
			set searchParam = ..%Schema.FindSearchParam(tIncludeBaseType, tIncludeParam)
			if searchParam="" {
				$$$FHIRAddError(pErrorList, $$$ERROR($$$HSFHIRErrInvalidQueryParameter, tIncludeBaseType, tOneInclude, $$$OutcomeInvalid(400)))
				If $IsObject(pRequest) {
					Do pRequest.Parameters.RemoveParameter(includeValues(tJ))
				}
				Continue
			}
			// Assert that the named param is of type "reference"
			if (searchParam.type '= "reference") {
				$$$FHIRAddError(pErrorList, $$$ERROR($$$HSFHIRErrInvalidIncludeReference,tOneInclude, $$$OutcomeInvalid(400)))
				If $IsObject(pRequest) {
					Do pRequest.Parameters.RemoveParameter(includeValues(tJ))
				}
				Continue
			} elseif ( ($ListFind( searchParam.target, pResourceType) = 0) && ($ListGet(searchParam.target, 1) '= "Resource")) {
				// The reference from the desired included type can reference the search type
				$$$FHIRAddError(pErrorList, $$$ERROR($$$HSFHIRErrInvalidRevIncludeReference,tOneInclude, pResourceType, $$$OutcomeInvalid(400)))
				If $IsObject(pRequest) {
					Do pRequest.Parameters.RemoveParameter(includeValues(tJ))
				}
				Continue
			}
			// Put it in the list of valid includes if it passes validation
			set pRes($i(pRes))=searchParam
			set pRes(pRes,"targetType")=tTargetType
			If $$$FSLogIsActive($$$FSChannelInclude) {
					set $List(tValidIncludes, *+1) =  tOneInclude
			}
		}		
	}
	$$$FSLogInclude("revInclude: "_$LTS(tValidIncludes))
}

Method History(
	pRequest As HS.FHIRServer.API.Data.Request,
	pResponse As HS.FHIRServer.API.Data.Response)
{
	#; http://hl7.org/fhir/http.html#history

	set pResponse.Id = pRequest.Id

	// Assert that this interaction on this resource type is allowed as per the
	// Conformance/CapabilityStatement. While the FHIR REST API refers to the search by type
	// interaction as "history", the Conformance/CapabilityStatement resource uses value set
	// TypeRestfulInteraction http://hl7.org/fhir/ValueSet/type-restful-interaction for
	// interaction, which specifies a name of "history-instance" for this interaction.
	Do ..RequireAllowedResourceInteraction(pRequest.Type, "history", pRequest.Interaction)

	// Load any _count and _since parameter info into the tCount and tSince variables.
	// If bad values are found, ignore them and include a warning in the returned payload.
	Set tErrorStatus = $$$OK
	set tCount = ""
	set tSince = ""
	set tKey = ""

	Set tValue = pRequest.Parameters.GetOneParameterValue("_count", .pModifier)
	if tValue '= "" {
		if (tValue?1N.N)&&(tValue>0) {
			Set tCount = tValue
		} else {
			$$$FHIRAddError(tErrorStatus, $$$ERROR($$$HSFHIRErrInvalidParameterValue, "_count", tValue, $$$OutcomeIs(400, "warning", "value")))
		}
	}
	Set tValue = pRequest.Parameters.GetOneParameterValue("_since", .pModifier)
	if tValue '= "" {
		if (tValue ? 4N1"-"2N1"-"2N1"T"2N1":"2N1":"2N1(1"Z",1"-"2N1":"2N,1"+"2N1":"2N)) {
			set tSince = ##class(HS.FHIRServer.Utils).ConvertToUTC(tValue)
		} else {
			// value as passed in failed validation, so ignore it
			$$$FHIRAddError(tErrorStatus, $$$ERROR($$$HSFHIRErrInvalidParameterValue, "_since", tValue, $$$OutcomeIs(400, "warning", "value")))
		}
	}
	Set tValue = pRequest.Parameters.GetOneParameterValue("_at", .pModifier)
	if tValue '= "" {
		$$$FHIRAddError(tErrorStatus, $$$ERROR($$$HSFHIRErrUnsupportedParameter, "_at", $$$OutcomeIs(400, "warning", "value")))
	}
	
	// Strict parameter handling for History
	$$$ThrowOnError(tErrorStatus)

	// TODO: Add support for _at.
	set tAt = ""
	
	Set privNeeded = ..GetPrivFromRequest(pRequest)
	
	// If an OAuth 2.0 access token was provided with this request, verify
	// that the request info does not indicate that the interaction is not
	// allowed per the token. This will Throw if the history is not allowed.
	If pRequest.Type '= "" {
		Do ..%interactions.oauth2TokenHandler.VerifyResourceIdRequest(pRequest.Type, pRequest.Id, privNeeded)
	} Else {
		Do ..%interactions.oauth2TokenHandler.VerifySystemLevelRequest()
	}

	#dim tHistoryResultSet As HS.FHIRServer.Util.SearchResult
	set tHistoryResultSet = ..%interactions.History( pRequest.Type, pRequest.Id, tSince, tAt)
	
	kill bundleUrls
	Set bundleUrls("self") = ..GetFullRequestURL( pRequest )

	Set bundle = ..CreateBundle("", "history", tHistoryResultSet.%ROWCOUNT, .bundleUrls, ..Schema)

	if tCount="" set tCount = tHistoryResultSet.%ROWCOUNT
	
	while tHistoryResultSet.NextUndeleted() {
		Set bundleEntry = ..AddBundleEntry(bundle)
		Set tVerb = tHistoryResultSet.Verb
		if tVerb '= "DELETE" {
			Set bundleEntry.resource = ..%interactions.Read(tHistoryResultSet.ResourceType, tHistoryResultSet.ResourceId, tHistoryResultSet.VersionId)
		}
		Set bundleEntry.request = $$$NewJSONObject
		Set bundleEntry.request.method = tVerb
		Set bundleEntry.request.url = pRequest.Type_$S(tVerb'="POST":"/"_pRequest.Id, 1:"")
		Set resourceMeta = ..%interactions.FindResourceMeta(tHistoryResultSet.ResourceType, tHistoryResultSet.ResourceId, tHistoryResultSet.VersionId)
		If (resourceMeta '= "") && ($ListValid(resourceMeta)) {
			Set lastModified = $ListGet(resourceMeta, 5)
			If lastModified '= "" {
				Set bundleEntry.response = {"lastModified": (lastModified)}
			}
		}
	}
	set pResponse.Json = ..FinalizeBundle(bundle)
	
	// If an OAuth 2.0 access token was provided with this request, verify
	// that the contents of the retrieved resource Bundle satisfies the scope(s)
	// and context of the token. This will Throw if the history is not allowed.
	Do ..%interactions.oauth2TokenHandler.VerifyHistoryInstanceResponse(pRequest.Type, bundle, privNeeded)
	
	set pResponse.Status = 200
}

Method Operation(
	pRequest As HS.FHIRServer.API.Data.Request,
	pResponse As HS.FHIRServer.API.Data.Response)
{
	Do ..interactions.Operation($this, pRequest, pResponse)
}

/// RequireAllowedResourceInteraction validates that the specified interaction is permitted by the Conformance/CapabilityStatement
/// server definition.<br>From FHIR Spec:  
/// In general, if an instance fails the constraints documented in the CapabilityStatement then the response should be a 400
/// <br>
/// Input:<br>
/// <li>pInteraction         : (required) FHIR RESTful interaction.
/// <li>pInteraction2         : (required) A more specific interaction (e.g. history, history-instance).
/// Return: void, but throws if interaction is not allowed
Method RequireAllowedResourceInteraction(
	pResourceType As %String,
	pInteraction As %String,
	pInteractionLevel2 As %String = "")
{
	set entry = ""
	Set interactionLevel2 = $select(pInteractionLevel2="": pInteraction, 1: pInteractionLevel2)
	Set rsrcMeta = ..RestResourceMap.%Get(pResourceType)
	if rsrcMeta '= "" {
		Set entry = ..findItemByProperty( rsrcMeta.interaction, "code", pInteraction )
		if (entry = "") && (interactionLevel2 '= pInteraction) {
			Set entry = ..findItemByProperty( rsrcMeta.interaction, "code", pInteractionLevel2 )
		}
	}
	If entry="" {
		if (interactionLevel2 = pInteraction) {
			$$$ThrowFHIR($$$HSFHIRErrInteractionNotSupported, pResourceType, pInteraction, $$$OutcomeNotSupported(400))
		}
		$$$ThrowFHIR($$$HSFHIRErrInteractionsNotSupported, pResourceType, pInteraction, interactionLevel2, $$$OutcomeNotSupported(400))
	}
}

/// RequireAllowedSystemInteraction validates that the specified interaction is permitted by the Conformance/CapabilityStatement
/// server definition.<br>From FHIR Spec:  
/// In general, if an instance fails the constraints documented in the CapabilityStatement then the response should be a 400<br>
/// <br>
/// Input:<br>
/// <li>pInteraction         : (required) FHIR RESTful interaction.
/// Return: void, but throws if interaction is not allowed
Method RequireAllowedSystemInteraction(pInteraction As %String) As %Boolean
{
	Set entry = ..findItemByProperty( ..RestServerMeta.interaction, "code", pInteraction )
	if (entry = "") {
		$$$ThrowFHIR($$$HSFHIRErrSystemInteractionNotSupported, pInteraction, $$$OutcomeNotSupported(400))
	}
}

ClassMethod GetPreferHeader(
	pRequest As HS.FHIRServer.API.Data.Request,
	pPreferenceType As %String) As %String
{
	Set tHeader = pRequest.Prefer
	Set tPreference = ""
	For i = 1:1:$Length(tHeader,";") {
		If $Piece($Piece(tHeader,";",i),"=",1)=pPreferenceType {
			Set tPreference = $Piece($Piece(tHeader,";",i),"=",2)
			$$$FSLog("Preference: "_tPreference)
			Quit
		}
	}
	Return tPreference
}

Method IsPreferStrictHandling(pRequest As HS.FHIRServer.API.Data.Request) As %Boolean
{
	// If Prefer:handling=strict, then it means that the request has asked
	// the server to consider unrecognized and/or unsupported search parameters
	// to be an error, rather than just being a condition to be ignored with a
	// warning.
	Set tPreferHandling = ..GetPreferHeader(pRequest, "handling")
	if tPreferHandling = "" {
		Set tPreferHandling = $Select(..%ConfigData.DefaultPreferHandling="":"lenient", 1:..%ConfigData.DefaultPreferHandling)
	}
	return (tPreferHandling = "strict")
}

ClassMethod GetFullRequestURL(pRequest As HS.FHIRServer.API.Data.Request)
{
	// When we build the full URL, we do not echo bad search parameters (they are still
	// available in pRequest.QueryString if needed)
	Set url = ..GetRequestURLNoQuery(pRequest)
	Set queryString = pRequest.Parameters.AsString()
	if queryString '= "" {
		set url = url _ "?" _ queryString	
	}
	Return url
}

ClassMethod GetRequestURLNoQuery(pRequest As HS.FHIRServer.API.Data.Request)
{
	Quit pRequest.BaseURL_$Select($Extract(pRequest.BaseURL,*)="/":"",1:"/")_pRequest.RequestPath
}

/// API
/// GetResourceCapabilityItem examines the specified Conformance/CapabilityStatement for the
/// the specified resource type and returns the value for the specified "capability item".<br>
/// <br>
/// Input:<br>
/// <li>pResourceType        : (required) FHIR resource type.
/// <li>pCapabilityItem      : (required) Resource type capability item (examples: "conditionalCreate", "readHistory").
/// <li>pDefault             : (required) Value to return if the specification is not present
Method IsCapabilitySupported(
	pResourceType As %String,
	pCapabilityItem As %String,
	pDefault As %Boolean) As %Boolean
{
	Set result = pDefault
	Set rsrcMeta = ..RestResourceMap.%Get(pResourceType)
	if rsrcMeta'="" {
		Set value = rsrcMeta.%Get(pCapabilityItem)
		if value '= "" {
			Set result = value
		}
	}
	Quit result
}

Method GetCapabilityStatus(
	pResourceType As %String,
	pCapabilityItem As %String) As %String
{
	Set result = ""
	Set rsrcMeta = ..RestResourceMap.%Get(pResourceType)
	if rsrcMeta'="" {
		Set result = rsrcMeta.%Get(pCapabilityItem)
	}
	Quit result
}

// Find the first object in an array that has a specific property value

ClassMethod findItemByProperty(
	array As %DynamicArray,
	propName As %String,
	propValue)
{
	Set iter = array.%GetIterator()
	while iter.%GetNext(.key , .value ) {
		if value.%Get(propName) = propValue {
			Return value
		}
	}
	Quit ""
}

/// Checks if the specified resource is a member of the Patient compartment.  If so, then it
/// inspects the enumerated reference properties to see if there is a reference to the specified
/// Patient resource id.
/// TODO:  This does (may) not handle compound property names properly...
///        it seems they indicate that the first property is an array of objects that have a "reference" property of
///        type reference.  So its like "AuditEvent.entity[n].reference.reference" but indicated by "entity.patient"
/// 
Method IsResourceForPatient(
	pResourceObj As %DynamicObject,
	pPatientResourceId As %String) As %Boolean [ Internal ]
{
	// Get the list of compartments that this resource is a part of
	Set compartmentList = ..Schema.BuildCompartmentList(pResourceObj)
	// return whether it includes a compartment for the specified Patient
	return $ListFind(compartmentList, "Patient/" _ pPatientResourceId)
}

ClassMethod RequireValidId(pId) As %String
{
	If ((pId '= "") && ($Length(pId)>64) || ($Translate(pId,"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-.")'=""))
	{
		$$$ThrowFHIR($$$HSFHIRErrInvalidId, pId, $$$OutcomeInvalid(400))
	}
	return pId
}

Method RequirePayload(pRequest As HS.FHIRServer.API.Data.Request) As %DynamicObject
{
	Set payload = pRequest.Json
	if payload = "" {
		$$$ThrowFHIR($$$HSFHIRErrPayloadMissing, pRequest.Interaction,$$$OutcomeIs(400, "invalid", "missing payload"))
	}
	Return payload
}

ClassMethod ETagValue(pVersionId As %String) As %String [ CodeMode = expression ]
{
"W/"""_pVersionId_""""
}

ClassMethod GetPrivFromRequest(pRequest As HS.FHIRServer.API.Data.Request) As %String [ CodeMode = expression ]
{
$Case(pRequest.AdditionalInfo.GetAt("USER:PrivilegeNeeded"), "r":"read", "w":"write", "*":"*", :pRequest.AdditionalInfo.GetAt("USER:PrivilegeNeeded"))
}

/// Return a list of BaseURLs to use in relation to reference-type search parameters.
/// This method ensures that the host name(s) that are in the returned BaseURLs are
/// converted to lowercase, as part of case-insensitizing host name for the purposes
/// of searching by references.
Method GetBaseURLs(pRequest As HS.FHIRServer.API.Data.Request) As %List
{
	#dim base As %List = ""
	#define makeURL(%hostname) $Piece(reqBaseURL,"/",1)_"//"_%hostname_":"_$Piece(reqBaseURL,":",*)
	#define addURL(%url) If '$ListFind(base, %url) Set $List(base, *+1) = %url
	For reqBaseURL = pRequest.BaseURL, pRequest.LocalBaseURL {
		Set fullHostName = $ZConvert($Piece($Piece(reqBaseURL, "/", 3), ":", 1), "L")
		If ##class(%SYSTEM.INetInfo).AddrType(fullHostName) = 1 {
			// fullHostName is an IP address. Try to find a host name for the
			// IP address. If one is found, then a BaseURL for it will be
			// added to the returned BaseURLs list.
			Set hostName = fullHostName
			Set hostFromAddr = $ZConvert(##class(%SYSTEM.INetInfo).AddrToHostName(##class(%SYSTEM.INetInfo).TextAddrToBinary(fullHostName)), "L")
			If hostFromAddr = "" {
				Set currentAddr = ##class(%SYSTEM.INetInfo).HostNameToAddr(##class(%SYSTEM.INetInfo).LocalHostName())
				If currentAddr = fullHostName {
					Set hostFromAddr = $ZConvert(##class(%SYSTEM.INetInfo).LocalHostName(), "L")
				}
			}
		} Else {
			// Else assume AddrType is 0 (a host name).
			Set hostFromAddr = ""
			If ($Piece(fullHostName, ".", 1) '= "www") && ($Piece(fullHostName, ".", *) '= "local") {
				Set hostName = $Piece(fullHostName, ".", 1)
			} Else {
				Set hostName = fullHostName
			}
		}
		
		Set server = $ZConvert($ZU(54,13,hostName), "L")
		Set qualifiedName = $Piece(server,",",*)
		If ""'=qualifiedName {
			Set qualifiedURL = $$$makeURL(qualifiedName)
			$$$addURL(qualifiedURL)
			Set hostURL = $$$makeURL(hostName)
			$$$addURL(hostURL)
		} Else {
			Set origBaseURL = $$$makeURL(fullHostName)
			$$$addURL(origBaseURL)
		}
		
		If hostFromAddr '="" {
			Set hostFromAddrURL = $$$makeURL(hostFromAddr)
			$$$addURL(hostFromAddrURL)
		}
		// Don't repeat loop if the LocalBaseURL is the same as the BaseURL
		If (pRequest.BaseURL = pRequest.LocalBaseURL) {
			Quit
		}
	}	
	Quit base
}

Method Summary(
	pSummary As %String,
	ByRef pResource As %DynamicObject)
{
	If pSummary = "text" {
		Do ..SummaryText(pResource)
	}
	ElseIf pSummary = "data" {
		Do ..SummaryData(pResource)
	}
}

/// Apply the _summary=text filter to a resource
/// Return only the "text" element, the 'id' element, the 'meta' element, and only top-level mandatory elements
Method SummaryText(ByRef pResource As %DynamicObject)
{
	Set topLevelArray = ""
	Set topLevelArray("resourceType") = 1
	Set topLevelArray("id") = 1
	Set topLevelArray("text") = 1
	Set topLevelArray("meta") = 1
	Set tPropName = ""
	For {
		Set tPropName = $$$NextRequiredProperty(..Schema, pResource.resourceType, tPropName)
		Quit:tPropName=""
		Set topLevelArray(tPropName) = 1
	}

	Set resouceIter = pResource.%GetIterator()
	For {
		Try {
			Set iteratorBool = resouceIter.%GetNext(.prop, .val)			
		} Catch getNextEx {
			If getNextEx.Name = "<MAXSTRING>" {
				Set iteratorBool = resouceIter.%GetNext(.prop, .val, "stream")
			} Else {
				Throw getNextEx
			}
		}
		Quit:'iteratorBool
		Kill val
		If '$G(topLevelArray(prop),0) {
			Do pResource.%Remove(prop)
		}
	}

	// Servers SHOULD mark the resources with the tag SUBSETTED to ensure that the incomplete resource is not accidentally used to overwrite a complete resource.
	Do ##class(HS.FHIRServer.Utils).Subsetted(pResource,"_summary=text search parameter")
}

/// Apply the _summary=data filter to a resource - Remove the text element
Method SummaryData(ByRef pResource As %DynamicObject) As %DynamicObject
{
	If pResource.text'="" {
		Do pResource.%Remove("text")
		Do ##class(HS.FHIRServer.Utils).Subsetted(pResource,"_summary=data search parameter")
	}
}

}
