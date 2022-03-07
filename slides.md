---
theme: ./slides/theme.json
author: Piotr Zaniewski
paging: Slide %d / %d
---

# Objectives

- Learn Crossplane fundamentals in a practical way
- See how Crossplane can help standardize cloud infrastructure management
- Introduce internal platform concept

---

# What's inside

- Introduction to Crossplane
- Demo Scenarios
- Summary of sessons learned

---

# Crossplane Demo

- Understand how Crossplane solves infrastructure provisioning and configuration
- Learn about and see basic building blocks in action
- Go through practical examples of creating, consuming and managing internal platform

---

# Simple Managed Resource

This scenario deploys an RDS instance in AWS.

---

## RDS YAML Representation

```yaml
apiVersion: database.aws.crossplane.io/v1beta1
kind: RDSInstance
metadata:
  name: rdspostgresql
spec:
  forProvider:
    region: eu-central-1
    dbInstanceClass: db.t2.small
    masterUsername: masteruser
    allocatedStorage: 30
    engine: postgres
    engineVersion: "12"
    skipFinalSnapshotBeforeDeletion: true
  writeConnectionSecretToRef:
    namespace: crossplane-system
    name: aws-rdspostgresql-conn
```

---

## Create RDS Instance

Creating an infrastructure resource in the cloud with <code>kubectl</code>.

```bash
kubectl apply -f $DEMODIR/managed-resource/rds-instance.yaml
```

```bash
kubectl get managed
```

> Resources creation can be accomplished with CI/CD pipeline or GitOps tools as well

---

## Kubernetes Representation

We can see the details of RDS Instance by examining its Kubernetes representation.

```bash
kubectl describe rdsinstance.database.aws.crossplane.io
```

---

## Connection Details

Connection details to the database have been stored in a `aws-rdspostgresql-conn`
secret in the `crossplane-system` namespace.

```bash
kubectl get secrets -n crossplane-system aws-rdspostgresql-conn -o jsonpath="{.data.username}" | base64 --decode
```

Here we are retrieving a user name.

> Connection details can be stored also in external secrets management systems such as Hashicorp vault

---

## Cleanup

We have created only one managed resource. Use `kubectl` to remove it.

> The secret was generated as part of creating the managed resource and will be removed as well.

```bash
kubectl delete -f $DEMODIR/managed-resource/rds-instance.yaml --wait=false
```

```bash
kubectl get managed
```

---

## Managed Resource Key Takeaways

- High fidelity managed resources
- API calls to cloud provider control plane
- Providers and providers configuration are encapsulated
- No direct cloud access needed for developers

---

# Multi-Cloud Composition

This scenario shows:

- deployment of an EC2 instance and VPC for the VMs to AWS
- deployment of an EC2 instance and VPC for the VMs to AWS with supporting infrastructure on Azure

---

## Definition

A `CompositeResourceDefinition` (or XRD) defines the type and schema of your XR. It lets Crossplane know that you want a particular kind of XR to exist, and what fields that XR should have.

An XRD is a little like a `CustomResourceDefinition` (`CRD`), but slightly more opinionated. Writing an XRD is mostly a matter of specifying an `OpenAPI` “structural schema”.

```yaml
apiVersion: apiextensions.crossplane.io/v1
kind: CompositeResourceDefinition
metadata:
  name: xvirtualmachineinstances.vm.platform.org
spec:
  group: vm.platform.org
  names:
    kind: XVirtualMachineInstance
    plural: xvirtualmachineinstances
  claimNames:
    kind: VirtualMachineInstance
    plural: virtualmachineinstances
  versions:
    - name: v1alpha1
      served: true
      referenceable: true
      schema:
        openAPIV3Schema:
          type: object
          properties:
            spec:
              type: object
              properties:
                parameters:
                  type: object
                  properties:
                    instanceSize:
                      type: string
                  required:
                    - instanceSize
              required:
                - parameters
```

---

## Composition

A `Composition` lets Crossplane know what to do when someone creates a `Composite Resource`.

Each Composition creates a link between an `XR` and a set of one or more `Managed Resources` - when the XR is created, updated, or deleted the set of Managed Resources are created, updated or deleted accordingly.

