# FIWARE Data Space Connector custom service integration

![Version: 0.2.2](https://img.shields.io/badge/Version-0.2.0-informational)

## Maintainers

| Name | Email |
| ---- | ------ |
| cristianmartella | <cristian.martella@unisalento.it> |

## Source Code

* <https://github.com/cristianmartella/fdsc-scenario-03>
* <https://github.com/cristianmartella/fdsc-scenario-02>
* <https://github.com/cristianmartella/fdsc-scenario-01>
* <https://github.com/FIWARE/data-space-connector>

<details>
<summary><b>Table of Contents</b></summary>

- [FIWARE Data Space Connector custom service integration](#fiware-data-space-connector-custom-service-integration)
  - [Maintainers](#maintainers)
  - [Source Code](#source-code)
  - [Introduction](#introduction)
  - [Service integration](#service-integration)
    - [Deployment as an independent service pod](#deployment-as-an-independent-service-pod)
      - [deployment.yaml](#deploymentyaml)
      - [service.yaml](#serviceyaml)
      - [ingress.yaml](#ingressyaml)
      - [Deployment of the custom service](#deployment-of-the-custom-service)
    - [Deployment as sidecar container](#deployment-as-sidecar-container)
    - [APISIX configuration](#apisix-configuration)
      - [openid-configuration](#openid-configuration)
      - [data-space-configuration](#data-space-configuration)
      - [Service endpoint](#service-endpoint)
  - [Custom credential type configuration](#custom-credential-type-configuration)
    - [Consumer side - Keycloak](#consumer-side---keycloak)
    - [Provider side - Credential configuration](#provider-side---credential-configuration)
  - [Deployment](#deployment)
    - [Quick deployment scripts](#quick-deployment-scripts)
      - [1. Deploy the cluster](#1-deploy-the-cluster)
      - [2. Deploy the Trust Anchor](#2-deploy-the-trust-anchor)
      - [3. Deploy the Provider](#3-deploy-the-provider)
      - [4. Deploy the Consumer](#4-deploy-the-consumer)
      - [5. Create a wallet for a Consumer's user](#5-create-a-wallet-for-a-consumers-user)
  - [Workflow](#workflow)
    - [1. Configure the ODRL policies](#1-configure-the-odrl-policies)
      - [RustAPITest service policy](#rustapitest-service-policy)
      - [Scorpio data service policy](#scorpio-data-service-policy)
    - [2. Register the provider and the consumer at the Trust Anchor](#2-register-the-provider-and-the-consumer-at-the-trust-anchor)
    - [3. Create a wallet for the user that operates on behalf of the Consumer](#3-create-a-wallet-for-the-user-that-operates-on-behalf-of-the-consumer)
    - [4. Issue the verifiable credentials](#4-issue-the-verifiable-credentials)
    - [5. Exchange the JWT tokens](#5-exchange-the-jwt-tokens)
    - [6. Verify the policies in action](#6-verify-the-policies-in-action)
      - [Test 01: Valid token scope (should succeed - 200 OK)](#test-01-valid-token-scope-should-succeed---200-ok)
      - [Test 02: Invalid token scope (should fail - 403 Forbidden)](#test-02-invalid-token-scope-should-fail---403-forbidden)
      - [Test 03: Valid token scope with data service (should succeed - 201 Created)](#test-03-valid-token-scope-with-data-service-should-succeed---201-created)
      - [Test 04: Valid token scope but wrong entity type (should fail - 403 Forbidden)](#test-04-valid-token-scope-but-wrong-entity-type-should-fail---403-forbidden)
      - [Test 05: Invalid token scope (should fail - 403 Forbidden)](#test-05-invalid-token-scope-should-fail---403-forbidden)
  - [License](#license)

</details>

## Introduction

This implementation aims to demonstrate how to successfully integrate a custom data service within the FIWARE Data Space Connector (FDSC) and configure custom credential for accessing it through ad-hoc ODRL policies. The participants included in this scenario are data Provider and a data Consumer.

## Service integration

In this scenario, the prerequisite to include a custom service as part of the FDSC deployment is to ensure that it is available on a public container image registry, such as `quay.io` or `docker.hub`. For the purposes of this demo, a simple RESTful API service coded in Rust and conveniently called [RustAPITest](https://hub.docker.com/r/cristianmartella/rustapitest) will be used.

There are two main approaches to configure the integration of a new service in the Kubernetes environment hosting the FDSC ecosystem.

### Deployment as an independent service pod

The first method consists of writing the proper `deployment.yaml`, `service.yaml` and (optionally) `ingress.yaml` files and applying them to the running instance of the FDSC.

#### deployment.yaml

This file contains the deployment information, including the path to the service container image on the public registry, the service name and the image pull policy.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    k8s-app: rustapitest
  name: rustapitest
  namespace: provider
spec:
  replicas: 1
  selector:
    matchLabels:
      k8s-app: rustapitest
  template:
    metadata:
      labels:
        k8s-app: rustapitest
      name: rustapitest
    spec:
      containers:
        - image: cristianmartella/rustapitest:0.1.1
          imagePullPolicy: Always
          name: rustapitest
      restartPolicy: Always
```

#### service.yaml

This file contains the service specifications, including the networking configuration for ports forwarding.

> [!Note]
> Configurations are applied to the services matched by the selector tag. In this case, to ensure that the configuration successfully targets the rustapitest service, it is necessary to match the value of the k8s-app label defined in the deployment's template metadata section.

The rustapitest service listens to requests on port 8085. The service.yaml file serves the purpose of making this port available to the k8s environment. To this end, it allows to specify a service type which, for the purposes of this scenario, is set to `LoadBalancer`. The reason of this choice lies in the suitability of this option for services that require high scalability and availability for handling high traffic volumes. With this configuration, Kubernetes provisions a public IP and assigns a port number from a predefined range of 30000-32767 (customizable via the `nodePort` option) to access the service externally. However, it is possible to expose a custom port by specifying the `port` value. In other words, the service exposes port 8085 (`port`) and forwards the traffic to the pods’ port 8085 (`targetPort`).

```yaml
apiVersion: v1
kind: Service
metadata:
  labels:
    k8s-app: rustapitest
  name: rustapitest
  namespace: provider
spec:
  ports:
    - name: tcp-8085-8085-ksfgp
      nodePort: 30386
      port: 8085
      protocol: TCP
      targetPort: 8085
  selector:
    k8s-app: rustapitest
  type: LoadBalancer
```

#### ingress.yaml

The ingress configuration is optional and allows to establish an endpoint to the service for external access. The configuration includes a mapping of a custom hostname (`rustapitest.127.0.0.1.nip.io`) to the service name (`rustapitest`) and port (`8085`).

> [!Note]
> Provisioning an ingress is not required when the internal endpoint of the service is mapped and secured via an APISIX route.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: rustapitest-ingress
  namespace: provider
spec:
  rules:
    - host: rustapitest.127.0.0.1.nip.io
      http:
        paths:
          - backend:
              service:
                name: rustapitest
                port:
                  number: 8085
            path: /
            pathType: Prefix
```

#### Deployment of the custom service

Supposing the service configuration files are located in the `../charts/rustapitest/templates` path, they can be applied to deploy the pod that runs the custom service as follows:

```bash
kubectl apply -f ../charts/rustapitest/templates -n <namespace>
```

Deployment with helm can be made possible by templating the chart.

### Deployment as sidecar container

An alternative to the independent service pod deployment described [above](#deployment-as-an-independent-service-pod) is to deploy the service as a sidecar container of another service. In this way, it will run along the main application container within the same pod. According to the official [documentation](https://kubernetes.io/docs/concepts/workloads/pods/sidecar-containers/), sidecar containers are mainly used to *enhance or extend the functionality of the primary application container by providing additional services, or functionality such as logging, monitoring, security or data synchronization, without directly altering the primary application code*.

The FDSC templates offer sidecar deployment opportunities, but it is important to note that some templates already embed sidecars definition, and editing the `values.yaml` file is a destructive operation in this sense, overriding the original definitions and impeding the successful deployment of the overall FDSC participant instance.

For instance, considering the APISIX configuration, there two pods: one for the control plane and one for the data plane. The least invasive option to successfully embed a sidecar container in this sense is to exploit the sidecar interface provided by the control plane configuration which, by default, [is not used](https://github.com/bitnami/charts/blob/main/bitnami/apisix/values.yaml#L1305). The data plane, instead, hosts the [OPA service](https://github.com/FIWARE/data-space-connector/blob/main/charts/data-space-connector/values.yaml#L254) as sidecar by default, and customizing the values.yaml would override this container definition, preventing its deployment.

The following `values.yaml` configuration allows to run the RustAPITest service as sidecar container of the APISIX control plane service. The `service` setup is used to configure the port forwarding, remapping port 8085 exposed by the container to the target port 8085 of the pod's endpoint, ensuring the reachability of the service at the `provider-dsc-apisix-control-plane:8085` internal endpoint.

```yaml
apisix:
    ...
    controlPlane:
        sidecars:
          - name: rustapitest
            image: cristianmartella/rustapitest:0.1.1
            imagePullPolicy: Always
            ports:
              - name: http
                containerPort: 8085
                protocol: TCP

        service:
            extraPorts:
              - name: rustapitest-port
                port: 8085
                targetPort: 8085
```

Optionally, it is also possible to configure the corresponding ingress by including the following definition:

```yaml
apisix:
    ...
    controlPlane:
    ...
    ingress:
        enabled: true
        hostname: rustapitest.127.0.0.1.nip.io
        paths:
          - "/"
        pathType: Prexix
        serviceName: provider-dsc-apisix-control-plane
        servicePort: 8085
```

> [!Note]
> The `serviceName` must match the pod's main application name.

### APISIX configuration

As an alternative to the ingress configuration, it is possible to configure the APISIX data plane to secure the endpoint and allow the definition of ad hoc policies that regulate the inbound traffic.

First and foremost, the APISIX data plane's ingress should include the new extra hostname `rustapitest.127.0.0.1.nip.io`:

```yaml
dataPlane:
    ingress:
        ...
        extraHosts:
        ...
          - name: rustapitest.127.0.0.1.nip.io
            path: /
```

Subsequently, the following three routes are added to the setup:

#### openid-configuration

```yaml
  - uri: /.well-known/openid-configuration
    host: rustapitest.127.0.0.1.nip.io
        upstream:
        nodes:
            verifier:3000: 1
        type: roundrobin
    plugins:
        proxy-rewrite:
            uri: /services/rustapitest-service/.well-known/openid-configuration
```

#### data-space-configuration

```yaml
  - uri: /.well-known/data-space-configuration
    host: rustapitest.127.0.0.1.nip.io
        upstream:
            nodes:
                dsconfig:3002: 1
            type: roundrobin
        plugins:
            proxy-rewrite:
                uri: /.well-known/data-space-configuration/data-space-configuration.json
            response-rewrite:
                headers:
                    set:
                        content-type: application/json
```

#### Service endpoint

```yaml
  - uri: /*
    host: rustapitest.127.0.0.1.nip.io
    upstream:
        nodes:
            provider-dsc-apisix-control-plane:8085: 1
        type: roundrobin
    plugins:
        # verify the jwt at the verifiers endpoint
        openid-connect:
            bearer_only: true
            use_jwks: true
            client_id: rustapitest-service
            client_secret: unused
            ssl_verify: false
            discovery: http://verifier:3000/services/rustapitest-service/.well-known/openid-configuration
        # request decisions at opa
        opa:
            host: "http://localhost:8181"
            policy: policy/main
            with_body: true
```

## Custom credential type configuration

The new service exposes a new endpoint that needs to be accessed externally. In some cases, the separation of responsibilities leads to the necessity to define RBAC rules to assign a path to a specific class of users that detain an allowed credential type.
To this end, it is possible to configure the FDSC auth services to enable the issuance of a custom credential type and define ODRL policies that implement the decisions per path to authorize the traffic of target credential types' detainers.

In the following, the `RustApiTestCredential` custom credential will be included.

### Consumer side - Keycloak

To issue `RustApiTestCredential` verifiable credentials, the Keycloak realm needs to be properly configured.
The following lines should be embedded in the `Keycloack.realm.clients` JSON payload.

> [!Note]
> The following snippets are simplified to highlight the location of the changes in the *standard* definition. The complete code is documented in the [fdsc-scenario-01 repository](https://github.com/cristianmartella/fdsc-scenario-01/blob/master/doc/consumer/CONSUMER.MD#keycloak-realm-configuration).

```json
{
    ...
    "attributes": {
        ...
        "vc.rustapitest-credential.format": "jwt_vc",
        "vc.rustapitest-credential.scope": "RustApiTestCredential"
    },
    "protocolMappers": [
        ...
        {
            "name": "context-mapper",
            ...
            "config": {
                ...
                "supportedCredentialTypes": "VerifiableCredential,UserCredential,OperatorCredential,RustApiTestCredential"
            }
        },
        {
            "name": "email-mapper",
            ...
            "config": {
                ...
                "supportedCredentialTypes": "UserCredential,OperatorCredential,RustApiTestCredential"
            }
        },
        {
            "name": "firstName-mapper",
            ...
            "config": {
                ...
                "supportedCredentialTypes": "UserCredential,OperatorCredential,RustApiTestCredential"
            }
        },
        {
            "name": "lastName-mapper",
            ...
            "config": {
                ...
                "supportedCredentialTypes": "UserCredential,OperatorCredential,RustApiTestCredential"
            }
        }
    ]
}
```

### Provider side - Credential configuration

To allow the exchange of JWT tokens for the `RustApiTestCredential` verifiable credentials at the `rustapitest.127.0.0.1.nip.io` endpoint, the `credentials-config-service` (ccs) must be instructed accordingly. Services such as `scorpio` and `tmf-api` include an ad-hoc `ccs` definition within their templates, facilitating the setup in this sense. As an alternative, it is possible to POST the configuration JSON payload with the internal `credentials-config-service:8080/service` endpoint.

In this scenario, the JSON payload to POST is the following:

```json
{
   "id":"rustapitest-service",
   "defaultOidcScope":"rustapitest",
   "oidcScopes":{
      "rustapitest":[
         {
            "type":"RustApiTestCredential",
            "trustedParticipantsLists":[
               "http://tir.trust-anchor.svc.cluster.local:8080"
            ],
            "trustedIssuersLists":[
               "http://trusted-issuers-list:8080"
            ]
         }
      ]
   }
}
```

To automate the registration of the `RustApiTestCredential` at the ccs at the startup of the FDSC instance, it is possible to deploy an additional sidecar container. Such a container will run a script that attempts to POST the above payload until the response code is 200.

Follows the complete sidecar definition:

```yaml
  - name: register-ccs
    image: alpine:latest
    imagePullPolicy: IfNotPresent
    command: ["/bin/sh", "-c", "
        apk add --no-cache curl jq;
        payload='{\"id\":\"rustapitest-service\",\"defaultOidcScope\":\"rustapitest\",\"oidcScopes\":{\"rustapitest\":[{\"type\":\"RustApiTestCredential\",\"trustedParticipantsLists\":[\"http://tir.trust-anchor.svc.cluster.local:8080\"],\"trustedIssuersLists\":[\"http://trusted-issuers-list:8080\"]}]}}';
        status_code=0;
        response='';
        echo \"Registering service with credentials-config-service\";
        while [ $status_code -ne 200 ] || [ -z $response ]; do
        echo \"Sending request\";
        response=$(curl -X POST http://credentials-config-service:8080/service \
            -H \"Content-Type: application/json\" \
            -d \"$payload\");
        status_code=$(echo $response | jq -r '.status');
        echo \"Response status code: $status_code\";
        echo \"Response body: $response\";
        done;
        echo \"Service registered successfully\";
        sleep infinity;
        "
    ]
```

## Deployment

The comprehensive overviews of the deployment steps documented in the fdsc-scenario-01 repository are valid for the [k3s cluster](https://github.com/cristianmartella/fdsc-scenario-01#setup-k3s-cluster), the [trust-anchor](https://github.com/cristianmartella/fdsc-scenario-01/blob/master/doc/trust-anchor/TRUST-ANCHOR.MD#deployment-of-the-trust-anchor), the [consumer](https://github.com/cristianmartella/fdsc-scenario-01/blob/master/doc/consumer/CONSUMER.MD#deployment-of-the-consumer) and the [provider](https://github.com/cristianmartella/fdsc-scenario-01/blob/master/doc/provider/PROVIDER.MD#deployment-of-the-provider).

### Quick deployment scripts

Quick deployment scripts are available in the `scripts` folder. The following table provides a brief description of the scripts and includes links to the corresponding documentation sources.

| **script** | **options** | **usage** | **description** |
| --- | --- | --- | --- |
| [00.cleanup.sh](https://github.com/cristianmartella/fdsc-scenario-02/blob/master/doc/SCRIPTS.MD#cleanup-script) | -p delete persistent volumes<br>-f remove the *k3s-maven-plugin* docker container and its volumes | [source] ./00.cleanup.sh [-p -f] | Uninstall the deployed pods, remove the namespaces and delete the persistent volumes |
| [01.deploy_cluster.sh](https://github.com/cristianmartella/fdsc-scenario-02/blob/master/doc/SCRIPTS.MD#k3s-cluster-deployment) | - | [source] ./01.deploy_cluster.sh | Performs all the operations required to configure and deploy a base k3s cluster |
| 02.deploy_k8s_dashboard.sh | - | ./02.deploy_k8s_dashboard.sh | (Optional) Deploys the k8s dashboard. Use the displayed token to access the dashboard at <http://locahost:8444> |
| [03.deploy_trust_anchor.sh](https://github.com/cristianmartella/fdsc-scenario-02/blob/master/doc/SCRIPTS.MD#trust-anchor-deployment) | - | ./03.deploy_trust_anchor.sh | Deploys the Trust Anchor |
| [04.deploy_provider.sh](https://github.com/cristianmartella/fdsc-scenario-02/blob/master/doc/SCRIPTS.MD#provider-deployment) | -p path/to/provider/ (defaults to ../provider)<br>-c [path/to/certificate/details/](https://github.com/cristianmartella/fdsc-scenario-01/blob/master/doc/SCRIPTS.MD#example-provider-certificateconf) | ./04.deploy_provider.sh [-p path/to/provider/ -c path/to/certificate/details/] | Configures and deploys the Provider |
| 05.deploy_rustapitest.sh | - | ./05.deploy_rustapitest.sh | (Optional) Deploys the RustAPITest service in the [independent pod configuration](#deployment-as-an-independent-service-pod) |
| [06.deploy_consumer.sh](https://github.com/cristianmartella/fdsc-scenario-01/blob/master/doc/SCRIPTS.MD#consumer-deployment) | -c [/path/to/certificate/details](https://github.com/cristianmartella/fdsc-scenario-01/blob/master/doc/SCRIPTS.MD#example-consumer-certificateconf) | ./06.deploy_consumer.sh [-c /path/to/certificate/details] | Configures and deploys the Consumer |
| [07.create_wallet.sh](https://github.com/cristianmartella/fdsc-scenario-01/blob/master/doc/SCRIPTS.MD#wallet-identity-creation) | -p wallet-path<br>-n vc-issuer-name (defaults to `consumer`) | [source] ./07.create_wallet.sh [-p wallet-path -n vc-issuer-name] | Creates a wallet for a Consumer's user |

The minimal deployment of the FDSC instance using the quick deployment scripts can be accomplished with the following sequence of operations:

#### 1. Deploy the cluster

```bash
. ./01.deploy_cluster.sh
```

#### 2. Deploy the Trust Anchor

```bash
./03.deploy_trust_anchor.sh
```

#### 3. Deploy the Provider

```bash
./04.deploy_provider.sh -c ../provider/.certificate.conf
```

#### 4. Deploy the Consumer

```bash
./06.deploy_consumer.sh -c ../consumer/.certificate.conf
```

#### 5. Create a wallet for a Consumer's user

```bash
./07.create_wallet.sh -p ../wallet
```

## Workflow

Once the FDSC instance is deployed, it is possible to operate the proper configurations to demostrate the successful integration of the custom service and its accessibility only through the custom credentials.

### 1. Configure the ODRL policies

In this scenario the goal is to provide access to users authenticated with `RustApiTestCredential` VC type to the RustAPITest custom service available at `rustapitest.127.0.0.1.nip.io:8080/users`, and map the `UserCredential` VC type to the Scorpio data service available at `mp-data-service.127.0.0.1.nip.io:8080/ngsi-ld/v1/entities`, allowing only to manage entities of a given type.

To this end, it is possible to interact with the PAP (available at `http://pap-provider.127.0.0.1.nip.io:8080/policy`) to POST two ODRL policies. The definition and description of such policies is reported in the following and is compliant with the [ODRL-PAP REGO mappings](https://github.com/wistefan/odrl-pap/blob/main/doc/REGO.md).

#### RustAPITest service policy

To allow traffic from users authenticated as `RustApiTestCredential` there are two constraints to configure: the **permission target** and the **permission assignee**.

The **permission target** allows to define the set of resources the policy refers to, in this case the http path `/users` that identifies the `rustapitest.127.0.0.1.nip.io:8080/users` target.

```json
"odrl:target": {
    "@type": "odrl:AssetCollection",
    "odrl:source": "urn:asset",
    "odrl:refinement": [
        {
            "@type": "odrl:Constraint",
            "odrl:leftOperand": "http:path",
            "odrl:operator": {
                "@id": "http:isInPath"
            },
            "odrl:rightOperand": {
                "@value": "/users",
                "@type": "xsd:string"
            }
        }
    ]
}
```

The **permission assignee** allows to constrain the pool of credentials permitted by this policy, in this case the `RustApiTestCredential`.

```json
"odrl:assignee": {
    "@type": "odrl:PartyCollection",
    "odrl:source": "urn:user",
    "odrl:refinement": {
        "@type": "odrl:Constraint",
        "odrl:leftOperand": {
            "@id": "vc:type"
        },
        "odrl:operator": {
            "@id": "odrl:hasPart"
        },
        "odrl:rightOperand": {
            "@value": "RustApiTestCredential",
            "@type": "xsd:string"
        }
    }
}
```

Follows the full policy JSON definition:

```json
{ 
    "@context": {
        "dc": "http://purl.org/dc/elements/1.1/",
        "dct": "http://purl.org/dc/terms/",
        "owl": "http://www.w3.org/2002/07/owl#",
        "odrl": "http://www.w3.org/ns/odrl/2/",
        "rdfs": "http://www.w3.org/2000/01/rdf-schema#",
        "skos": "http://www.w3.org/2004/02/skos/core#"
    },
    "@id": "https://mp-operation.org/policy/common/type",
    "@type": "odrl:Policy",
    "odrl:permission": {
        "odrl:assigner": {
            "@id": "https://www.mp-operation.org/"
        },
        "odrl:target": {
            "@type": "odrl:AssetCollection",
            "odrl:source": "urn:asset",
            "odrl:refinement": [
                {
                    "@type": "odrl:Constraint",
                    "odrl:leftOperand": "http:path",
                    "odrl:operator": {
                        "@id": "http:isInPath"
                    },
                    "odrl:rightOperand": {
                        "@value": "/users",
                        "@type": "xsd:string"
                    }
                }
            ]
        },
        "odrl:assignee": {
            "@type": "odrl:PartyCollection",
            "odrl:source": "urn:user",
            "odrl:refinement": {
                "@type": "odrl:Constraint",
                "odrl:leftOperand": {
                    "@id": "vc:type"
                },
                "odrl:operator": {
                    "@id": "odrl:hasPart"
                },
                "odrl:rightOperand": {
                    "@value": "RustApiTestCredential",
                    "@type": "xsd:string"
                }
            }
        },
        "odrl:action": {
            "@id": "odrl:use"
        }
    }
}
```

#### Scorpio data service policy

Similarly as above, to allow traffic from users authenticated as `UserCredential` there are two constraints to configure: the **permission target** and the **permission assignee**.

The **permission target** allows to define the set of resources the policy refers to, in this case the http path `/ngsi-ld/v1/entities` that identifies the `mp-data-service.127.0.0.1.nip.io:8080/ngsi-ld/v1/entities` target. An additional contraint refers to the permitted entity type (`K8SCluster`) that the designated users can exchange with the target data service. Hence, the permission target will feature the logic AND of two constraints.

```json
"odrl:target": {
    "@type": "odrl:AssetCollection",
    "odrl:source": "urn:asset",
    "odrl:refinement": [
        {
            "@type": "odrl:Constraint",
            "odrl:leftOperand": "http:path",
            "odrl:operator": {
                "@id": "http:isInPath"
            },
            "odrl:rightOperand": {
                "@value": "/ngsi-ld/v1/entities",
                "@type": "xsd:string"
            }
        },
        {
            "@type": "odrl:Constraint",
            "odrl:leftOperand": "ngsi-ld:entityType",
            "odrl:operator": {
                "@id": "odrl:eq"
            },
            "odrl:rightOperand": "K8SCluster"
        }
    ]
}
```

The **permission assignee** allows to constrain the pool of credentials permitted by this policy, in this case the `UserCredential`.

```json
"odrl:assignee": {
    "@type": "odrl:PartyCollection",
    "odrl:source": "urn:user",
    "odrl:refinement": {
        "@type": "odrl:Constraint",
        "odrl:leftOperand": {
            "@id": "vc:type"
        },
        "odrl:operator": {
            "@id": "odrl:hasPart"
        },
        "odrl:rightOperand": {
            "@value": "UserCredential",
            "@type": "xsd:string"
        }
    }
}
```

Follows the full policy JSON definition:

```json
{ 
    "@context": {
        "dc": "http://purl.org/dc/elements/1.1/",
        "dct": "http://purl.org/dc/terms/",
        "owl": "http://www.w3.org/2002/07/owl#",
        "odrl": "http://www.w3.org/ns/odrl/2/",
        "rdfs": "http://www.w3.org/2000/01/rdf-schema#",
        "skos": "http://www.w3.org/2004/02/skos/core#"
    },
    "@id": "https://mp-operation.org/policy/common/type",
    "@type": "odrl:Policy",
    "odrl:permission": {
        "odrl:assigner": {
            "@id": "https://www.mp-operation.org/"
        },
        "odrl:target": {
            "@type": "odrl:AssetCollection",
            "odrl:source": "urn:asset",
            "odrl:refinement": [
                {
                    "@type": "odrl:Constraint",
                    "odrl:leftOperand": "http:path",
                    "odrl:operator": {
                        "@id": "http:isInPath"
                    },
                    "odrl:rightOperand": {
                        "@value": "/ngsi-ld/v1/entities",
                        "@type": "xsd:string"
                    }
                },
                {
                    "@type": "odrl:Constraint",
                    "odrl:leftOperand": "ngsi-ld:entityType",
                    "odrl:operator": {
                        "@id": "odrl:eq"
                    },
                    "odrl:rightOperand": "K8SCluster"
                }
            ]
        },
        "odrl:assignee": {
            "@type": "odrl:PartyCollection",
            "odrl:source": "urn:user",
            "odrl:refinement": {
                "@type": "odrl:Constraint",
                "odrl:leftOperand": {
                    "@id": "vc:type"
                },
                "odrl:operator": {
                    "@id": "odrl:hasPart"
                },
                "odrl:rightOperand": {
                    "@value": "UserCredential",
                    "@type": "xsd:string"
                }
            }
        },
        "odrl:action": {
            "@id": "{{04_ODRL-ACTION}}"
        }
    }
}
```

### 2. Register the provider and the consumer at the Trust Anchor

The participants can be registrated at the Trust Anchor by POSTing their DIDs at the Trusted Issuers List service endpoint `http://til.127.0.0.1.nip.io:8080/issuer`. The JSON payload is structured as follows:

```json
{
    "did": "<PARTICIPANT-DID>",
    "credentials": []
}
```

Consumer and Provider's DIDs are conveniently located in the respective identity folders in a file called `did.key`. DID keys are also displayed after the successful deployment of the Consumer and the Provider.

### 3. Create a wallet for the user that operates on behalf of the Consumer

This step is documented in the [fdsc-scenario-01 repository](https://github.com/cristianmartella/fdsc-scenario-01/blob/master/doc/provider/PROVIDER.MD#test-authorized-access) and can be conveniently simplified by running the script `07.create_wallet.sh`, as documented [above](#quick-deployment-scripts).

### 4. Issue the verifiable credentials

To issue a VC of type `UserCredential`, run the following command:

```bash
export USER_CREDENTIAL=$(./get_credential_for_consumer.sh http://keycloak-consumer.127.0.0.1.nip.io:8080 user-credential); echo ${USER_CREDENTIAL}
```

Similarly to create a VC of `RustApiTestCredential`, the following command is used instead:

```bash
export RAT_CREDENTIAL=$(./get_credential_for_consumer.sh http://keycloak-consumer.127.0.0.1.nip.io:8080 rustapitest-credential); echo ${RAT_CREDENTIAL}
```

### 5. Exchange the JWT tokens

To exchange a JWT token with the `UserCredential` VC issued in [step 4](#4-issue-the-verifiable-credentials) for the user with the identity wallet created in [step 3](#3-create-a-wallet-for-the-user-that-operates-on-behalf-of-the-consumer), the following command is used:

```bash
export USER_ACCESS_TOKEN=$(./get_access_token_oid4vp.sh http://mp-data-service.127.0.0.1.nip.io:8080 $USER_CREDENTIAL UserCredential ../wallet-identity); echo $USER_ACCESS_TOKEN
```

Similarly, the following command allows to exchange a JWT token for the same wallet with the `RustApiTestCredential` VC:

```bash
export RAT_ACCESS_TOKEN=(./get_access_token_oid4vp.sh http://rustapitest.127.0.0.1.nip.io:8080 $RAT_CREDENTIAL RustApiTestCredential ../wallet-identity); echo $RAT_ACCESS_TOKEN
```

These JWT tokens can be embedded as bearer authentication tokens in the next step to authorize the requests.

### 6. Verify the policies in action

To verify the correct execution of the policies, the following five tests are performed.

> [!Note]
> The payload of the following POST requests is merely intended for demo purposes.

#### Test 01: Valid token scope (should succeed - 200 OK)

```bash
curl -X POST http://rustapitest.127.0.0.1.nip.io:8080/users \
  -H 'accept: */*' \
  -H 'authorization: Bearer $RAT_ACCESS_TOKEN' \
  -H 'content-type: application/json' \
  -d '
    {
        "id": "urn:ngsi-ld:K8SCluster:cluster-1",
        "type": "K8SCluster",
        "name": "John Doe",
        "email": "qwer@qwer.qw"
    }'
```

#### Test 02: Invalid token scope (should fail - 403 Forbidden)

```bash
curl -X POST http://rustapitest.127.0.0.1.nip.io:8080/users \
  -H 'accept: */*' \
  -H 'authorization: Bearer $USER_ACCESS_TOKEN' \
  -H 'content-type: application/json' \
  -d '
    {
        "id": "urn:ngsi-ld:K8SCluster:cluster-1",
        "type": "K8SCluster",
        "name": "John Doe",
        "email": "qwer@qwer.qw"
    }'
```

#### Test 03: Valid token scope with data service (should succeed - 201 Created)

```bash
curl -X POST http://mp-data-service.127.0.0.1.nip.io:8080/users \
  -H 'accept: */*' \
  -H 'authorization: Bearer $USER_ACCESS_TOKEN' \
  -H 'content-type: application/json' \
  -d '
    {
        "id": "urn:ngsi-ld:K8SCluster:cluster-1",
        "type": "K8SCluster",
        "name": "John Doe",
        "email": "qwer@qwer.qw"
    }'
```

#### Test 04: Valid token scope but wrong entity type (should fail - 403 Forbidden)

```bash
curl -X POST http://mp-data-service.127.0.0.1.nip.io:8080/users \
  -H 'accept: */*' \
  -H 'authorization: Bearer $USER_ACCESS_TOKEN' \
  -H 'content-type: application/json' \
  -d '
    {
        "id": "urn:ngsi-ld:K8SCluster:cluster-1",
        "type": "K8SCluster-2",
        "name": "John Doe",
        "email": "qwer@qwer.qw"
    }'
```

#### Test 05: Invalid token scope (should fail - 403 Forbidden)

```bash
curl -X POST http://mp-data-service.127.0.0.1.nip.io:8080/users \
  -H 'accept: */*' \
  -H 'authorization: Bearer $RAT_ACCESS_TOKEN' \
  -H 'content-type: application/json' \
  -d '
    {
        "id": "urn:ngsi-ld:K8SCluster:cluster-1",
        "type": "K8SCluster",
        "name": "John Doe",
        "email": "qwer@qwer.qw"
    }'
```

## License

Copyright 2025 Cristian Martella

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

<http://www.apache.org/licenses/LICENSE-2.0>

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
