# terraform/modules/aws/eks/variables.tf

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "k8s_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.27"
}

variable "vpc_id" {
  description = "VPC ID where EKS will be deployed"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs for EKS"
  type        = list(string)
}

variable "vpc_cidr" {
  description = "CIDR block of the VPC"
  type        = string
}

variable "public_access_cidrs" {
  description = "List of CIDR blocks that can access the EKS API server"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "node_groups" {
  description = "Map of node group configurations"
  type = map(object({
    capacity_type  = string
    instance_types = list(string)
    ami_type       = string
    desired_size   = number
    max_size       = number
    min_size       = number
    disk_size      = number
    gpu_enabled    = bool
    taints = list(object({
      key    = string
      value  = string
      effect = string
    }))
    labels = map(string)
  }))
  default = {
    main = {
      capacity_type  = "ON_DEMAND"
      instance_types = ["m5.large"]
      ami_type       = "AL2_x86_64"
      desired_size   = 2
      max_size       = 10
      min_size       = 1
      disk_size      = 50
      gpu_enabled    = false
      taints         = []
      labels         = {}
    }
  }
}

variable "cloudwatch_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 30
}

variable "key_name" {
  description = "SSH key pair name for EC2 instances"
  type        = string
  default     = null
}

variable "project_name" {
  description = "Project name for tagging"
  type        = string
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}