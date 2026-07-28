module "eks" {
  source = "terraform-aws-modules/eks/aws"
  # was pinned to 18.31.0 (Nov 2022, missing even the 18.31.2 patch from
  # 2 days later). Current major is 21.x. v21 also drops aws-auth configmap
  # management in favor of EKS access entries (see access_entries below),
  # and dropped the `cluster_` prefix from most input variable names to
  # better match the underlying API - verify against the registry for the
  # latest 21.x patch before applying.
  version            = "~> 21.0"
  name               = var.cluster_name
  kubernetes_version = var.cluster_version

  #networking
  subnet_ids              = module.vpc.private_subnets
  vpc_id                  = module.vpc.vpc_id
  endpoint_public_access  = false
  endpoint_private_access = true

  //enable logs and OIDC
  enabled_log_types = ["audit", "api", "authenticator"]
  enable_irsa       = true

  # EKS Auto Mode: AWS manages compute (nodes), storage (replaces the EBS CSI
  # driver), and load balancing (replaces the AWS Load Balancer Controller)
  # for us. This removes the need for the vpc-cni / aws-ebs-csi-driver
  # add-ons, the CNI/CSI/ALB-controller IRSA roles, the ALB controller Helm
  # release, and the eks_managed_node_group* configuration that used to live
  # in this file.
  compute_config = {
    enabled    = true
    node_pools = ["general-purpose"]
  }

  # coredns still runs as a regular add-on under Auto Mode.
  addons = {
    coredns = {}
  }

  # Auth: use EKS access entries instead of the (now removed) aws-auth
  # configmap management. Grants the same cluster-admin access the
  # aws_auth_roles block used to grant via "system:masters".
  authentication_mode = "API"

  access_entries = {
    admin = {
      principal_arn = aws_iam_role.eks_cluster_admin.arn

      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }
}

# Allow Aurora/RDS access from the nodes EKS Auto Mode provisions.
#
# Uses module.eks.cluster_primary_security_group_id - NOT
# node_security_group_id and NOT cluster_security_group_id, both of which
# look right but aren't:
#   - node_security_group_id: under Auto Mode there's no separate per-node-
#     group security group the way traditional eks_managed_node_groups work,
#     so this points at a security group nothing actually uses.
#   - cluster_security_group_id: this is an *additional* security group the
#     module itself creates and attaches to the cluster - a different
#     resource from the one AWS's EKS service auto-creates for the cluster.
#
# cluster_primary_security_group_id is the module's output for that
# AWS-auto-created security group - the one Auto Mode nodes actually use for
# control-plane-to-data-plane communication, and the one shown as "Cluster
# security group" in the EKS console / clusterSecurityGroupId via the API.
resource "aws_security_group_rule" "nodes_to_rds" {
  description              = "Node to RDS access"
  type                     = "egress"
  protocol                 = "tcp"
  from_port                = 5432
  to_port                  = 5432
  security_group_id        = module.eks.cluster_primary_security_group_id
  source_security_group_id = aws_security_group.rds.id
}