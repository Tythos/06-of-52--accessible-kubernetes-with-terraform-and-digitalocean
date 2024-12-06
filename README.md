# 06-of-52--accessible-kubernetes-with-terraform-and-digitalocean

Kubernetes can be a beast, if you haven't paid the price needed to wrap your head around the full models and relationships. But it remains one of the best ways to transparently and robustly deploy complicated orchestrations in a provider-agnostic manner. Fortunately, there are combinations of tools that can help. We'll walk through a quick combination of these today.

## Before the Cluster

A new project starts with a domain name. Not for any particular reason--just that it helps to have it in place when we start managing records and defining derivative ingress rules.

So, let's assume you've used DreamHost or GoDaddy and put a few dollars down. We'll use the example `mydomain.com` for this article, which is of course not what you or I *actually* register.

Most importantly, though, are the nameservers used to register records for this domain name, which you will likely need to either:

1. Provide at purchase time, or

1. Customize once you've purchased your domain

Point those to DigitalOcean, which we'll be using to flesh out our tech stack, and we'll get going:

* `ns1.digitalocean.com`

* `ns2.digitalocean.com`

* `ns3.digitalocean.com`

## Setting Up the Project

Another reason we wanted to get the domain name registered first is, it's the only thing we can't define in static IAC (infrastructure-as-code). We'll be using Terraform to flesh our the rest of our Kubernetes journey here, and in combination with DigitalOcean that means *EVERYTHING* will be nicely encapsulated in Terraform resources. Now that we've pointed to the DigitalOcean nameservers (which will also dovetail nicely with cert registration later on), we can start writing our Terraform code.

To deploy DigitalOcean resources, we'll need an account and an API key. Like most cloud providers, DigitalOcean comes with some nice complementary credits upon signup. I'll pause here and take a break while you go get your token.

...

Done? Great! There are two ways to do the next step: passing this token as an environmental variable, or putting it in a `.tfvars` file where Terraform can find it. 

1. If you pop that baby into your local shell using an environmental variable (`TF_VAR_DO_TOKEN`), you can use this token to implicitly authorize Terraform to deploy resources to our cluster. *THIS IS A REALLY NEAT TRICK*: If you have a Terraform variable, it will by default be populated by an environmental variable (if one exists) that has the `TF_VAR_` prefixed to the same name.  

1. You can also add it to a gitignore'ed `.tfvars` file (as `DO_TOOKEN`). This is a little more risky, because it means a secuer value is now "touching disk" and (if you're not careful) could be accidentally added and tracked by version control. But it also provides more transparency and is more obviously identified/hooked to a specific Terraform `variable` entry.

Regardless of which approach you use, we'll want to reference it in our `variables.tf` file, leaving it empty to tell Terraform that it is a required value:

```tf
variable "DO_TOKEN" {
    type = string
    description = "API token for DigitalOcean provider; pass using environmental variable $TF_VAR_DO_TOKEN"
}
```

We'll now use this reference to create our `providers.tf` file at the top level of our project. 

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

## Modules, Projects, and Namespaces

We'll use folders within this project define individual Terraform modules, each of which could correspond to a Kubernetes namespace or DigitalOcean project (in either case, they're just sets of resources). Let's create a folder/module now with an empty `digitalocean_project` resource where our subsequent provider-specific resources will be defined; call it "doproject" for now. Within this folder, we'll define the `digitalocean_project` resource itself, just to test our setup:

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
  version = "1.31.1-do.4"

  node_pool {
    name       = "worker-pool"
    size       = "s-2vcpu-2gb"
    node_count = 3
  }
}
```

This is a good time to point out the excellent "slugs" reference page DigitalOcean maintains. Adjust your region and Kubernetes version as desired! You could even feed them in from variables if you wanted to.

https://slugs.do-api.dev/

Run `terraform apply` and... poof! You have a functioning Kubernetes cluster in the cloud. Congratulations!

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
```

