variable "region" {
  description = "AWS region"
}

variable "vpc_name" {
  default     = "opal-vpc"
  description = "VPC name"
}

variable "cluster_name" {
  default     = "opal-cluster"
  description = "EKS cluster name"
}

variable "cluster_version" {
  default = "1.35"
  description = <<-EOT
    EKS cluster version. 1.32 is out of standard support (ended Mar 2026).
    EKS only guarantees ~4 versions of support at a time, so check
    https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html
    for the current recommended version before deploying.
  EOT
}

# Unused now that cluster_compute_config (EKS Auto Mode) manages node
# provisioning - see eks.tf. Left here in case you disable Auto Mode and
# go back to eks_managed_node_groups.
variable "cluster_node_instance_type" {
  default     = "m6i.xlarge"
  description = "EKS cluster node instance type (only used if EKS Auto Mode is disabled)"
}

variable "db_identifier" {
  default     = "opal"
  description = "DB identifier"
}

variable "db_engine_version" {
  default     = "17.9"
  description = "Aurora PostgreSQL engine version. Was RDS Postgres 15.10, which hits end of standard support in May 2026."
}

variable "db_instance_class" {
  # Aurora doesn't support the db.m* family used previously - r6g is the
  # standard general-purpose choice for Aurora PostgreSQL.
  default     = "db.r6g.large"
  description = "Aurora DB instance class (applies to both writer and reader instances)"
}

variable "db_reader_count" {
  default     = 1
  description = "Number of Aurora reader instances to run alongside the writer, for failover"
}
