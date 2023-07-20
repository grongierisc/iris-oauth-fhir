# Download k3d

curl -s https://raw.githubusercontent.com/rancher/k3d/main/install.sh | bash

# create a registry

k3d registry create registry.localhost --port 5000

# add registry to hosts
## mac

sudo nano /etc/hosts

# Start the culster

k3d cluster create demo --servers 1 --agents 2 --volume $HOME/git/iris-oauth-fhir/k8s/data:/var/lib/rancher/k3s/storage@all --registry-use k3d-registry.localhost:5000 -p "8081:80@loadbalancer" -p "4443:443@loadbalancer" --api-port 6550

# tag operator image

docker tag intersystems/iris-operator-amd:3.5.48.100 k3d-registry.localhost:5000/intersystems/iris-operator-amd:3.5.48.100

# push operator image

docker push k3d-registry.localhost:5000/intersystems/iris-operator-amd:3.5.48.100

# install helm

curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

# install iris-operator

## install it

helm install intersystems k8s/iris_operator_amd-3.5.48.100/chart/iris-operator

# tag iris-oauth-fhir

docker tag iris-oauth-fhir-iris:latest k3d-registry.localhost:5000/iris-oauth-fhir-iris:latest

# push iris-oauth-fhir

docker push k3d-registry.localhost:5000/iris-oauth-fhir-iris:latest

# deploy iris-oauth-fhir

kubectl apply -f config/iris-simple.yaml

# forward port

kubectl port-forward pods/sample-data-0 1975:1972 52775:52773 -n default

# remove deployment

kubectl delete -f config/iris-simple.yaml

# add a web gateway
## tag web gateway

docker tag containers.intersystems.com/intersystems/webgateway:2023.1.1.380.0-linux-amd64 k3d-registry.localhost:5000/intersystems/webgateway:2023.1.1.380.0-linux-amd64

## push web gateway

docker push k3d-registry.localhost:5000/intersystems/webgateway:2023.1.1.380.0-linux-amd64

## deploy iris + web gateway

kubectl apply -f config/iris-web.yaml

# delete pvc

kubectl delete pvc iris-data-sample-data-0 -n default

# create configmap

kubectl create cm iriscluster-config --from-file common.cpf --from-file CSP-merge.ini

# create secret

kubectl create secret generic iriscluster-secret --from-file misc/auth/secret.json

# create certificate

openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout tls.key -out tls.crt -subj "/CN=*.localhost"

# add certificate to kubernetes

kubectl create secret tls tls-secret --key k8s/tls/tls.key --cert k8s/tls/tls.crt

# deploy iris + web gateway + tls

kubectl apply -f k8s/config/iris-web-merge.yaml

# update a configmap

kubectl create cm iriscluster-config --from-file common.cpf --from-file CSP-merge.ini -o yaml --dry-run=client | kubectl replace -f -

# ingress

helm repo add nginx-stable https://helm.nginx.com/stable
helm repo update
helm install nginx-ingress nginx-stable/nginx-ingress

# deploy ingress

kubectl apply -f k8s/config/ingress.yaml