It's not usable yet, though, because we can't access it. Subsequent Kubernetes resources (through the provider) will need to know the cluster configuration to deploy to it. And I find it's very helpful to keep a snapshot of the `kubeconfig.yaml` so I can inspect, verify, and debug infrastructure from the command line. Let's do both.

## Come and Get Your Kubeconfig

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

Run another `terraform apply` and you'll be able to pipe the results to a file (which you should *DEFINITELY* add to your `.gitignore`) and identify with a `$KUBECONFIG` environmental variable.

On Windows:

```bat
terraform output -raw KUBECONFIG > kubeconfig.yaml
set KUBECONFIG="%CD%\kubeconfig.yaml"
```

On Unix:

```sh
terraform output -raw KUBECONFIG > kubeconfig.yaml
export KUBECONFIG="$PWD/kubeconfig.yaml"
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

We're set! We have a functioning cluster and we're ready to deploy Kubernetes resources. Let's start with a basic nginx container for demonstration purposes. Create a new folder/module, "wwwnamespace". We'll use individual Terraform modules specifically to organize specific Kubernetes namespaces from here on out, so add to this folder a `wwwnamespace.tf` file and populate accordingly:

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

Since we create a new module, and added a new provider, you'll need to run `terraform init` again. Once that's done, run `terraform apply` and you should see your Kubernetes namespace appear in no time when you run the appropiate `kubectl` query!

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

We want a basic nginx container. No problem! Add a `wwwdeployment.tf` to our "wwwnamespace" module and populate accordingly:

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

Notice we've used a new variable `APP_NAME` here. It's good practice to define "magic strings" (like names and selector labels) as Terraform variables because it helps ensure Kubernetes (which is stateless at this level) always has consistent "knowledge" and there are no chances of fat-fingering a bad reference. Services and other resources can use these variables, too. Let's define the `APP_NAME` value at the top level and "pass" it into the module. That means adding a `variables.tf` in our "wwwnamespace" folder/module:

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

## Next, the Service

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

## Lastly, the Ingress

A careful observer will note that we didn't define a Service "type". In our case, this defaulted to "ClusterIP", which means the service was assigned a specific address on the internal Kubernetes network. This does not, however, "expose" the service for access to external users.

And here's where things get fun. A traditional cluster will have at least three "meta" applications running at any given time:

* A load balancer, to define distribution of traffic from an external entry point into the cluster

* An ingress controller, for enforcing a set of ingress rules against the load balancer traffic-routing policies

* A cert manager, for automatically securing TLS termination on ingress

Load balancers are particularly sticky. If you are operating an on-prem cluster, for example, you will likely be using something like MetalLB (or some functional equivalent like Traefik, automatically provided in many cases by your Kubernetes "substrate" like microk8s). However, if you are operating on a provider, like AWS or DigitalOcean, the load balancer is unique to that platform and implemented by the provider.

We're going to define our ingress anyways, even though nothing exists yet to "enforce" (or secure) it. Create a `wwwingress.tf` file in our "wwwnamespace" folder/module and populate accordingly. If you're coming from a "traditional" or manual Kubernetes background, note how useful it is to procedurally bind to the service properties! Terraform really is wonderful.

```tf
resource "kubernetes_ingress_v1" "wwwingress" {
  metadata {
    name      = "wwwingress"
    namespace = kubernetes_namespace.wwwnamespace.metadata[0].name
  }

  spec {
    ingress_class_name = "nginx"

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

One thing I should point out here: We are assuming, if you have registered the domain name "mydomain.com", that you are organizing service ingresses under a subdomain using the "application" name we defined in `APP_NAME`. This means two things: First, that we can "dynamically" construct the `host` property of the ingress by combining the two, so long as we have also passed `HOST_NAME` into the Terraform context. Second, that we do indeed want such a "prefix" rule for our ingress paths. There are good reasons sometimes for doing otherwise, but this is a good approach for now. Modify the folder/module `variables.tf` accordingly:

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

An "ingress controller" is responsible for "enforcing" the ingress rules that you create using "Ingress" resources. Because it's not necessarily built into your cluster, there are many choices you can select from in the ingress controller universe. We'll look at using the NGINX-based ingress controller, and we'll deploy it to its own folder/module/namespace. Create an "icnamespace" folder/module and include it in your top-level `main.tf`:

```tf
module "doproject" {
  source = "./doproject"
}

module "icnamespace" {
  source = "./icnamespace"
}

module "wwwnamespace" {
  source    = "./wwwnamespace"
  APP_NAME  = "www"
  HOST_NAME = var.HOST_NAME
}
```

If you look at the official documentation, you'll see there are several ways to deploy the nginx ingress controller. We'll be using a Helm-based approach for two reasons:

1. It's self-contained and easy to configure & deploy

1. It will be very helpful to demonstrate how easy it is to include Helm releases in your cluster's stack.

1. Oh--it also has official support for integration with DigitalOcean load balanacers, so there's one less thing to worry about!

Take a gander at the official Helm chart listing:

https://artifacthub.io/packages/helm/ingress-nginx/ingress-nginx

Let's start by adding the "Helm" provider to our top-level `providers.tf`, citing the same configuration as our "Kubernetes" provider. With all three providers, it will look something like this:

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

    helm = {
      source = "hashicorp/helm"
      version = "2.12.1"
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

provider "helm" {
  kubernetes {
    host                   = module.doproject.CLUSTER_HOST
    token                  = module.doproject.CLUSTER_TOKEN
    cluster_ca_certificate = module.doproject.CLUSTER_CA
  }
}
```

Now let's add a Kuberenetes namespace resource to our "icnamespace" folder/module:

```tf
resource "kubernetes_namespace" "icnamespace" {
  metadata {
    name = "icnamespace"
  }
}
```

We're now ready to deploy our ingress controller. Create a corresponding Helm release resource and cite the appropriate variable bindings via Terraform (like namespace and release values); note we "set" a particular value in the Helm release to ensure the controller's ingress class will be the default used by the cluster:

```tf
resource "helm_release" "icrelease" {
  name       = "nginx-ingress"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = "4.9.1"
  namespace  = kubernetes_namespace.icnamespace.metadata[0].name

  set {
    name  = "controller.ingressClassResource.default"
    value = "true"
  }

  set {
    name  = "controller.publishService.enabled"
    value = "true"
  }
}
```

Now run a `terraform init` (remember we have a new provider) and a `terraform apply`. You now have a running ingress controller! Pretty slick, isn't it, to treat Helm releases as just another resource, and with values from procedural bindings? Look at the resulting resources deployed to this namespace to verify everything is running:

```sh
> kubectl get all -n icnamespace
NAME                                                         READY   STATUS    RESTARTS   AGE
pod/nginx-ingress-ingress-nginx-controller-55dcf9879-r2ztl   1/1     Running   0          2m50s

NAME                                                       TYPE           CLUSTER-IP       EXTERNAL-IP     PORT(S)                      AGE
service/nginx-ingress-ingress-nginx-controller             LoadBalancer   10.245.138.94    164.90.247.81   80:31874/TCP,443:30097/TCP   2m50s
service/nginx-ingress-ingress-nginx-controller-admission   ClusterIP      10.245.120.127   <none>          443/TCP                      2m50s

NAME                                                     READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/nginx-ingress-ingress-nginx-controller   1/1     1            1           2m50s

NAME                                                               DESIRED   CURRENT   READY   AGE
replicaset.apps/nginx-ingress-ingress-nginx-controller-55dcf9879   1         1         1       2m50s
```

And take another look at our ingress, whose "CLASS" colume should should now reflect enforcement by nginx:

```sh
> kubectl get Ingresses --all-namespaces
NAMESPACE      NAME         CLASS   HOSTS              ADDRESS   PORTS   AGE
wwwnamespace   wwwingress   nginx   www.mydomain.com             80      5m26s
```

## Automating Record Management

But we still can't browse to our endpoint; the domain name we registered isn't pointing to any specific address. We'll use DigitalOcean "domain" and "record" resources to apply this. And since the ingress controller's "LoadBalancer" service is the one with the external IP, we'll create them here within our "icnamespace" folder/module.

Before we can do that, we need to "extract" the service resource from the Helm release. Create a `data.tf` file in the "icnamespace" folder/module and include a citation for the LoadBalancer service that was created. Note how easy it is to back out the correct resource identity, even though we didn't deploy it directly!

```tf
data "kubernetes_service" "lbicservice" {
  metadata {
    name      = "${helm_release.icrelease.name}-${helm_release.icrelease.chart}-controller"
    namespace = kubernetes_namespace.icnamespace.metadata[0].name
  }
}
```

Now we can create a `dodomain.tf` file in the same folder/module with the following resource, citing that service's external IP:

```tf
resource "digitalocean_domain" "dodomain" {
  name       = var.HOST_NAME
  ip_address = data.kubernetes_service.lbicservice.status[0].load_balancer[0].ingress[0].ip
}
```

Note we'll need to pass the `HOST_NAME` variable in from the top level, too, so create a `variables.tf` in this folder/module:

```tf
variable "HOST_NAME" {
  type        = string
  description = "'Base' host name to which app names will be prepended to construct FQDNs"
}
```

And update the top-level `main.tf` accordingly:

```tf
module "doproject" {
  source = "./doproject"
}

module "icnamespace" {
  source    = "./icnamespace"
  HOST_NAME = var.HOST_NAME
}

module "wwwnamespace" {
  source    = "./wwwnamespace"
  APP_NAME  = "www"
  HOST_NAME = var.HOST_NAME
}
```

We'll also need to make sure the DigitalOcean provider is required by this "icnamespace" folder/module, so create a `providers.tf` and include the following:

```tf
terraform {
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "2.34.1"
    }
  }
}
```

This works for the top-level domain, but we also want to make sure subdomains will route here as well. So, we'll create a DigitalOcean record resource, `dorecord.tf`, also within the "icnamespace" folder/module, that just repeats the domain "A" record but for wildcard subdomains:

```tf
resource "digitalocean_record" "dorecord" {
  domain = digitalocean_domain.dodomain.id
  type   = "A"
  name   = "*"
  value  = digitalocean_domain.dodomain.ip_address
}
```

For the purposes of debugging (via `nslookup` or similar), it might be help to add an output reporting what public IP address was used. Create a `icnamespace/outputs.tf` file and populate accordingly:

```tf
output "PUBLIC_IP" {
  value = digitalocean_domain.dodomain.ip_address
}
```

Then, add this value to the top-level `outputs.tf` file so we can see it when we apply:

```tf
output "PUBLIC_IP" {
  value = module.icnamespace.PUBLIC_IP
}
```

Lastly, if we want, we can go back to our DigitalOcean "project" resource and make sure they are all organized under there as well, but strictly speaking this isn't necessary. You can now run `terraform init` and `terraform apply`. Then verify with a `curl` command:

```sh
> curl www.mydomain.com
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<style>
html { color-scheme: light dark; }
body { width: 35em; margin: 0 auto;
font-family: Tahoma, Verdana, Arial, sans-serif; }
</style>
</head>
<body>
<h1>Welcome to nginx!</h1>
<p>If you see this page, the nginx web server is successfully installed and
working. Further configuration is required.</p>

<p>For online documentation and support please refer to
<a href="http://nginx.org/">nginx.org</a>.<br/>
Commercial support is available at
<a href="http://nginx.com/">nginx.com</a>.</p>

<p><em>Thank you for using nginx.</em></p>
</body>
</html>
```

Pretty slick!

## Batton the Hatches

Our last exercise here is traditionally one of the hardest operations in systems administration. I am, of course, talking about certificate management.

Fortunately, we've made a judicious selection of technologies in our stack here. It turns out to be relatively straightforward!

We'll use a "cert-manager" Helm release, much like we did with our nginx-based ingress controller, and provide the appropriate bindings to enable DigitalOcean to handle the ACME challenges directly.

Since DigitalOcean is operating the nameservers our records are using, this greatly simplifies the process to the point where you may not even notice initial challenges and renewals.

Create a new folder/module for "certsnamespace" and include it in the top-level `main.tf`, which should have grown to look something like this by now:

```tf
module "doproject" {
  source = "./doproject"
}

module "icnamespace" {
  source    = "./icnamespace"
  HOST_NAME = var.HOST_NAME
}

module "certsnamespace" {
  source      = "./certsnamespace"
}

module "wwwnamespace" {
  source              = "./wwwnamespace"
  APP_NAME            = "www"
  HOST_NAME           = var.HOST_NAME
}
```

Initially, we'll just populate this with a single Kubernetes namespace before we start rolling out the Helm release. Create a `certsnamespace.tf` file and populate accordingly:

```tf
resource "kubernetes_namespace" "certsnamespace" {
  metadata {
    name = "certsnamespace"
  }
}
```

Now, create a `certmanagerrelease.tf` within this folder/module and populate accordingly. We'll want to make sure it installs the CRDs (custom resource definitions) that we'll cite in subsequent steps to define things like the Cluster Issuer--but other than that, the default Helm release settings work out-of-the-box:

```tf
resource "helm_release" "certmanagerrelease" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  version    = "v1.7.1"
  namespace  = kubernetes_namespace.certsnamespace.metadata[0].name

  set {
    name  = "installCRDs"
    value = "true"
  }
}
```

Run `terraform init` and `terraform apply` to get this module, and the release, up and running. Feel free to verify everything's spun up appropriately:

```sh
> kubectl get all -n certsnamespace
```

Next we'll want to apply the Cluster Issuer resource. But it will need some information to automate correctly. In particular, we'll need to provide the DigitalOcean API token (for it to modify DNS records on-the-fly for DNS01 challenges); an email address to use when requesting certificates for renewal notices; and a server address (e.g., staging vs. production) for the ACME API. Create a `certsnamespace/variables.tf` file and populate with the following:

```tf
variable "DO_TOKEN" {
  type        = string
  description = "API token used to write to the DigitalOcean infrastructure"
  sensitive   = true
}

