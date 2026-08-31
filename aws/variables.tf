variable "region" {
  description = "AWS region"
}

variable "name_prefix" {
  default     = "opal"
  description = "Name prefix applied to all resources created by this"
}

variable "cluster_version" {
  default     = "1.36"
  description = "EKS cluster version"
}

variable "cluster_node_instance_type" {
  default     = "m6i.xlarge"
  description = "EKS cluster node instance type"
}

variable "db_instance_class" {
  default     = "db.m6i.large"
  description = "DB instance class"
}
