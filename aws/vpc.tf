data "aws_availability_zones" "available" {}

module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  # was pinned to 3.2.0 (2021-era), which predates and is not validated
  # against aws provider 6.x. Bumping alongside the provider upgrade since
  # v3 will very likely fail plan/apply against provider >= 6. This module
  # jumps 3 major versions (3 -> 6) - diff the plan carefully before
  # applying, per the module's upgrade guides on the registry.
  version = "~> 6.0"

  name                 = var.vpc_name
  cidr                 = "10.0.0.0/16"
  azs                  = data.aws_availability_zones.available.names
  private_subnets      = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets       = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/role/elb"                           = 1
    "kubernetes.io/cluster/${module.eks.cluster_name}" = "owned"
  }

}
