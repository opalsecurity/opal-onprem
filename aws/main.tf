terraform {
  # >= 1.11 is required for ephemeral resources / write-only arguments
  # (used in rds.tf to keep the DB master password out of state & plan output).
  required_version = ">= 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      # was pinned to 4.67.0 (last 4.x release, ~2yrs old). Current major is 6.x.
      version = ">= 6.43, < 7.0"
    }
    random = {
      source = "hashicorp/random"
      # 3.7+ ships the `ephemeral "random_password"` resource used in rds.tf.
      version = ">= 3.7.0, < 4.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# NOTE: the `kubernetes` and `helm` providers previously configured here have
# been removed. They existed only to install the AWS Load Balancer Controller
# and EBS CSI/VPC CNI IRSA roles by hand. With EKS Auto Mode enabled (see
# eks.tf) those add-ons are managed natively by EKS, so nothing in this repo
# needs to talk to the Kubernetes API directly anymore.
#
# One deliberate exception: Auto Mode registers the EBS CSI driver
# (ebs.csi.eks.amazonaws.com) but does NOT create a default StorageClass
# pointing at it, so PVC-backed workloads (KOTS, Helm charts, etc.) will get
# stuck Pending until one exists. We tried managing that StorageClass here
# via the `kubernetes` provider, but this cluster's endpoint is private
# (endpoint_public_access = false), so the `kubernetes` provider's calls -
# unlike the `aws` provider's calls to public AWS APIs - must originate from
# inside the VPC. That makes `terraform apply` only runnable from the
# bastion (or a VPN'd-in host) the moment this provider is configured, even
# for applies that don't touch the StorageClass. Not worth that operational
# cost for one resource, so it's intentionally left out of Terraform.
#
# Instead, apply the default StorageClass manually, once, from the bastion
# right after `terraform apply` creates the cluster:
#
#   cat <<EOF | kubectl apply -f -
#   apiVersion: storage.k8s.io/v1
#   kind: StorageClass
#   metadata:
#     name: auto-ebs-sc
#     annotations:
#       storageclass.kubernetes.io/is-default-class: "true"
#   provisioner: ebs.csi.eks.amazonaws.com
#   volumeBindingMode: WaitForFirstConsumer
#   reclaimPolicy: Delete
#   parameters:
#     type: gp3
#   EOF
#
# If you add other Kubernetes/Helm-managed resources back to this repo (and
# accept the VPC-only-apply tradeoff), re-add the providers, e.g.:
#
# data "aws_eks_cluster_auth" "cluster" {
#   name = module.eks.cluster_name
# }
#
# provider "kubernetes" {
#   host                   = module.eks.cluster_endpoint
#   cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
#   token                  = data.aws_eks_cluster_auth.cluster.token
# }