```yaml
apiVersion: apiextensions.crossplane.io/v1
kind: Composition
metadata:
  name: xvminstances.aws.vm.platform.org
  labels:
    provider: aws
    vpc: new
spec:
  compositeTypeRef:
    apiVersion: vm.platform.org/v1alpha1
    kind: XVirtualMachineInstance
  resources:
    - name: vminstance
      base:
        apiVersion: ec2.aws.crossplane.io/v1alpha1
        kind: Instance
        spec:
          forProvider:
            subnetIdSelector:
              matchControllerRef: true
            region: eu-central-1
            imageId: ami-0a49b025fffbbdac6
            accociatePublicIpAddress: true
            keyName: ec2-sandbox
            securityGroupSelector:
              matchControllerRef: true
            publiclyAccessible: true
      patches:
        - fromFieldPath: "metadata.uid"
          toFieldPath: "spec.writeConnectionSecretToRef.name"
        - fromFieldPath: "spec.parameters.instanceSize"
          toFieldPath: "spec.forProvider.instanceType"
          transforms:
            - type: map
              map:
                small: "t2.micro"
                medium: "m1.medium"
                large: "m1.large"
```

---

## Apply Composition and Definition

Applying composition and definition resources registers them with the Crossplane’s controller and make them available in the cluster.

> By default all the Crossplane resources are cluster scoped, all but claims.
> Claims are namespace scoped and enable developers to easily create infrastructure.

```bash
kubectl apply -f $DEMODIR/ec2-composition/definition.yaml
kubectl apply -f $DEMODIR/ec2-composition/composition.yaml
```

```bash
kubectl get xrd
kubectl get compositions
```

---

## EC2 Instance Schema

Compared to complex YAML schema, here is a VM claim ready to use by developers.

```yaml
apiVersion: vm.platform.org/v1alpha1
kind: VirtualMachineInstance
metadata:
  name: sample-ec2
  namespace: default
spec:
  parameters:
    # small, medium, large
    instanceSize: small
  compositionSelector:
    matchLabels:
      provider: aws
      vpc: new
  writeConnectionSecretToRef:
    name: ec2-conn
```

> Althouth connection secret is written to the ec2-conn in default namespace, the secret is empty.
> Not all MRs are generatng secrets

---

## Create EC2 Instance

Creating EC2 Instance by using `kubectl` command. This instance will be visible in the cluster and can be managed directly by development teams.

> There are a lot of additional managed resources created behind the scenes.
> Something development teams don't have to worry about.

```bash
kubectl apply -f $DEMODIR/ec2-composition/claim-aws.yaml
```

```bash
kubectl get managed
```

---

## Register Composition with Azure Support

Here is an abbreviated composition that targets the same XRD, but this time creates also a Storage Account in Azure.

> For the sake of an example, spec values are hard-coded. In real life scenario those would be patched from a claim where appropriate.

```yaml
apiVersion: apiextensions.crossplane.io/v1
kind: Composition
metadata:
  name: xvminstances-with-support.aws.vm.platform.org
  labels:
    provider: aws-azure
    vpc: new
spec:
  writeConnectionSecretsToNamespace: crossplane-system
  compositeTypeRef:
    apiVersion: vm.platform.org/v1alpha1
    kind: XVirtualMachineInstance
  resources:
    - name: vminstance
      base:
        apiVersion: ec2.aws.crossplane.io/v1alpha1
        kind: Instance
...
    - name: supportingsa
      base:
        apiVersion: storage.azure.crossplane.io/v1alpha3
        kind: Account
        metadata:
          name: supportingsa123rfbt
          annotations:
            crossplane.io/external-name: supportingsa123rfbt
        spec:
          resourceGroupName: supporting-sa-ert54
          accountName: supportingsa123rfbt
          storageAccountSpec:
            kind: "Storage"
            location: "West Europe"
            sku:
              name: "Standard_LRS"
          writeConnectionSecretToRef:
            name: azure-sa-secret
            namespace: default
...
```

---

## Register Composition with Azure Support

Create a new composition that automatically deploys a supporting storage account to Azure.

```bash
kubectl apply -f $DEMODIR/ec2-composition/composition-with-azure.yaml
```

```bash
kubectl get compositions
```

---

### Changes in EC2 Claim Schema

```yaml
apiVersion: vm.platform.org/v1alpha1
kind: VirtualMachineInstance
metadata:
  name: sample-ec2-with-azure <- New name
  namespace: default
spec:
  parameters:
    # small, medium, large
    instanceSize: small
  compositionSelector:
    matchLabels:
      provider: aws-azure <- Target new composition
      vpc: new
  writeConnectionSecretToRef:
    name: ec2-conn-azure <- Secret name changed
```

---

### EC2 Instance with Azure Storage Account

```bash
kubectl apply -f $DEMODIR/ec2-composition/claim-aws-azure.yaml
```

```bash
kubectl get managed
```

---

### Retrieve connection information SA

```bash
kubectl get secrets -n default azure-sa-secret -o jsonpath="{.data.endpoint}" | base64 --decode
```

