# iris-oauth-fhir

## Change password in CPF

## K8s

### install k3d

wget -q -O - https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash

### install helm

curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

### create network :

docker network create k3d-net --driver=bridge --gateway=192.175.243.1 --subnet=192.175.243.0/24

### create cluster

k3d cluster create --no-hostip dev --network k3d-net -i "docker.io/rancher/k3s:v1.20.9-k3s1" --api-port 6550 -p "2222:22@loadbalancer" -p "8081:80@loadbalancer" -p "10000-10050:10000-10050@loadbalancer" -p "10500-10510:10500-10510@loadbalancer" --volume "$PWD/k8s/registries.yaml:/etc/rancher/k3s/registries.yaml" --agents 2

The docker containers created to simulate the worker nodes of our cluster will be create using the k3d-net network.

The cluster will have:

    1 master node (server node) to run core kubernetes building blocks such as CoreDNS
    2 agent nodes (worker nodes) to run our workloads (including the smart data services control plane)

K3d creates a load balancer for our cluster. We are exposing ports:

    8081 - The port to reach our Nginx ingress for the control plane
    10000-10050 - 50 ports to be allocated to services we will be deploying in the cluster

### VPN Config

cmpatch=$(kubectl get cm coredns -n kube-system --template='{{.data.Corefile}}' | sed "s/forward.*/forward . 172.16.100.100 172.17.100.100 \/etc\/resolv\.conf/g" | tr '\n' '^' | xargs -0 printf '{"data": {"Corefile":"%s"}}' | sed -E 's%\^%\\n%g') && kubectl patch cm coredns -n kube-system -p="$cmpatch"

### Create Namespace

kubectl create namespace etab-connector

### install local registry

curl -Lo skaffold https://storage.googleapis.com/skaffold/releases/latest/skaffold-darwin-amd64 && \
sudo install skaffold /usr/local/bin/

docker run -d \
--restart=always \
--network=k3d-net \
--name local-registry \
-e REGISTRY_HTTP_ADDR=0.0.0.0:5000 \
-p 5000:5000 \
registry:2

docker tag containers.intersystems.com/intersystems/iris-operator:3.1.0.112 local-registry:5000/intersystems/iris-operator:3.1.0.112

docker tag etab-connector:latest local-registry:5000/etab-connector:latest

docker push local-registry:5000/etab-connector:latest

docker push local-registry:5000/intersystems/iris-operator:3.1.0.112

helm install intersystems ./k8s/iris_operator-3.1.0.112/chart/iris-operator

kubectl apply -f values.yaml

skaffold build --default-repo=local-registry:5000


kubectl create configmap config-etab2 --from-file DefaultSettings.xml
cd k8s/raw-deploy 
kubectl apply -f 02-deploy-iris.yaml

k3d cluster delete dev
