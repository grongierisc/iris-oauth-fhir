# IRIS Operator
[IRIS Operator by intersystems](https://github.com/kubeIRIS/operator) - InterSystems IRIS Operator for Kubernetes

## Introduction

This chart bootstraps an [InterSystems IRIS Operator](https://docs.intersystems.com/irislatest/csp/docbook/DocBook.UI.Page.cls?KEY=PAGE_DEPLOYMENT_IKO) on a [Kubernetes](http://kubernetes.io) cluster using the [Helm](https://helm.sh) package manager.

Please see linked documentation above for pre-requisites and installation procedure.


## Installing the Chart
To install the chart with the release name `iris-operator`:

```console
$ helm install intersystems iris_operator-3.3.0.120/chart/iris-operator --namespace intersystems 
```

The command deploys IRIS operator on the Kubernetes cluster in the default configuration. The [configuration](#configuration) section lists the parameters that can be configured during installation.

> **Tip**: List all releases using `helm list`

## Uninstalling the Chart

To uninstall/delete the `iris-operator`:

```console
$ helm uninstall iris-operator --namespace intersystems
```

The command removes all the Kubernetes components associated with the chart and deletes the release.

## Configuration

The following table lists the configurable parameters of the IRIS chart and their default values.


| Parameter                               | Description                                                        | Default            |
| --------------------------------------- | ------------------------------------------------------------------ | ------------------ |
| `replicaCount`                          | Number of IRIS operator replicas to create (only 1 is supported)  | `1`                |
| `operator.registry`                     | Docker registry used to pull IRIS operator image                  | `kubeIRIS`        |
| `operator.repository`                   | IRIS operator container image                                     | `iris-operator`   |
| `operator.tag`                          | IRIS operator container image tag                                 | `3.3.0.120`            |
| `cleaner.registry`                      | Docker registry used to pull Webhook cleaner image                 | `intersystems`         |
| `cleaner.repository`                    | Webhook cleaner container image                                    | `kubectl`          |
| `cleaner.tag`                           | Webhook cleaner container image tag                                | `v1.11`            |
| `imagePullSecrets`                      | Specify image pull secrets                                         | `nil` (does not add image pull secrets to deployed pods) |
| `imagePullPolicy`                       | Image pull policy                                                  | `IfNotPresent`     |
| `criticalAddon`                         | If true, installs IRIS operator as critical addon                 | `false`            |
| `logLevel`                              | Log level for operator                                             | `3`                |
| `affinity`                              | Affinity rules for pod assignment                                  | `{}`               |
| `nodeSelector`                          | Node labels for pod assignment                                     | `{}`               |
| `tolerations`                           | Tolerations used pod assignment                                    | `{}`               |
| `rbac.create`                           | If `true`, create and use RBAC resources                           | `true`             |
| `serviceAccount.create`                 | If `true`, create a new service account                            | `true`             |
| `serviceAccount.name`                   | Service account to be used. If not set and `serviceAccount.create` is `true`, a name is generated using the fullname template                                              | ``                                                        |
| `apiserver.groupPriorityMinimum`        | The minimum priority the group should have.                        | 10000              |
| `apiserver.versionPriority`             | The ordering of this API inside of the group.                      | 15                 |
| `apiserver.enableValidatingWebhook`     | Enable validating webhooks for IRIS CRDs                          | true               |
| `apiserver.enableMutatingWebhook`       | Enable mutating webhooks for IRIS CRDs                            | true               |
| `apiserver.ca`                          | CA certificate used by main Kubernetes api server                  | `not-ca-cert`      |
| `apiserver.disableStatusSubresource`    | If true, disables status sub resource for crds. Otherwise enables based on Kubernetes version | `false`            |
| `apiserver.bypassValidatingWebhookXray` | If true, bypasses validating webhook xray checks                   | `false`            |
| `apiserver.useKubeapiserverFqdnForAks`  | If true, uses kube-apiserver FQDN for AKS cluster to workaround https://github.com/Azure/AKS/issues/522 | `true`             |
| `apiserver.healthcheck.enabled`         | Enable readiness and liveliness probes                             | `true`             |
| `monitoring.agent`                      | Specify which monitoring agent to use for monitoring IRIS. It accepts either `prometheus.io/builtin` or `prometheus.io/coreos-operator`.                                  | `none`                                                    |
| `monitoring.operator`                   | Specify whether to monitor IRIS operator.                                                                                                                                 | `false`                                                   |
| `monitoring.prometheus.namespace`       | Specify the namespace where Prometheus server is running or will be deployed.                                                                                              | Release namespace                                         |
| `monitoring.serviceMonitor.labels`      | Specify the labels for ServiceMonitor. Prometheus crd will select ServiceMonitor using these labels. Only usable when monitoring agent is `prometheus.io/coreos-operator`. | `app: <generated app name>` and `release: <release name>` |

Specify each parameter using the `--set key=value[,key=value]` argument to `helm install`. For example:

```console
$ helm install --name iris-operator --set image.tag=3.3.0.120 intersystems/iris-operator
```

Alternatively, a YAML file that specifies the values for the parameters can be provided while
installing the chart. For example:

```console
$ helm install --name iris-operator --values values.yaml intersystems/iris-operator
```
