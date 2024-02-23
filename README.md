# 06-of-52--accessible-kubernetes-with-terraform-and-digitalocean

Kubernetes can be a beast, if you haven't paid the price needed to wrap your head around the full models and relationships. But it remains one of the best ways to transparently and robustly deploy complicated orchestrations in a provider-agnostic manner. Fortunately, there are combinations of tools that can help. We'll walk through a quick combination of these today.

## Before the Cluster

A new project starts with a domain name. Not for any particular reason--just that it helps to have it in place when we start managing records and defining derivative ingress rules.

So, let's assume you've used DreamHost or GoDaddy and put a few dollars down. We'll use the example `souolibrogenos.us` for this article--it's long enough to be unique, based on the name of a Celtic deity, and uses the `.us` TLD to make sure we're being super-cheap. Who's got more than two dollars to throw at this anyways!?

Most importantly, though, are the nameservers used to register records for this domain name, which you will likely need to either a) provide at purchase time, or b) customize once you've purchased your domain. Point those to DigitalOcean, which we'll be using to flesh out our tech stack, and we'll get going:

* `ns1.digitalocean.com`

* `ns2.digitalocean.com`

* `ns3.digitalocean.com`

## Setting Up the Project

Another reason we wanted to get the domain name registered first is, it's the only thing we can't define in static IAC (infrastructure-as-code). We'll be using Terraform to flesh our the rest of our Kubernetes journey here, and in combination with DigitalOcean that means *EVERYTHING* will be nicely encapsulated in Terraform resources. Now that we've pointed to the DigitalOcean nameservers (which will also dovetail nicely with cert registration later on), we can start writing our Terraform code.

To deploy DigitalOcean resources, we'll need an account and an API key. Like most cloud providers, DigitalOcean comes with some nice complementary credits upon signup. I'll pause here and take a break while you go get your token.

...

Done? Great! Pop that baby into your local shell using an environmental variable (`TF_VAR_DO_TOKEN`). We'll use this token to implicitly authorize Terraform to deploy resources to our cluster. As with any other security key, you don't want this to touch your disk--keep it in memory if possible. Instead, we'll leave it empty in our `variables.tf` file to tell Terraform that it is a required value:

```tf
variable "DO_TOKEN" {
    type = string
    description = "API token for DigitalOcean provider; pass using environmental variable $TF_VAR_DO_TOKEN"
}
```

We'll now use this token to create our `providers.tf` file at the top level of our project. *THIS IS A REALLY NEAT TRICK*: If you have a Terraform variable, it will by default be populated by an environmental variable (if one exists) that has the `TF_VAR_` prefixed to the same name. This is a slick Terraform behavior, and keeps you from being overly-reliant on a `.tfvars` file that could get accidentally added to version control.

```tf
terraform {
  required_providers {
    digitalocean = {
      source = "digitalocean/digitalocean"
      version = "2.34.1"
    }
  }
}

provider "digitalocean" {
  token = var.DO_TOKEN
}
```

We'll use folders within this project define individual Terraform modules, each of which could correspond to a Kubernetes namespace or DigitalOcean project. Let's create one now with an empty `digitalocean_project` resource where our subsequent provider-specific resources will be defined; call it "doproject" for now. Within this folder, we'll define the `digitalocean_project` resource itself, just to test our setup:

```tf
resource "digitalocean_project" "doproject" {
  name        = "doproject"
  description = "A project to represent development resources"
  purpose     = "Web Application"
  environment = "Development"
}
```

Forward the relevant provider requirements to the module (it will need its own `providers.tf`):

```tf
terraform {
  required_providers {
    digitalocean = {
      source = "digitalocean/digitalocean"
      version = "2.34.1"
    }
  }
}
```

Lastly, we'll want to make sure this module is included in our top-level `main.tf` file. I tend to include nothing *BUT* modules here, because it lets me cleanly map dependencies (including variable values) between each "step" or "app" in the deployment process.

```tf
module "doproject" {
    source = "./doproject"
}
```