Here we are retrieving the storage account endpoint.

> Connection details can be stored also in external secrets management systems such as Hashicorp vault

---

## Cleanup EC2 Instance

Deleting the EC2 Instance will also remove underlying networking and storage infrastructure.
There is no need to remove resources one by one, Kubernetes reconciliation loop will ensure, that
once the EC2 Instance is deleted, VPC will also be removed.

> In a later demo we will see how to reuse existing infrastructure.

```bash
kubectl delete -f $DEMODIR/ec2-composition/claim-aws.yaml --wait=false
kubectl delete -f $DEMODIR/ec2-composition/claim-aws-azure.yaml --wait=false
kubectl delete -f $DEMODIR/ec2-composition/definition.yaml
kubectl delete -f $DEMODIR/ec2-composition/composition.yaml
kubectl delete -f $DEMODIR/ec2-composition/composition-with-azure.yaml
```

---

## Multi-Cloud Composition Key Takeaways

- Use compositions to separate platform level components from developer claims
- Use compositions to create resources in multiple cloud providers
- Crossplane enables platform and application development teams to collaborate
- Composition encapsulates complexity, hides information and abstracts lower level implementation details
- Connection details distributed as Kubernetes secret

---

# Reference Existing Resources

This scenario shows how to:

- Add new resource to an existing infrastructure
- Multitenancy of RDS Instances with shared networking
- Using K8s namespaces for isolation
- Claim vs XRD only resource

---

## Composite Network and RDS

Composite network and composite RDS composition and XRDs. Following YAML shows how reference ID for the VPC is carried over from composition to XRD.

XRD

```yaml
apiVersion: apiextensions.crossplane.io/v1
kind: CompositeResourceDefinition
metadata:
  name: compositenetworks.acmeplatform.cloud
spec:
  claimNames:
    kind: Network
    plural: networks
  group: acmeplatform.cloud
...
            spec:
              type: object
              properties:
                id: <-- reference ID
                  type: string
                  description: ID of this Network that other objects will use to refer to it.
              required:
                - id

```

Composition

```yaml
apiVersion: apiextensions.crossplane.io/v1
kind: Composition
metadata:
  name: composite-network
  labels:
    provider: aws
spec:
  writeConnectionSecretsToNamespace: devops-team
  compositeTypeRef:
    apiVersion: acmeplatform.cloud/v1alpha1
    kind: CompositeNetwork
  resources:
    - base:
...
      patches:
        - fromFieldPath: spec.id <-- same reference ID as in XRD
          toFieldPath: metadata.labels[networks.aws.platformref.crossplane.io/network-id]
...
```

---

## Composite Network and RDS registration

We are registering with Crossplane composite network and composite RDS composition/definition.

```bash
kubectl apply -f $DEMODIR/reference-resources/composite-network.yaml
kubectl apply -f $DEMODIR/reference-resources/composite-rds.yaml
```

---

## Create Namespaces

- **devops-team** represents platform team namespace where base infrastructure resides
- **team1** represents team one, this team can only create resources in their namespace
- **team2** represents team two, this team can only create resources in their namespace

```bash
kubectl create ns devops-team
kubectl create ns team1
kubectl create ns team2
```

---

## Network Stack

Network is exposed with a very simple claim.

> Note that a scenario is possible where network stack would not have a corresponding claim, thus making it cluster wide scope and accessible only for platform team.

```yaml
apiVersion: acmeplatform.cloud/v1alpha1
kind: Network
metadata:
  name: network
spec:
  id: platform-ref-aws-network
```

---

## Provision Network Stack

Now we are acting as a platform team member and provisioning base infrastructure by creating a network for the databases to connect to.

```bash
kubectl apply -f $DEMODIR/reference-resources/network-claim.yaml
kubectl get claim
kubectl get xrd
kubectl get compositions
```

---

## RDS Instance claim

Those RDS Instances will be attached to the network.

> Notice the `networkRef` field with the id matching the network claim.

```yaml
apiVersion: acmeplatform.cloud/v1alpha1
kind: PostgreSQLInstance
metadata:
  name: team1-db
  namespace: team1
spec:
  parameters:
    storageGB: 20
    networkRef:
      id: platform-ref-aws-network
  writeConnectionSecretToRef:
    name: my-db-conn-team1
```

---

### Provision RDS Instances

- base network is provisioned, now we are acting as someone from team 1, let's provision a PostgreSQL instance
- we are assuming the role of team 2 member and provisioning a separate instance of PostgreSQL database into our namespace

