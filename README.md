# Infrastructure as Code: Crossplane

## Introduction

[Presentation on slides.com](https://slides.com/decoder/crossplane)

## How to run slides

Slides are based on https://github.com/maaslalani/slides.

The setup should run on Mac, Linux and Windows with WSL2.

### Install Slides CLI

`go install github.com/maaslalani/slides@latest`

### Run Slides

`slides slides.md`

### Execute Commands

`ctrl + e`

## Slides Scenarios

All demos are self-contained and modular. Each main section can be ran independently.

### Folder Setup

Each scenario has a corresponding folder with Kubernetes and Crossplane yaml files. The files are sources in the slides and fed to kubectl CLI.

### Note on scripts

The main "orchestrator" or the whole setup is the `Makefile`. It calls various scripts to help with automating the cluster creation and setup process.

> Files containg sensitive information are removed after the script run and added to `.gitigignore` for additional safety.

### Prerequisites

Locally installed you will need:

- Docker Desktop or other container run time
- WSL2 if using Windows
- kubectl
- slides CLI
- make

#### Setup AWS

Install [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) and create configuration access.

> Configure default profile for AWS CLI following [this tutorial](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-quickstart.html#cli-configure-quickstart-config).

#### Setup Azure

Install [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) and create a service account

```bash
# login to Azure via browser
az login

# create service principal with Owner role
az ad sp create-for-rbac --sdk-auth --role Owner > ~/crossplane-azure-provider-key.json

export AZURE_CLIENT_ID=<clientId value from json file>

# add required Azure Active Directory permissions
az ad app permission add --id ${AZURE_CLIENT_ID} --api 00000002-0000-0000-c000-000000000000 --api-permissions 1cda74f2-2616-4834-b122-5cb1b07f8a59=Role 78c8a3c8-a07e-4b9e-af1b-b5ccab50a175=Role

# grant (activate) the permissions
az ad app permission grant --id ${AZURE_CLIENT_ID} --api 00000002-0000-0000-c000-000000000000 --expires never

# grant admin consent to the service principal you created
az ad app permission admin-consent --id "${AZURE_CLIENT_ID}"
```

> This will copy Azure SP credentials into your home directory, so there is no risk of accidentally committing them to the Git repo.

#### Local variables

You will need to export followng variables for the demo setup to work:

`export DEMODIR=<full path to the directory where you cloned this repo into>`

#### Observability

To visualize CRDs use [Octant](https://docs.vmware.com/en/VMware-vSphere/7.0/vmware-vsphere-with-tanzu/GUID-1AEDB285-C965-473F-8C91-75724200D444.html); a VMware open source cluster visualizer, running in a browser so no in-cluster installation is required.

If you like terminal tools more, [k9s](https://k9scli.io/) got you covered.

From there should be able to follow along with the demos from [Crossplane's web page](https://crossplane.io/docs/v1.5/getting-started/provision-infrastructure.html) and scenarios from this document.

### Create Cluster

Run `make` in the root folder of the project, this will:

> If you are running on on Windows WSL2, use `make wsl` instead of `make`.

- Install [kind](https://kind.sigs.k8s.io/) (Kubernetes IN Docker) if not already installed
- Create kind cluster called crossplane-cluster and swap context to it
- Install crossplane using helm
- Install crossplane CLI if not already installed
- Install AWS provider on the cluster
- Create a temporary file with AWS credentials based on default CLI profile
- Create a secret with AWS credentials in crossplane-system namespace
- Configure AWS provider to use the secret for provisioning the infrastructure
- Install and confugure Azure provider on the cluster
- Install Kubernetes provider
- Install Kyverno for the authorization demo
- Remove the temporary files with credentials so it's not accidentally checked in the repository

> Crossplane should be installed in a _crossplane-system_ namespace and AWS, Azure and Kubernetes providers providers ready to go.
Use following commands to validate the installation:

- check if all crossplane components were installed correctly `kubectl get all -n crossplane-system`
- check if the AWS provider was installed `kubectl get pkg`
- make sure that credentials propagated correctly into the Kubernetes secret `k get secrets -n crossplane-system aws-creds -o jsonpath="{.data.creds}" | base64 --decode`

Use following commands to check various crossplane resources:

- `kubectl get claim`: get all resources of all claim kinds.
- `kubectl get compositions`: get all resources that are of composite kind.
- `kubectl get managed`: get all resources that represent a unit of external infrastructure.
- `kubectl get <name-of-provider>`: get all resources related to <provider>.
- `kubectl get crossplane`: get all resources related to Crossplane.

## Conclusion

We have seen how Crossplane can help make infrastructure provisioning and management easier. Here are a few benefits I would like to highlight.

- Composable Infrastructure
- Self-Service
- Increased Automation
- Standardized collaboration
- Ubiquitous language (K8s API)

What I like most about Crossplane is that it’s built with the DevOps culture in mind by promoting loosely coupled collaboration between Applications Teams and Platform Teams. The resource model, packaging, configuration are well thought out.

There are also a few challenges to keep in mind:

- Complexity, it’s a price to pay for the flexibility it provides
- YAML proliferation, which is good or bad depending on where you stand on YAML ;)
- You need to know K8s well

Complexity is addressed by moving it to specialized Platform Teams. For YAML I would love to see more push for integrating YAML generation like CDK8s or others. I see reliance on K8s as a benefit, but for those of us who are not yet comfortable with Kubernetes, this makes the learning curve a bit steeper.

In summary, Crossplane is a great product, it appeared at the right time and solves decades all problems in a very innovative and future proof way.