variable "ACME_EMAIL" {
  type        = string
  description = "Email address used for ACME cert registration and renewal proces"
}

variable "ACME_SERVER" {
  type        = string
  description = "Address used to configure ClusterIssuer for ACME cert request verification"
}
```

Feel free to set these values from the environment, using `$TF_VAR_ACME_EMAIL` and `$TF_VAR_ACME_SERVER`, accordingly. While testing, you should use the "staging" ACME server for Let's Encrypt, "https://acme-staging-v02.api.letsencrypt.org/directory". Since we're using Terraform, it will be trivial to change this over once we're ready for production. Add `ACME_EMAIL` and `ACME_SERVER` to your top-level `variables.tf`.

```tf
variable "DO_TOKEN" {
  type        = string
  description = "API token for DigitalOcean provider; pass using environmental variable $TF_VAR_DO_TOKEN"
}

variable "HOST_NAME" {
  type        = string
  description = "'Base' host name to which app names will be prepended to construct FQDNs"
}

variable "ACME_EMAIL" {
  type        = string
  description = "Email address used for ACME cert registration and renewal proces"
}

variable "ACME_SERVER" {
  type        = string
  description = "Address used to configure ClusterIssuer for ACME cert request verification"
}
```

Now we can modify the top-level `main.tf` to pass these values to the correct module:

```tf
module "doproject" {
  source = "./doproject"
}

