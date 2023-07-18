import os

# setup the environment
os.environ['IRISNAMESPACE'] = '%SYS'

import iris
import json


def setup_oauth(filename):
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

if __name__ == '__main__':
    # command line argument is the secret.json file
    import sys
    setup_oauth(sys.argv[1])