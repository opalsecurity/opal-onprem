data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_id
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_id
}

# irsa - vpc cni
module "vpc_cni_irsa_role" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  role_name = "${module.eks.cluster_name}-vpc-cni"

  attach_vpc_cni_policy = true
  vpc_cni_enable_ipv4   = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-node"]
    }
  }
}

# irsa - csi ebs storage
module "ebs_csi_irsa_role" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  role_name             = "${module.eks.cluster_name}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

# irsa - alb controller
module "alb_controller_irsa_role" {
  source = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"

  role_name                              = "${module.eks.cluster_name}-alb-controller"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "18.31.0"
  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  #networking
  subnet_ids = module.vpc.private_subnets
  vpc_id     = module.vpc.vpc_id

  //enable logs and OIDC
  cluster_enabled_log_types = ["audit", "api", "authenticator"]
  enable_irsa               = true

  # install the add-ons
  cluster_addons = {
    kube-proxy = {
      resolve_conflicts = "OVERWRITE"
    }
    coredns = {
      resolve_conflicts = "OVERWRITE"
    }
    vpc-cni = {
      resolve_conflicts        = "OVERWRITE"
      service_account_role_arn = module.vpc_cni_irsa_role.iam_role_arn
    }
    aws-ebs-csi-driver = {
      resolve_conflicts        = "OVERWRITE"
      service_account_role_arn = module.ebs_csi_irsa_role.iam_role_arn
    }
  }

  # make worker nodes work with SSM
  eks_managed_node_group_defaults = {
    instance_types = [var.cluster_node_instance_type]
    iam_role_additional_policies = [
      "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
      "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
    ]
    # We are using the IRSA created above for CNI permissions
    # However, we have to provision a new cluster with the policy attached FIRST
    # before we can disable. Without this initial policy,
    # the VPC CNI fails to assign IPs and nodes cannot join the new cluster
    # see https://github.com/aws/containers-roadmap/issues/1666 for more context
    iam_role_attach_cni_policy = true
  }

  #allow node to node communication and rds access
  node_security_group_additional_rules = {
    ingress_allow_access_from_nodes = {
      description = "Node to node access"
      type        = "ingress"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      self        = true
    }
    egress_allow_access_to_nodes = {
      description = "Node to node access"
      type        = "egress"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      self        = true
    }
    ingress_allow_access_from_control_plane = {
      description                   = "Cluster to node access"
      protocol                      = "-1"
      from_port                     = 0
      to_port                       = 0
      type                          = "ingress"
      source_cluster_security_group = true
    }
    egress_allow_access_to_rds = {
      description = "Node to RDS access"
      type        = "egress"
      protocol    = "tcp"
      from_port   = 5432
      to_port     = 5432
      cidr_blocks = module.vpc.private_subnets_cidr_blocks
    }
  }

  # default to three worker nodes across AZs - two nodes is okay based on t-shirt sizing.
  eks_managed_node_groups = {
    worker = {
      name         = "opal-worker"
      max_size     = 3
      desired_size = 3
    }
    # To deploy this change, a blue-green deployment is necessary.
    # First, add the new `worker-green` node group, with a tf plan + apply.
    # After confirming success, remove the previous `worker` node group,
    # with a tf plan + apply.
    worker-green = {
      name         = "opal-worker-greenn"
      max_size     = 3
      desired_size = 2
      subnet_ids = concat([
        for subnet_id in module.vpc.private_subnets : subnet_id if subnet_id != "<private_subnet_id_to_exclude>"
      ], [
        for subnet_id in module.vpc.public_subnets : subnet_id if subnet_id != "<public_subnet_id_to_exclude>"
      ])
    }
  }

  # show example auth config map
  manage_aws_auth_configmap = true
  aws_auth_roles = [
    {
      rolearn  = aws_iam_role.eks_cluster_admin.arn
      username = aws_iam_role.eks_cluster_admin.name
      groups   = ["system:masters"]
    }
  ]
}

#alb controller
resource "helm_release" "alb_controller" {
  name = "aws-load-balancer-controller"

  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"

  namespace = "kube-system"

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }
  set {
    name  = "serviceAccount.create"
    value = true
  }
  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller "
  }
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.alb_controller_irsa_role.iam_role_arn
  }
}