Run `terraform init` and `terraform apply`, and we'll now have an "MVP" to which we can incrementally add resources as we deploy our infrastructure! Pretty neat.

## ClusterTime!

Okay, we're finally ready to deploy our Kubernetes cluster. Ready to see how difficult it is? Create another resource in our "doproject" folder/module/project, within a `docluster.tf` file. It will define a basic cluster using the `digitalocean_kubernetes_cluster` resource type.

```tf
resource "digitalocean_kubernetes_cluster" "docluster" {
  name   = "docluster"
  region = "sfo3"
  version = "1.29.1-do.0"

  node_pool {
    name       = "worker-pool"
    size       = "s-2vcpu-2gb"
    node_count = 3
  }
}
```

This is a good time to point out the excellent "slugs" reference page DigitalOcean maintains. Adjust your region and Kubernetes version as desired! You could even feed them in from variables if you wanted to.

https://slugs.do-api.dev/

Run `terraform apply` and... poof! You have a functioning Kubernetes cluster! Congratulations.

Before we get too excited, though, let's make sure this cluster is organized under the DigitalOcean project we created; modify `doproject.tf` to include it:

```tf
resource "digitalocean_project" "doproject" {
  name        = "doproject"
  description = "A project to represent development resources"
  purpose     = "Web Application"
  environment = "Development"

  resources = [
    digitalocean_kubernetes_cluster.docluster.urn
  ]
}

It's not usable yet, though, because we can't access it. Subsequent Kubernetes resources (through the provider) will need to know the cluster configuration to deploy to it. And I find it's very helpful to keep a snapshot of the `kubeconfig.yaml` so I can inspect, verify, and debug infrastructure from the command line. Let's do both.

### Come and Get Your Kubeconfig

Add an `outputs.tf` file to our "doproject" module/folder. It will extract the raw Kubernetes configuration from the deployed cluster.

```tf
output "KUBECONFIG" {
    value = digitalocean_kubernetes_cluster.docluster.kube_config[0].raw_config
    sensitive = true
}
```

Now, we can add another `outputs.tf` to the top-level project that will, in turn, let us extract the config from the command line.

```tf
output "KUBECONFIG" {
    value = module.doproject.KUBECONFIG
    sensitive = true
}
```

Run another `terraform apply` and you'll be able to pipe the results to a file (which you should *DEFINITELY* add to your `.gitignore`) and identify with a `$KUBECONFIG` environmental variable:

```sh
terraform output -raw KUBECONFIG > kubeconfig.yaml
set KUBECONFIG="%CD%/kubeconfig.yaml"
```

You can now verify that `kubectl` can communicate with your cluster:

```sh
kubectl cluster-info
```

Lastly, let's pass the specific config data to a second top-level provider, `hashicorp/kubernetes`. Add three new outputs to our "doproject" module: the cluster host, the cluster token, and the CA certificate:

```tf
output "KUBECONFIG" {
  value     = digitalocean_kubernetes_cluster.docluster.kube_config[0].raw_config
  sensitive = true
}

output "CLUSTER_HOST" {
  value = digitalocean_kubernetes_cluster.docluster.endpoint
}

output "CLUSTER_TOKEN" {
  value     = digitalocean_kubernetes_cluster.docluster.kube_config[0].token
  sensitive = true
}

output "CLUSTER_CA" {
  value     = base64decode(digitalocean_kubernetes_cluster.docluster.kube_config[0].cluster_ca_certificate)
  sensitive = true
}
```

Then, edit the top-level `providers.tf` to define the new Kubernetes provider with this information:

```tf
terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "2.34.1"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "2.26.0"
    }
  }
}

provider "digitalocean" {
  token = var.DO_TOKEN
}

