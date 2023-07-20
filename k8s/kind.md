# install kind

brew install kind

# create cluster

sh k8s/kind-registry-startup.sh

# apply pv-pvc

kubectl apply -f k8s/config/pv-pvc.yaml

# install iris-operator
## tag operator image

docker tag intersystems/iris-operator-amd:3.5.48.100 k3d-registry.localhost:5000/intersystems/iris-operator-amd:3.5.48.100

## push operator image

docker push k3d-registry.localhost:5000/intersystems/iris-operator-amd:3.5.48.100

## install it

helm install intersystems k8s/iris_operator_amd-3.5.48.100/chart/iris-operator

# create certificate

openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout tls.key -out tls.crt -subj "/CN=*.localhost"

# add certificate to kubernetes

kubectl create secret tls tls-secret --key k8s/tls/tls.key --cert k8s/tls/tls.crt

# create configmap

kubectl create cm iriscluster-config --from-file common.cpf --from-file CSP-merge.ini

# create secret

kubectl create secret generic iriscluster-secret --from-file misc/auth/secret.json

# deploy iris-oauth-fhir

kubectl apply -f k8s/config/iris-web-merge.yaml

## test

kubectl create deployment iko --image=k3d-registry.localhost:5000/intersystems/iris-operator-amd:3.5.48.100