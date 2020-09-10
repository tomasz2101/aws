terraform {
  required_version = ">= 0.12.0"
}

provider "aws" {
  version = ">= 2.28.1"
  region  = var.region
}

data "aws_availability_zones" "available" {
}

module "aws_vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "2.6.0"

  name = "${var.cluster_name}-vpc"
  cidr = "10.0.0.0/16"
  azs = data.aws_availability_zones.available.names
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = "1"
  }
}

module "eks" {
  source           = "terraform-aws-modules/eks/aws"
  cluster_name     = var.cluster_name
  subnets          = module.aws_vpc.private_subnets
  cluster_version  = var.k8s_version
  write_kubeconfig = false
  vpc_id           = module.aws_vpc.vpc_id

  worker_groups = [
    {
      name                          = "worker-group-1"
      instance_type                 = var.worker_node_type
      additional_userdata           = "echo foo bar"
      asg_desired_capacity          = var.worker_node_count
    }
  ]

  map_roles                            = []
  map_users                            = []
  map_accounts                         = []
}

data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
  token                  = data.aws_eks_cluster_auth.cluster.token
  load_config_file       = false
  version                = "~> 1.9"
}



resource "helm_release" "rocketchat" {
  name             = "chat"
  create_namespace = true
  namespace        = "default"
  chart            = "rocketchat"
  repository       = "https://kubernetes-charts.storage.googleapis.com"
  version          = "2.0.2"

  values = [file("${path.module}/rocketchat-values.yaml")]

  set {
    type  = "string"
    name  = "host"
    value = "chat.${var.dns_domain}"
  }
  set {
    type  = "string"
    name  = "ingress.tls[0].hosts[0]"
    value = "chat.${var.dns_domain}"
  }
}


provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)
    token                  = data.aws_eks_cluster_auth.cluster.token
    load_config_file       = false
  }
}