provider "kubernetes" {
  host                   = module.doproject.CLUSTER_HOST
  token                  = module.doproject.CLUSTER_TOKEN
  cluster_ca_certificate = module.doproject.CLUSTER_CA
}
```

## Kubernetes Resources

We're set! We have a functioning cluster and we're ready to deploy Kubernetes resources. Let's start with a basic NGINX container to demonstrate. Create a new folder/module, "wwwnamespace". We'll use individual Terraform modules to organize specific Kubernetes namespaces, so add to this folder a `wwwnamespace.tf` file and populate accordingly:

```tf
resource "kubernetes_namespace" "wwwnamespace" {
  metadata {
    name = "wwwnamespace"
  }
}
```

Now let's revisit our top-level `main.tf` and make sure the module is included.

```tf
module "doproject" {
    source = "./doproject"
}

module "wwwnamespace" {
    source = "./wwwnamespace"
}
```

Since we create a new module, and added a new provider, you'll need to run `terraform init` again. Once that's done, run `terraform apply` and you should see your Kubernetes namespace appear in no time!

```sh
> kubectl get ns
NAME              STATUS   AGE
default           Active   15m
kube-node-lease   Active   15m
kube-public       Active   15m
kube-system       Active   15m
wwwnamespace      Active   4s
```

The basic pattern of Kubernetes orchestration looks something like this:

1. Apply a "deployment" to get a container running on a pod in your cluster namespace

2. Define a "service" to ensure that deployment is exposed on the internal network

3. Apply an "ingress" that defines how external traffic will be routed to that particular service

Let's go through each step now.

## First, the Deployment

We want a basic NGINX container. No problem! Add a `wwwdeployment.tf` to our "wwwnamespace" module and populate accordingly:

```tf
resource "kubernetes_deployment" "wwwdeployment" {
  metadata {
    name      = "wwwdeployment"
    namespace = kubernetes_namespace.wwwnamespace.metadata[0].name
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = var.APP_NAME
      }
    }

    template {
      metadata {
        labels = {
          app = var.APP_NAME
        }
      }

      spec {
        container {
          image = "nginx"
          name  = "nginx"
        }
      }
    }
  }
}
```

Notice we've used a new variable `APP_NAME` here. It's good practice to define "magic strings" as Terraform variables because it helps ensure Kubernetes (which is stateless at this level) always has consistent "knowledge" and there are no chances of fat-fingering a bad selector label. Services and other resources can use these variables, too. Let's define the `APP_NAME` value at the top level and "pass" it into the module. That means adding a `variables.tf` in our "wwwnamespace" folder/module:

```tf
variable "APP_NAME" {
  type        = string
  description = "Name used to construct selector labels and as a subdomain used in building FQDNs for ingress"
}
```

Now let's modify our top-level `main.tf` to indicate what that application's name should be:

```tf
module "doproject" {
  source = "./doproject"
}

module "wwwnamespace" {
  source   = "./wwwnamespace"
  APP_NAME = "www"
}
```

Once you've run `terraform apply` you should be able to verify that the new Kubernetes deployment (and associated pods & replicasets) are indeed up and running:

```sh
> kubectl get all -n wwwnamespace
NAME                                READY   STATUS    RESTARTS   AGE
pod/wwwdeployment-d79bb5b9d-5p8kg   1/1     Running   0          27s

NAME                            READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/wwwdeployment   1/1     1            1           27s

NAME                                      DESIRED   CURRENT   READY   AGE
replicaset.apps/wwwdeployment-d79bb5b9d   1         1         1       27s
```

### Next, the Service

We need to identify this deployment within our internal cluster network. To do so, we'll next add a `wwwservice.tf` file and populate accordingly:

```tf
resource "kubernetes_service" "wwwservice" {
  metadata {
    name      = "wwwservice"
    namespace = kubernetes_namespace.wwwnamespace.metadata[0].name
  }

  spec {
    selector = {
      app = var.APP_NAME
    }

    port {
      port        = 80
      target_port = 80
    }
  }
}
```

Note the use of the `APP_NAME` variable to ensure we are applying the correct selector labels consistently. Run a `terraform apply` and verify the new Service now exists:

```sh
> kubectl get all -n wwwnamespace
NAME                                READY   STATUS    RESTARTS   AGE
pod/wwwdeployment-d79bb5b9d-5p8kg   1/1     Running   0          5m27s