module "icnamespace" {
  source    = "./icnamespace"
  HOST_NAME = var.HOST_NAME
}

module "certsnamespace" {
  source      = "./certsnamespace"
  DO_TOKEN    = var.DO_TOKEN
  ACME_EMAIL  = var.ACME_EMAIL
  ACME_SERVER = var.ACME_SERVER
}

module "wwwnamespace" {
  source    = "./wwwnamespace"
  APP_NAME  = "www"
  HOST_NAME = var.HOST_NAME
}
```

Next, we'll need to securely pass the DigitalOcean token into the Kubernetes resources. Naturally, a Kubernetes secret is called for. Create a `dotoksecret.tf` within our "certsnamespace" folder/module and populate accordingly:

```tf
resource "kubernetes_secret" "dotoksecret" {
  metadata {
    name      = "dotoksecret"
    namespace = kubernetes_namespace.certsnamespace.metadata[0].name
  }

  data = {
    access-token = var.DO_TOKEN
  }
}
```

Now we're ready to define our cluster issuer. It's worth reading up on the ACME certificate request process in general:

https://cert-manager.io/docs/configuration/acme/

And for the DigitalOcean configuration for DNS01 challenges in particular:

https://cert-manager.io/docs/configuration/acme/dns01/digitalocean/

Now we're ready to create our cluster issuer. Since it's a cluster-wide resource, it doesn't technically belong in a namespace. For organization purposes, though, we'll keep it here alongside our other "certsnamespace" resources. Create a `clusterissuer.tf` file and populate like so:

```tf
resource "kubernetes_manifest" "clusterissuer" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"

    metadata = {
      name = "clusterissuer"
    }

    spec = {
      acme = {
        email  = var.ACME_EMAIL
        server = var.ACME_SERVER

        privateKeySecretRef = {
          name = "clusterissuer-secret"
        }

        solvers = [{
          dns01 = {
            digitalocean = {
              tokenSecretRef = {
                name = kubernetes_secret.dotoksecret.metadata[0].name
                key  = "access-token"
              }
            }
          }
        }]
      }
    }
  }
}
```

Lastly, we'll want to export the cluster issuer name from this module because that is how ingress resources will resolve where their cert requests should go. Add an `outputs.tf` file to this folder/module with the following:

```tf
output "CLUSTER_ISSUER_NAME" {
  value       = kubernetes_manifest.clusterissuer.manifest.metadata.name
  description = "Name used by ingress rules to identify where certificate requests within the cluster will be handled"
}
```

Now we're ready. Run `terraform apply` and... well, nothing will happen yet. But believe me, this is a big step.

For our last step, we need to go back to our ingress and instruct it to terminate TLS traffic accordingly. To do so, we'll need to make sure the cluster issuer name is passed forward to our "wwwnamespace" module, so update its `variables.tf` file:

```tf
variable "APP_NAME" {
  type        = string
  description = "Name used to construct selector labels and as a subdomain used in building FQDNs for ingress"
}

