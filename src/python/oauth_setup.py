import os
import sys

import json

def setup_oauth(filename):

    os.environ['IRISNAMESPACE'] = '%SYS'
    import iris

    # read the secret.json file
    with open(filename) as f:
        secret = json.load(f)

    if not iris.cls("Security.SSLConfigs")._ExistsId("ssl oauth"):
        # setup the ssl config
        ssl = iris.cls("Security.SSLConfigs")._New()
        ssl.Name = "ssl oauth"
        ssl._Save()

    # setup the oauth2 server definition

    oauth2_server = iris.cls("OAuth2.ServerDefinition").OpenByIssuer(secret["other"]["issuer"])
    if oauth2_server == "":
        oauth2_server = iris.cls("OAuth2.ServerDefinition")._New()
    oauth2_server.IssuerEndpoint = secret["other"]["issuer"]
    oauth2_server.SSLConfiguration = "ssl oauth"
    oauth2_server.Metadata.authorization_endpoint= secret["web"]["auth_uri"]
    oauth2_server.Metadata.token_endpoint= secret["web"]["token_uri"]
    oauth2_server.Metadata.jwks_uri= secret["web"]["auth_provider_x509_cert_url"]
    oauth2_server._Save()

    # setup the client based on the server definition
    client = iris.cls('OAuth2.Client')._New()
    client.ApplicationName = "FHIR Oauth"
    client.ServerDefinition = oauth2_server
    client.Enabled = 1
    client.SSLConfiguration = "ssl oauth"
    client.ClientType = "resource"
    client.ClientSecret = secret["web"]["client_secret"]
    client.ClientId = secret["web"]["client_id"]
    client._Save()

    # swith namespace to the FHIRSERVER namespace
    iris.system.Process.SetNamespace("FHIRSERVER")

    # set the oauth2 client name
    config = iris.cls('HS.Util.RESTCSPConfig')._OpenId(1)
    config.OAuthClientName = "FHIR Oauth"
    config._Save()

    # Remove the unauthenticated access
    strategy = iris.cls('HS.FHIRServer.API.InteractionsStrategy').GetStrategyForEndpoint('/fhir/r4')
    config = strategy.GetServiceConfigData()
    config.DebugMode = 0
    strategy.SaveServiceConfigData(config)

def setup_unauthenticated():
    
    import iris

    app_key = '/fhir/r4'
    # get config
    config = iris.cls('HS.Util.RESTCSPConfig')._OpenId(1)
    # remove the oauth client name
    config.OAuthClientName = ''
    # save the config
    config._Save()

    #set unauthorized access
    strategy = iris.cls('HS.FHIRServer.API.InteractionsStrategy').GetStrategyForEndpoint(app_key)
    config = strategy.GetServiceConfigData()
    # set the debug mode to 4 = unauthenticated
    config.DebugMode = 4
    config.MaxSearchResults = 100000
    strategy.SaveServiceConfigData(config)


if __name__ == '__main__':
    # command line argument is the secret.json file
    # check if one argument is passed and it is a file
    if len(sys.argv) != 2 or not os.path.isfile(sys.argv[1]):
        print("Setup server in unauthenticated mode")
        setup_unauthenticated()
        print("The server is setup in unauthenticated mode")
    else:
        print("Setting up the oauth2 server")
        setup_oauth(sys.argv[1])
        print("The oauth2 server is setup")
