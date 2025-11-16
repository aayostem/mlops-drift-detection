# terraform/modules/aws/vpc/main.tf

# VPC for MLOps platform
resource "aws_vpc" "ml_platform" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, {
    Name = "${var.project_name}-vpc-${var.environment}"
  })
}

# Public Subnets for load balancers and NAT gateways
resource "aws_subnet" "public" {
  count                   = length(var.public_subnet_cidrs)
  vpc_id                  = aws_vpc.ml_platform.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.tags, {
    Name = "${var.project_name}-public-${count.index + 1}-${var.environment}"
    "kubernetes.io/role/elb" = "1"
  })
}

# Private Subnets for EKS worker nodes and databases
resource "aws_subnet" "private" {
  count             = length(var.private_subnet_cidrs)
  vpc_id            = aws_vpc.ml_platform.id
  cidr_block        = var.private_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(var.tags, {
    Name = "${var.project_name}-private-${count.index + 1}-${var.environment}"
    "kubernetes.io/role/internal-elb" = "1"
  })
}

# Database Subnets for RDS instances
resource "aws_subnet" "database" {
  count             = length(var.database_subnet_cidrs)
  vpc_id            = aws_vpc.ml_platform.id
  cidr_block        = var.database_subnet_cidrs[count.index]
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = merge(var.tags, {
    Name = "${var.project_name}-database-${count.index + 1}-${var.environment}"
  })
}

# Internet Gateway for public subnets
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.ml_platform.id

  tags = merge(var.tags, {
    Name = "${var.project_name}-igw-${var.environment}"
  })
}

# NAT Gateways for private subnets
resource "aws_eip" "nat" {
  count = length(var.public_subnet_cidrs)
  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${var.project_name}-nat-eip-${count.index + 1}-${var.environment}"
  })
}

resource "aws_nat_gateway" "main" {
  count         = length(var.public_subnet_cidrs)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(var.tags, {
    Name = "${var.project_name}-nat-${count.index + 1}-${var.environment}"
  })

  depends_on = [aws_internet_gateway.main]
}

# Route Tables
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.ml_platform.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-public-rt-${var.environment}"
  })
}

resource "aws_route_table" "private" {
  count  = length(var.private_subnet_cidrs)
  vpc_id = aws_vpc.ml_platform.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-private-rt-${count.index + 1}-${var.environment}"
  })
}

resource "aws_route_table" "database" {
  vpc_id = aws_vpc.ml_platform.id

  tags = merge(var.tags, {
    Name = "${var.project_name}-database-rt-${var.environment}"
  })
}

# Route Table Associations
resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

resource "aws_route_table_association" "database" {
  count          = length(aws_subnet.database)
  subnet_id      = aws_subnet.database[count.index].id
  route_table_id = aws_route_table.database.id
}

# VPC Endpoints for private EKS cluster access
resource "aws_vpc_endpoint" "s3" {
  vpc_id       = aws_vpc.ml_platform.id
  service_name = "com.amazonaws.${var.region}.s3"

  tags = merge(var.tags, {
    Name = "${var.project_name}-s3-endpoint-${var.environment}"
  })
}

resource "aws_vpc_endpoint" "ecr_api" {
  vpc_id            = aws_vpc.ml_platform.id
  service_name      = "com.amazonaws.${var.region}.ecr.api"
  vpc_endpoint_type = "Interface"

  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  subnet_ids          = aws_subnet.private[*].id
  private_dns_enabled = true

  tags = merge(var.tags, {
    Name = "${var.project_name}-ecr-api-endpoint-${var.environment}"
  })
}

resource "aws_vpc_endpoint" "ecr_dkr" {
  vpc_id            = aws_vpc.ml_platform.id
  service_name      = "com.amazonaws.${var.region}.ecr.dkr"
  vpc_endpoint_type = "Interface"

  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  subnet_ids          = aws_subnet.private[*].id
  private_dns_enabled = true

  tags = merge(var.tags, {
    Name = "${var.project_name}-ecr-dkr-endpoint-${var.environment}"
  })
}

# Security Groups
resource "aws_security_group" "vpc_endpoints" {
  name_prefix = "${var.project_name}-endpoints-"
  vpc_id      = aws_vpc.ml_platform.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  tags = merge(var.tags, {
    Name = "${var.project_name}-endpoints-sg-${var.environment}"
  })
}

# Data source for availability zones
data "aws_availability_zones" "available" {
  state = "available"
}