NAME                 TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)   AGE
service/wwwservice   ClusterIP   10.245.48.185   <none>        80/TCP    15s

NAME                            READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/wwwdeployment   1/1     1            1           5m27s

NAME                                      DESIRED   CURRENT   READY   AGE
replicaset.apps/wwwdeployment-d79bb5b9d   1         1         1       5m27s
```

### Lastly, the Ingress

A careful observer will note that we didn't define a Service "type". In our case, this defaulted to "ClusterIP", which means the service was assigned a specific address on the internal Kubernetes network. This does not, however, "expose" the service for access to external users.

And here's where things get fun. A traditional cluster will have at least three "meta" applications running at any given time:

* A load balancer, to define an entry point for distribution of traffic

* An ingress controller, for enforcing ingress rules against the load balancer traffic-routing policies

* A cert manager, for automatically securing ingress TLS termination

Load balancers are particularly sticky. If you are operating an on-prem cluster, you will likely be using something like MetalLB (or something provided by your Kubernetes "substrate", like k3s or microk8s, automatically). However, if you are operating on a provider, like AWS or DigitalOcean, the load balancer is implemented by the provider.

We're going to define our ingress anyways, even though nothing exists yet to "enforce" (or secure) it. Create a `wwwingress.tf` file in our "wwwnamespace" folder/module and populate accordingly. If you're coming from a "traditional" or manual Kubernetes background, note how useful it is to procedurally bind to the service properties! Terraform really is wonderful.

```tf
resource "kubernetes_ingress_v1" "wwwingress" {
  metadata {
    name      = "wwwingress"
    namespace = kubernetes_namespace.wwwnamespace.metadata[0].name
  }

  spec {
    rule {
      host = "${var.APP_NAME}.${var.HOST_NAME}"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service.wwwservice.metadata[0].name

              port {
                number = kubernetes_service.wwwservice.spec[0].port[0].port
              }
            }
          }
        }
      }
    }
  }
}
```

One thing I should point out here: We are assuming, if you have registered `mydomain.com`, that you are organizing service ingresses under a subdomain using the "application" name we defined in `APP_NAME`. This means two things: First, that we can "dynamically" construct the `host` property of the ingress by combining the two, so long as we have also passed `HOST_NAME` into the Terraform context. Second, that we do indeed want such a "prefix" rule for our ingress paths. There are good reasons sometimes for doing otherwise, but this is a good approach for now. Modify the folder/module `variables.tf` accordingly:

```tf
variable "APP_NAME" {
  type        = string
  description = "Name used to construct selector labels and as a subdomain used in building FQDNs for ingress"
}

variable "HOST_NAME" {
  type        = string
  description = "Domain under which ingress FQDNs are constructed"
}
```

And pass it in from a top-level variable (so we can re-use it later when defining DNS records), first by modifying the top-level `variables.tf`:

```tf
variable "DO_TOKEN" {
  type        = string
  description = "API token for DigitalOcean provider; pass using environmental variable $TF_VAR_DO_TOKEN"
}

variable "HOST_NAME" {
  type        = string
  description = "'Base' host name to which app names will be prepended to construct FQDNs"
}
```

And then by passing it through to the module in your `main.tf`:

```tf
module "doproject" {
  source = "./doproject"
}

module "wwwnamespace" {
  source   = "./wwwnamespace"
  APP_NAME = "www"
  HOST_NAME = var.HOST_NAME
}
```

Run a `terraform apply` and you'll see the ingress spin up. But, you can't access anything yet, because nothing is "enforcing" the ingress rule (e.g., we don't have an ingress controller), and there is no external IP assigned. Let's handle this next. But, fortunately, you'll only need to set up those things once before the previous steps will work for *all* of your similarly-deployed applications.

## The Ingress, It Must Be Controlled!

An "ingress controller" is responsible for "enforcing" the ingress rules that you create using "Ingress" resources.
