variable "aws_region" {
  description = "AWS region for EKS cluster"
  type        = string
  default     = "us-west-2"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "skilpulse-eks"
}

variable "cluster_version" {
  description = "Kubernetes version for EKS"
  type        = string
  default     = "1.35"
}

variable "node_instance_type" {
  description = "EC2 instance type for EKS worker nodes"
  type        = string
  default     = "c7i-flex.large"
}

variable "node_desired_count" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 3
}

variable "node_max_count" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 5
}

variable "vpc_cidr" {
  description = "VPC cidr range"
  type        = string
  default     = "10.0.0.0/16"
}

variable "total_azs" {
  description = "Total availability zones to create"
  type        = number
  default     = 3
}

variable "public_subnets" {
  description = "Public subnets cidr"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

variable "private_subnets" {
  description = "Public subnets cidr"
  type        = list(string)
  default     = ["10.0.4.0/24", "10.0.5.0/24", "10.0.6.0/24"]
}

variable "intra_subnets" {
  description = "Public subnets cidr"
  type        = list(string)
  default     = ["10.0.7.0/24", "10.0.8.0/24", "10.0.9.0/24"]
}

variable "namespace" {
  default = "skillpulse"
}