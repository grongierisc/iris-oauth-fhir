import time
import os
import json

import iris

from FhirInteraction import OAuthInteraction, Interaction

from google.oauth2 import id_token
from google.auth.transport import requests

import requests as rq

# The following is an example of a custom OAuthInteraction class that
class CustomOAuthInteraction(OAuthInteraction):
    
    client_id = None
    last_time_verified = None
    time_interval = 5

    def clear_instance(self):
        self.token_string = None
        self.oauth_client = None
        self.base_url = None
        self.username = None
        self.token_obj = None
        self.scopes = None
        self.verify_search_results = None

    def set_instance(self, token:str,oauth_client:str,base_url:str,username:str):

        self.clear_instance()

        if not token or not oauth_client:
            # the token or oauth client is not set, skip the verification
            return

        global_time = iris.gref('^FHIR.OAuth2.Time')
        if global_time[token[0:50]]:
            self.last_time_verified = global_time[token[0:50]]

        if self.last_time_verified and (time.time() - float(self.last_time_verified)) < self.time_interval:
            # the token was verified less than 5 seconds ago, skip the verification
            return

        self.token_string = token
        self.oauth_client = oauth_client
        self.base_url = base_url
        self.username = username

        # try to set the client id
        try:
            # first get the var env GOOGLE_CLIENT_ID is not set then None
            self.client_id = os.environ.get('GOOGLE_CLIENT_ID')
            # if not set, then by the secret.json file
            if not self.client_id:
                with open(os.environ.get('ISC_OAUTH_SECRET_PATH'),encoding='utf-8') as f:
                    data = json.load(f)
                    self.client_id = data['web']['client_id']
        except FileNotFoundError:
            pass

        try:
            self.verify_token(token)
        except Exception as e:
            self.clear_instance()
            raise e
        # token is valid, set the last time verified to now
        global_time[token[0:50]]=str(time.time())

    def verify_token(self,token:str):
        # check if the token is an access token or an id token
        if token.startswith('ya29.'):
            self.verify_access_token(token)
        else:
            self.verify_id_token(token)

    def verify_access_token(self,token:str):
        # verify the access token is valid
        # get with a timeout of 5 seconds
        response = rq.get(f"https://www.googleapis.com/oauth2/v3/tokeninfo?access_token={token}",timeout=5)
        try:
            response.raise_for_status()
        except rq.exceptions.HTTPError as e:
            # the token is not valid
            raise e

    def verify_id_token(self,token:str):
        # Verify the token and get the user info
        idinfo = id_token.verify_oauth2_token(token, requests.Request(), self.client_id)
        if idinfo['iss'] not in ['accounts.google.com', 'https://accounts.google.com']:
            raise ValueError('Wrong issuer.')

    def get_introspection(self)->dict:
        return {}
    
    def get_user_info(self,basic_auth_username:str,basic_auth_roles:str)->dict:
        return {"Username":basic_auth_username,"Roles":basic_auth_roles}
    
    def verify_resource_id_request(self,resource_type:str,resource_id:str,required_privilege:str):
        pass

    def verify_resource_content(self,resource_dict:dict,required_privilege:str,allow_shared_resource:bool):
        pass

    def verify_history_instance_response(self,resource_type:str,resource_dict:dict,required_privilege:str):
        pass

    def verify_delete_request(self,resource_type:str,resource_id:str,required_privilege:str):
        pass

    def verify_search_request(self,
                              resource_type:str,
                              compartment_resource_type:str,
                              compartment_resource_id:str,
                              parameters:'iris.HS.FHIRServer.API.Data.QueryParameters',
                              required_privilege:str):
            pass
    
    def verify_system_level_request(self):
        pass

class CustomInteraction(Interaction):

    def on_after_request(self, fhir_service, fhir_request, fhir_response, body):
        
        #extract the token from the header
        header = "HEADER:X-Goog-Authenticated-User-Id"

        # Upper case the header name
        header = header.upper()

        # replace - with _
        header = header.replace("-","_")

        header_value = fhir_request.AdditionalInfo.GetAt(header)

        if fhir_request.AdditionalInfo.GetAt(header) == "" :
            header_value = "None"

        # Get the resource verb
        verbe = fhir_request.RequestMethod

        #Get the URL
        #Extract the URL from the request
        url = "/" + fhir_request.RequestPath

        if fhir_request.QueryString != "" :
            url = url + "?" + fhir_request.QueryString

        #Get protocol
        protocol = "HTTP/1.1"

        #Response code
        response_code = fhir_response.Status

        #Get the IP address
        ip = fhir_request.AdditionalInfo.GetAt("ClientAddr")
            
        #Create log entry
        #Format ClientAddr "GET /fhir/r4/Patient?Name=toto HTTP/1.1" 200 token
        line = f'{ip} "{verbe} {url} {protocol}" {response_code} {header_value}'
        iris.cls('%SYS.System').WriteToConsoleLog(line,0,0,"FHIR.Server")

