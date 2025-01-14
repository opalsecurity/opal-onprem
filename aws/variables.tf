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
  default     = "1.29"
  description = "EKS cluster version"
}

variable "cluster_node_instance_type" {
  default     = "m6i.xlarge"
  description = "EKS cluster node instance type"
}

variable "db_identifier" {
  default     = "opal"
  description = "DB identifier"
}

variable "db_instance_class" {
  default     = "db.m6i.large"
  description = "DB instance class"
}
