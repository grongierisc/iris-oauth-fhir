# iris-oauth-fhir

![img](https://i0.wp.com/sunfox.org/blog/wp-content/uploads/2007/05/openid2.png)
![fhir](https://v2k8e7u2.rocketcdn.me/wp-content/uploads/2022/11/HL7-FHIR-LOGO.png.webp)

This is a sample application that demonstrates how to use the [InterSystems IRIS for Health FHIR Repository](https://docs.intersystems.com/irisforhealthlatest/csp/docbook/DocBook.UI.Page.cls?KEY=HXFHIR) to build a FHIR Repository with OAuth2 authorization, the FHIR endpoint will be the resource server and Google OpenId will be the authorization server.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/)
- [Git](https://git-scm.com/downloads)
- [Google Cloud Platform](https://cloud.google.com/) account

## Installation

### Setup Google Cloud Platform

This part is inspired by the article [Adding Google Social Login into InterSystems Management Portal](https://community.intersystems.com/post/adding-google-social-login-intersystems-management-portal) from yurimarx Marx in the InterSystems Community.

1. Create a new project in Google Cloud Platform

2. On the header click Select a project:

![img](https://lh3.googleusercontent.com/UrO8wXdSnglV61L3-_pJZqoeU1-u8xkquMNhekzqt4Bq3Sv29UbpK8bAzqzZAZf_HYdcl424o4cBddKh4fNUNORSS7yHx7nV4jGXEH2p_eSCj9NSZaMliQS1ZoygU5Bms6rVYvICm7Ky1S7TNJLJWbM)

3. Click the button NEW PROJECT:

![img](https://lh6.googleusercontent.com/trWV5eyJkDg52kA6ec-WA-3JsTwuCWkPd-mOe8DrPozmjzYLTOdJrhfGb5FiEEsT4kjL_qqgUic6fI6lbCJ6ZCxqx4VNQdO7-WuXf7Sp0H5Em0WuwuI2U7BvsSbq8z1FBsm4hIE7NZHvLekYfZWszfE)

4. Create a sample project for this article called InterSystemsIRIS and click the button CREATE:

![img](https://lh6.googleusercontent.com/p2j6ctk7dGvK6KM_PeGjo7Ig8n2AT0RpVP9hV3vFuM8HB1XTnSgLY_-EGB5AzjN2KSCrkCdO3Z9wNl6qhFl0aWybHpIhiX6yFtZeRVQ5uifVPityCCwcg1sP2G1xgbf7ZxcqyKR_2Zu7FlLAWcg5XPc)

5. Go to the Header again and select the created project InterSystemsIRIS hyperlink in the table:

![img](https://lh6.googleusercontent.com/9vRNOYAhs6ghJhc248aq4CBo-mEHy92vhIYPW0V0Ng8yht3GQbJuxAT70HbdxaTJVMRtQk2KaYpaCoB5VoFzu2sys-TkhNt8P9veKIpCXsEb5u0mYjx2zDmZbOXF_fKdGMzypbfUMyqtm10dbb5g-s4)

6. Now the selected project is the working one:

![img](https://lh3.googleusercontent.com/aNzHOr_rGtDRCkRbdQHg6Vnt6kUijcdx9aQxEHWu0ff9EH_9YqsU8cvOiawMeh9yfYZfoPz8yHtoSit1CsjBRcWsWq8xpTu84_JAA0yh2RK5e-kM4F7zII-9BltYwnuTPTWlPv2BMukq_CO17_87ARE)

7. In the header look for credentials on the Search field and choose API credentials (third option for this image):

![img](https://lh4.googleusercontent.com/wDLcX0moxPmJYXFht9tMewJRmFEVG4samIq1S9TPjV__M7hd4u-sXsHk_q5d4B5WqzLuDZ7bQCx4EubpAMv2_NvyqmIl9JEL649o79GH0_2Gy5fL8jcnAMtthWsQ_dOTYq_Ffz7CSBY-LDHmhHswxZo)

8. On the top of the screen, click the + CREATE CREDENTIALS button and select OAuth 2.0 Client ID option:

![img](https://lh4.googleusercontent.com/EGyMynKhvAPKuVejvBJ59U5Ih01Lpnqw_Po5Ga5nK43oquMkD_NZYocK27MjLG-zNro-T6Z5uG-2Isl00wXG8dpgpEBlCca0ZlzUGXsoCAARNqcBTS4NJEBX2AGGJIP8L3N1t0m-rZpSqOea7YTfJFE)

9. Now click CONFIGURE CONSENT SCREEN:

![img](https://lh5.googleusercontent.com/PbHDj07YURT57XmS-NH85npSoT69eYXWPPoC3V5B6DsCLVQV4c_vC4o3ZxKLwdoYqO0SgEUCpsYPEMVEiIcm_y4ifJMLEWuvGN9yylHSsFWl-SCC5BfMZSsnsM5XxrsL5r5APtAOxRZmObo6IXnFxL0)

10. Choose External (any person who has Gmail is able to use it) and click the CREATE button:

![img](https://lh3.googleusercontent.com/btgNo7Y7j8ox3tjcy__5tLKTI48vbDtn_CKhCJ6MEUC4kgdFgBE6GOF58_3U0zm02ealZkgUbsaXwmGXE87deSIrh-9WaOMgBCBcssOqCYE0KC4pse3XQRJbCPeM9mNwLNDvJBshQhYqveAtM6bFe-8)

11. In Edit app registration, complete the field values as follow:
App Information (use your email for user support email):

![img](https://github.com/grongierisc/iris-oauth-fhir/blob/main/misc/img/Edit_app_registration.jpg?raw=true)


1.  For Authorized domains, it is not necessary to set anything because this sample will use localhost. Set the developer contact information with your email and click the SAVE AND CONTINUE button:

![img](https://github.com/grongierisc/iris-oauth-fhir/blob/main/misc/img/Edit_app_registration_2.jpg?raw=true)


12. Click ADD OR REMOVE SCOPES and select the following scopes, scroll the dialog, and click the UPDATE button:

![img](https://github.com/grongierisc/iris-oauth-fhir/blob/main/misc/img/Scope_openid.jpg?raw=true)

13. Include your email into the Test users list (using the +ADD USERS button) and click the SAVE AND CONTINUE button:

![img](https://github.com/grongierisc/iris-oauth-fhir/blob/main/misc/img/Test_user.jpg?raw=true)

15. The wizard shows you the Summary of the filled fields. Scroll the screen and click the BACK TO DASHBOARD button.
16. Now, it is time to configure the credentials for this new project. Select the option Credentials:

![img](https://lh6.googleusercontent.com/gjqSKoWv0ePY6A7gJ_EExof00ja99-n3MlOhB9EC1eS9gtTII1Xbn8HjF4uDtXUYKkvJzhaEQfSrFIUTBWFV_b0aXVsdXG4aK_YVeh2ddfxlghmBwgQljZO7YkDM8i3kCK05cvN4YvD-fPNxr3v9nDQ)

17. Click the + CREATE CREDENTIALS button and select OAuth client ID option:

![img](https://lh5.googleusercontent.com/_WLvGyzjqr6CV5TSsOFyhVO1c8xHnda-qwZ2T3HA2X-t6s9lU9jlspsuarpEc6wSAD6frTjR8BhkCvnJ0dnIPBAuoOyw7qQnTCTYZgsQBdQYgXcXWCHoz07ayHeqVdNrSwuh_Oreh406u8i6HhallsA)

18. Select Web application option and complete the field values as follow:

![img](https://github.com/grongierisc/iris-oauth-fhir/blob/main/misc/img/Create_OpenId.jpg?raw=true)

We will be using postman for the demo, but if you want to use the sample application, you will need to add the following redirect URIs, same goes for the JavaScript origins.

19. Click the CREATE button and copy the Client ID and Client Secret values:

![img](https://github.com/grongierisc/iris-oauth-fhir/blob/main/misc/img/Secrets.jpg?raw=true)

You are done with the Google Cloud Platform configuration.

### Setup the sample application

1. Clone this repository:

```bash
git clone https://github.com/grongierisc/iris-oauth-fhir
```

2. Build the docker image:

```bash
docker-compose build
```

3. Set Client Id an Client Secret from the last part of (Setup Google Cloud Platform) in a new file called `secret.json` in `misc/auth` folder, you can use the `secret.json.template` as a template.

```json
{
    "web": {
        "client_id": "xxxx",
        "project_id": "intersystems-iris-fhir",
        "auth_uri": "https://accounts.google.com/o/oauth2/auth",
        "token_uri": "https://oauth2.googleapis.com/token",
        "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v3/certs",
        "client_secret": "xxxx"
    },
    "other" : {
        "issuer" : "accounts.google.com"
    }
}
```

⚠️ Warning : `auth_provider_x509_cert_url` by default is `https://www.googleapis.com/oauth2/v1/certs` but it is deprecated, you need to use `https://www.googleapis.com/oauth2/v3/certs` instead.

4. Run the docker image:

```bash
docker-compose up -d
```

### Test it with Postman

The endpoint is `httsp://localhost:4443/fhir/r4/`.

0. Configure Postman to use the self-signed certificate, see [Postman documentation](https://learning.postman.com/docs/sending-requests/certificates/).

1. Create a new request in Postman and go to the Authorization tab. Select OAuth 2.0 as the type :

![img](https://github.com/grongierisc/iris-oauth-fhir/blob/main/misc/img/Postman_Auth.jpg?raw=true)

2. On the Configure New Token dialog, set the following values:

The access url token is : `https://accounts.google.com/o/oauth2/token`
Scopes is : `openid`
Client Id and Client Secret are the one you got from the Google Cloud Platform.

![img](https://github.com/grongierisc/iris-oauth-fhir/blob/main/misc/img/Postman_Config.jpg?raw=true)

3. Click the Request Token button and you will be redirected to the Google login page:

![img](https://github.com/grongierisc/iris-oauth-fhir/blob/main/misc/img/Postman_Get_Token1.jpg?raw=true)
![img](https://github.com/grongierisc/iris-oauth-fhir/blob/main/misc/img/Postman_Get_Token2.jpg?raw=true)

4. Make use of the token to get the patient list:

![img](https://github.com/grongierisc/iris-oauth-fhir/blob/main/misc/img/Postman_Use_Token.jpg?raw=true)

5. Select in Token type, ID Token and click the Use Token button:

![img](https://github.com/grongierisc/iris-oauth-fhir/blob/main/misc/img/Postman_Token_Id.jpg?raw=true)

6. You will get the patient list:

![img](https://github.com/grongierisc/iris-oauth-fhir/blob/main/misc/img/Postman_Success.jpg?raw=true)

What journey, hope you enjoyed it.

More to come, stay tuned. We will be dealing with kubernetes and the FHIR repository in the next part.
