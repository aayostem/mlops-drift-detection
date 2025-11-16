# terraform/modules/aws/eks/main.tf

# EKS Cluster
resource "aws_eks_cluster" "ml_platform" {
  name     = "${var.cluster_name}-${var.environment}"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = var.k8s_version

  vpc_config {
    subnet_ids              = var.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = var.public_access_cidrs
    security_group_ids      = [aws_security_group.eks_cluster.id]
  }

  # Enable control plane logging
  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = aws_kms_key.eks.arn
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_vpc_resource_controller,
    aws_cloudwatch_log_group.eks_cluster
  ]

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-${var.environment}"
  })
}

# EKS Node Groups
resource "aws_eks_node_group" "main" {
  for_each = var.node_groups

  cluster_name    = aws_eks_cluster.ml_platform.name
  node_group_name = "${each.key}-${var.environment}"
  node_role_arn   = aws_iam_role.eks_node_group.arn
  subnet_ids      = var.private_subnet_ids

  capacity_type  = each.value.capacity_type
  instance_types = each.value.instance_types
  ami_type       = each.value.ami_type

  scaling_config {
    desired_size = each.value.desired_size
    max_size     = each.value.max_size
    min_size     = each.value.min_size
  }

  disk_size = each.value.disk_size

  # GPU-specific configuration
  dynamic "launch_template" {
    for_each = each.value.gpu_enabled ? [1] : []
    content {
      id      = aws_launch_template.gpu[each.key].id
      version = aws_launch_template.gpu[each.key].latest_version
    }
  }

  # Taints and labels for ML workloads
  dynamic "taint" {
    for_each = each.value.taints
    content {
      key    = taint.value.key
      value  = taint.value.value
      effect = taint.value.effect
    }
  }

  labels = merge(each.value.labels, {
    environment = var.environment
  })

  tags = merge(var.tags, {
    Name = "${each.key}-node-group-${var.environment}"
  })

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.ec2_container_registry_read_only,
  ]
}

# Launch template for GPU nodes
resource "aws_launch_template" "gpu" {
  for_each = { for k, v in var.node_groups : k => v if v.gpu_enabled }

  name_prefix   = "${each.key}-gpu-"
  image_id      = data.aws_ami.eks_gpu.id
  instance_type = each.value.instance_types[0]
  key_name      = var.key_name

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size = each.value.disk_size
      volume_type = "gp3"
      encrypted   = true
      kms_key_id  = aws_kms_key.eks.arn
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
  }

  tag_specifications {
    resource_type = "instance"

    tags = merge(var.tags, {
      Name = "${each.key}-gpu-instance-${var.environment}"
    })
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Security Group for EKS cluster
resource "aws_security_group" "eks_cluster" {
  name_prefix = "${var.cluster_name}-cluster-"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-cluster-sg-${var.environment}"
  })
}

# KMS Key for EKS encryption
resource "aws_kms_key" "eks" {
  description             = "KMS key for EKS cluster ${var.cluster_name}-${var.environment}"
  deletion_window_in_days = 10
  enable_key_rotation     = true

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-kms-${var.environment}"
  })
}

# CloudWatch Log Group for EKS
resource "aws_cloudwatch_log_group" "eks_cluster" {
  name              = "/aws/eks/${var.cluster_name}-${var.environment}/cluster"
  retention_in_days = var.cloudwatch_retention_days

  tags = merge(var.tags, {
    Name = "${var.cluster_name}-logs-${var.environment}"
  })
}

# Data source for EKS optimized AMI with GPU support
data "aws_ami" "eks_gpu" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amazon-eks-gpu-node-${var.k8s_version}-*"]
  }
}