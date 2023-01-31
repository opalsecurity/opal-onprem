variable "region" {
  default     = "us-east-2"
  description = "AWS region"
}

variable "vpc_name" {
  default     = "opal-vpc"
  description = "VPC name"
}

variable "cluster_name" {
  default     = "opal-cluster"
  description = "Cluster name"
}

variable "db_identifier" {
  default     = "opal"
  description = "DB identifier"
}

variable "cluster_node_instance_type" {
  default     = "m5.large"
  description = "Cluster node instance type"
}

variable "db_instance_class" {
  default     = "db.m5.large"
  description = "DB instance class"
}