```bash
kubectl apply -f $DEMODIR/reference-resources/rds-claim-team1.yaml
kubectl apply -f $DEMODIR/reference-resources/rds-claim-team2.yaml
```

```bash
kubectl get managed
```

---

### Check Claims

You can see that RDS instances are provisioned only in the respective namespaces of `team1` and `team2`, whereas the VPC is provisioned in the `default` namespace.

```bash
kubectl get claim -A
```

---

## Cleanup RDS and Network

- remove the databases when ready
- finally, delete the VPC, there is no need to wait for the databases to be deleted first, Crossplane will keep reconciling the remove all resources eventually

```bash
kubectl delete -f $DEMODIR/reference-resources/network-claim.yaml
kubectl delete -f $DEMODIR/reference-resources/rds-claim-team1.yaml
kubectl delete -f $DEMODIR/reference-resources/rds-claim-team2.yaml
```

---

## Reference Existing Resource Key Takeaways

By referencing existing cloud resources, it is possible to create base infrastructure such as VPCs, storage, load balancers, etc and integrate new infrastructure with it.
This also opens up a scenario where a platform team can control the base infrastructure on the cluster level (not exposed to individual namespaces) and teams consuming the infrastructure could choose to integrate with the base or the integration could be built into the compositions.

Reusing existing cloud resources is a base requirement for building [landing zones](https://docs.microsoft.com/en-us/azure/cloud-adoption-framework/ready/landing-zone/).

> Kubernetes out of the box doesn't have a good model of referencing resources. This is only possible via annotations, which is a brittle approach. Crossplane controllers provide a native referencing functionality.

---

# Authorization and Multi tenancy

This scenario shows how to:

- Isolate tenants
- Authenticate
- Use K8s RBAC to authorize
- Use policies to manage complex authorization rules

---

## Cloud Governance

There are a few ways to govern access to resources within Crossplane. All of them are predicated on Kubernetes RBAC and often utilize existing products from cloud native ecosystem:

> This scenario assumes one centralized cluster, but there are also patterns for managing authorization on multi cluster setup

- Kubernetes RBAC and namespaces
- Isolation with Composition
- Policy Enforcement

In this use case, we are going to discuss RBAC and Composition based tenancy and demo policy enforcement scenario.

---

### Governance Models

#### Model #1: Kubernetes RBAC and namespaces

Leveraging namespaced and cluster scoped resources, where only claims are namespace specific. This approach is mixed with Kubernetes authorization mechanism to grant roles to users or groups to be able to create/manage specific resources.

#### Model #2: Isolation with Composition

In almost every scenario example, we've seen how compositions are used to expose only the necessary fields to end users. We can think of compositions as an isolation method where users can only manipulate the fields exposed to them.

#### Model #3: Policy Enforcement

Taking advantage of policy engines such as `Kyverno` or `OPA with Gatekeeper` to create fine-grained reusable policies.
In this scenario we will use `Kyverno` to apply fine grained policy to resource creation depending on a namespace.

---

## Policy Enforcement with Kyverno

Policy enforcement scenario showcases the power of Kubernetes and CNCF ecosystem and well integration. Crossplane being a Kubernetes native took, takes advantage of the fact that all other tools standardize on the Kubernetes API and can quickly extend with functionally functionally "for free" by using 3rd party CNCF projects and tools.

---

### Register Definition and Composition

Create XRD defining interface to our composite resource and composition, which by default deploys EC2 to AWS.

```bash
kubectl apply -f $DEMODIR/auth/definition.yaml
kubectl apply -f $DEMODIR/auth/composition.yaml
```

---

### Create Policy

Create Kyverno policy disallowing large VM instances for team1.

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: disallow-large-instances
  annotations:
    policies.kyverno.io/title: Disallow Large VM Instances
    policies.kyverno.io/category: Cost
    policies.kyverno.io/severity: medium
    policies.kyverno.io/subject: Cluster
    policies.kyverno.io/description: >-
      Disallow Large VM Instances
spec:
  validationFailureAction: enforce
  rules:
  - name: check-version-number
    match:
      resources:
        kinds:
        - VirtualMachineInstance
    preconditions:
    - key: "{{request.object.metadata.namespace}}"
      operator: Equals
      value: team1
    validate:
      message: "This team cannot create large VM instance due to cost reasons, large VM instances can only be created by team2"
      pattern:
        spec:
          parameters:
            instanceSize: "!large"
```

---

### Kyverno Policy

Create Kyverno policy disallowing large VM instances for team1.

```bash
kubectl apply -f $DEMODIR/auth/ec2-policy.yaml
```

---

### EC2 Claim

Now, let's try creating a large EC2 Instance in team1 namespace.

> Remember that in the Kyverno policy we have stated that **large** instances are not allowed.

```yaml
apiVersion: vm.platform.org/v1alpha1
kind: VirtualMachineInstance
metadata:
  name: sample-ec2
  namespace: team1
spec:
  parameters:
    # small, medium, large
    instanceSize: large
  compositionSelector:
    matchLabels:
      provider: aws
      vpc: new
  writeConnectionSecretToRef:
    name: ec2-conn
```

---

### Create Claim

Kyverno policy is in place, as we try to create a large EC2 instance, it should fail.

> Attempting to create a large EC2 Instance results in triggering Kyverno response and registers a `clusterpolicy` report.

```bash
kubectl apply -f $DEMODIR/auth/claim-aws.yaml
```

```bash
kubectl describe clusterpolicies
```

---

### Cleanup Policy Enforcement

Since the policy blocked creation of the large EC2 Instance, there is no need to remove managed resources from AWS.

```bash
kubectl delete -f $DEMODIR/auth/definition.yaml
kubectl delete -f $DEMODIR/auth/composition.yaml
```

---

## Authorization and Multitenancy Key Takeaways

- Integration with 3rd party tools in Kubernetes ecosystem
- Standardized cloud governance with automated tagging and centralized credentials management
- Infrastructure deployment in multi tenant environments, single and multi clusters

---

# Compose Kubernetes Application

This scenario deploy a sample K8s application consisting of:

- Deployment
- Service
- Ingress
- Horizontal Pod Autoscaler

---

## Kubernetes Provider

Provider-kubernetes is a Crossplane Provider that enables deployment and management of arbitrary Kubernetes objects on clusters typically provisioned by Crossplane:

- A Provider resource type that only points to a credentials Secret
- An Object resource type that is to manage Kubernetes Objects
- A managed resource controller that reconciles Object typed resources and manages arbitrary Kubernetes Objects

---

### Kubernetes Provider Config

```yaml
apiVersion: pkg.crossplane.io/v1alpha1
kind: ControllerConfig
metadata:
  name: crossplane-provider-kubernetes
spec:
  serviceAccountName: crossplane-provider-kubernetes

apiVersion: pkg.crossplane.io/v1
kind: Provider
metadata:
  name: crossplane-provider-kubernetes
spec:
  package: crossplane/provider-kubernetes:main
  controllerConfigRef:
    name: crossplane-provider-kubernetes
```

---

### Register Definition and Composition

```bash
kubectl apply -f $DEMODIR/k8s-applications/composition-definition.yaml
```

```bash
kubectl get managed
kubectl get xrd
kubectl get compositions
```

---

### Minimalistic Claim for Developers

```yaml
apiVersion: acmeplatform.com/v1alpha1
kind: AppClaim
metadata:
  name: platform-demo
  labels:
    app-owner: piotrzan
spec:
  id: acme-platform
  compositionSelector:
    matchLabels:
      type: frontend
  parameters:
    namespace: devops-team
    image: piotrzan/nginx-demo:green
    host: acme-platform.127.0.0.1.nip.io
```

---

### Create Resources

```bash
kubectl create ns devops-team
kubectl apply -f $DEMODIR/k8s-applications/app-claim.yaml
```

```bash
kubectl get managed
```

---

### Navigate to the web page

```bash
xdg-open https://acme-platform.127.0.0.1.nip.io/
```

---

### Modify the app

Change the image to show a blue background instead.

```bash
kubectl apply -f $DEMODIR/k8s-applications/app-claim-blue.yaml
```

---

### See All Kubernetes Resources

```bash
kubectl get pod,ingress,hpa,deployment,service -n devops-team

kubectl get managed
```

---

### Cleanup Kubernetes App

```bash
kubectl delete -f $DEMODIR/k8s-applications/app-claim.yaml
```

---

## Kubernetes Provider Key Takeaways

- Simplified Kubernetes resources consumption by developers
- Other providers based on the terrajet project
- Multiple providers in single package
- Difference between helm and the operator is that operator constantly reconciles
- Possible to create internal acme "Kubernetes Apps"

---

# Other Scenarios

Upcomming scenarios

- Packaging and distributing
- Upgrading and revisions
- Vault integration
- Managing existing cloud resources
- Referencing cloud resources
- GitOps with Flux
- Consuming infrastructure directly from Kubernetes resources

---

# Resources

- blogs on medium: <https://medium.com/@piotrzan>
- katacoda scenario: <https://www.katacoda.com/decoder/scenarios/crossplane-k8s-provider>