variable "HOST_NAME" {
  type        = string
  description = "Domain under which ingress FQDNs are constructed"
}

variable "CLUSTER_ISSUER_NAME" {
  type        = string
  description = "Name used by ingress rules to identify where certificate requests within the cluster will be handled"
}
```

Then we'll modify the top-level `main.tf` to make sure the value is passed through to this module:

```tf
module "doproject" {
  source = "./doproject"
}

module "icnamespace" {
  source    = "./icnamespace"
  HOST_NAME = var.HOST_NAME
}

module "certsnamespace" {
  source      = "./certsnamespace"
  DO_TOKEN    = var.DO_TOKEN
  ACME_EMAIL  = var.ACME_EMAIL
  ACME_SERVER = var.ACME_SERVER
}

module "wwwnamespace" {
  source              = "./wwwnamespace"
  APP_NAME            = "www"
  HOST_NAME           = var.HOST_NAME
  CLUSTER_ISSUER_NAME = module.certsnamespace.CLUSTER_ISSUER_NAME
}
```

Now we're ready to modify our ingress rule. This involves three specific changes:

1. We need to add an annotation, recognized by "cert-manager", to indicate the cluster name where certificate requests will be handled

1. We'll need to add a TLS block defining what address will be issued a certificate

1. That TLS block will also need to define the name of a secret resource (created automatically) where certificate information will be stored once issued

Put together, the "new and improved" ingress resource (`wwwnamespace/ingress.tf`, specifically) will look something like this:

```tf
resource "kubernetes_ingress_v1" "wwwingress" {
  metadata {
    name      = "wwwingress"
    namespace = kubernetes_namespace.wwwnamespace.metadata[0].name

    annotations = {
      "cert-manager.io/cluster-issuer" = var.CLUSTER_ISSUER_NAME
    }
  }

  spec {
    ingress_class_name = "nginx"

    tls {
      hosts       = ["${var.APP_NAME}.${var.HOST_NAME}"]
      secret_name = "${var.APP_NAME}-tls-secret"
    }

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

Now run a `terraform apply` and look for Certificate resources (created automatically). 

```sh
> kubectl get Certificates --all-namespaces
NAMESPACE      NAME             READY   SECRET           AGE
wwwnamespace   www-tls-secret   True    www-tls-secret   68s
```

It will take a few minutes, but eventually you should see a "READY=true" indicator. This indicates you can now `curl` the secure endpoint. Use a `-kv` flag because these are "staging" certificates that will explicitly be rejected by a browser or standard request, and because we want to inspect relevant certificate details in the exchange.

```sh
$ curl -kv https://www.mydomain.com
*   Trying 164.90.247.81:443...
* Connected to www.mydomain.com (164.90.247.81) port 443 (#0)
* ALPN, offering h2
* ALPN, offering http/1.1
* TLSv1.0 (OUT), TLS header, Certificate Status (22):
* TLSv1.3 (OUT), TLS handshake, Client hello (1):
* TLSv1.2 (IN), TLS header, Certificate Status (22):
* TLSv1.3 (IN), TLS handshake, Server hello (2):
* TLSv1.2 (IN), TLS header, Finished (20):
* TLSv1.2 (IN), TLS header, Supplemental data (23):
* TLSv1.3 (IN), TLS handshake, Encrypted Extensions (8):
* TLSv1.2 (IN), TLS header, Supplemental data (23):
* TLSv1.3 (IN), TLS handshake, Certificate (11):
* TLSv1.2 (IN), TLS header, Supplemental data (23):
* TLSv1.3 (IN), TLS handshake, CERT verify (15):
* TLSv1.2 (IN), TLS header, Supplemental data (23):
* TLSv1.3 (IN), TLS handshake, Finished (20):
* TLSv1.2 (OUT), TLS header, Finished (20):
* TLSv1.3 (OUT), TLS change cipher, Change cipher spec (1):
* TLSv1.2 (OUT), TLS header, Supplemental data (23):
* TLSv1.3 (OUT), TLS handshake, Finished (20):
* SSL connection using TLSv1.3 / TLS_AES_256_GCM_SHA384
* ALPN, server accepted to use h2
* Server certificate:
*  subject: CN=www.mydomain.com
*  start date: Feb 23 03:53:04 2024 GMT
*  expire date: May 23 03:53:03 2024 GMT
*  issuer: C=US; O=(STAGING) Let's Encrypt; CN=(STAGING) Artificial Apricot R3
*  SSL certificate verify result: unable to get local issuer certificate (20), continuing anyway.
* Using HTTP2, server supports multiplexing
* Connection state changed (HTTP/2 confirmed)
* Copying HTTP/2 data in stream buffer to connection buffer after upgrade: len=0
* TLSv1.2 (OUT), TLS header, Supplemental data (23):
* TLSv1.2 (OUT), TLS header, Supplemental data (23):
* TLSv1.2 (OUT), TLS header, Supplemental data (23):
* Using Stream ID: 1 (easy handle 0x55a222e46eb0)
* TLSv1.2 (OUT), TLS header, Supplemental data (23):
> GET / HTTP/2
> Host: www.mydomain.com
> user-agent: curl/7.81.0
> accept: */*
>
* TLSv1.2 (IN), TLS header, Supplemental data (23):
* TLSv1.3 (IN), TLS handshake, Newsession Ticket (4):
* TLSv1.2 (IN), TLS header, Supplemental data (23):
* TLSv1.3 (IN), TLS handshake, Newsession Ticket (4):
* old SSL session ID is stale, removing
* TLSv1.2 (IN), TLS header, Supplemental data (23):
* Connection state changed (MAX_CONCURRENT_STREAMS == 128)!
* TLSv1.2 (OUT), TLS header, Supplemental data (23):
* TLSv1.2 (IN), TLS header, Supplemental data (23):
< HTTP/2 200
< date: Fri, 23 Feb 2024 04:54:09 GMT
< content-type: text/html
< content-length: 615
< last-modified: Wed, 14 Feb 2024 16:03:00 GMT
< etag: "65cce434-267"
< accept-ranges: bytes
< strict-transport-security: max-age=31536000; includeSubDomains
<
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
<style>
html { color-scheme: light dark; }
body { width: 35em; margin: 0 auto;
font-family: Tahoma, Verdana, Arial, sans-serif; }
</style>
</head>
<body>
<h1>Welcome to nginx!</h1>
<p>If you see this page, the nginx web server is successfully installed and
working. Further configuration is required.</p>

<p>For online documentation and support please refer to
<a href="http://nginx.org/">nginx.org</a>.<br/>
Commercial support is available at
<a href="http://nginx.com/">nginx.com</a>.</p>

<p><em>Thank you for using nginx.</em></p>
</body>
</html>
* TLSv1.2 (IN), TLS header, Supplemental data (23):
* Connection #0 to host www.mydomain.com left intact
```

If all goes well, you're ready to switch to production! Change the value of your top-level `ACME_SERVER` variable (`$TF_VAR_ACME_SERVER` if you were using environmental variables to define it) to "https://acme-v02.api.letsencrypt.org/directory". Delete the old staging certificate and its secret to force a reissue, then apply the resources:

```sh
> kubectl delete Certificate/www-tls-secret -n wwwnamespace
> kubectl delete Secret/www-tls-secret -n wwwnamespace
> terraform apply
```

Production certificate requests may take longer to issue, so be patient and wait for the status of the "Certificate" resource to indicate "READY=True":

```sh
> kubectl get Certificates --all-namespaces
NAME             READY   SECRET           AGE
www-tls-secret   True    www-tls-secret   63s
```

Now you should be able to load HTTPS straight from your browser! How's that for a breath of fresh air?

## Conclusion

Okay, this was actually not a small lift. If you made it this far, congratulations!

But hopefully you've had enough experience with other approaches to realize how painless this was.

In particular, there's a lot of "one time" setup in our cluster here that we'll never need to repeat again.

Incremental applications will be able to reuse the same cert manager, project resources, and ingress controller.

Instead, each application will probably only have a small set of resources, configured with appropriate bindings to cluster-wide utilities:

* Databases using something like StatefulSets and backed by Persistent Volume Templates (though your underlying storage solution may vary)

* Containers using Kubernetes deployments

* Services for both exposed with Kubernetes service resources

* Ingresses to define external routes "into" public service endpoints

* Individual namespaces to wrap up each application within its own isolated concerns

In other words, we have a decently high-grade Kubernetes cluster here, and it's all automated with static IAC. Slick.

And of course, don't forget to `terraform destroy` once you're finished, lest you break your cloud provider budget (or free credits limit).
