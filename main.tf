provider "aws" {
  region = "ap-south-2"
}

# -------------------------
# VPC
# -------------------------
resource "aws_vpc" "prakash_vpc" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "prakash-vpc"
  }
}

# -------------------------
# Subnets
# -------------------------
resource "aws_subnet" "prakash_subnet" {
  count = 2

  vpc_id                  = aws_vpc.prakash_vpc.id
  cidr_block              = cidrsubnet(aws_vpc.prakash_vpc.cidr_block, 8, count.index)
  availability_zone       = element(["ap-south-2a", "ap-south-2b"], count.index)
  map_public_ip_on_launch = true

  tags = {
    Name = "prakash-subnet-${count.index}"
  }
}

# -------------------------
# Internet Gateway
# -------------------------
resource "aws_internet_gateway" "prakash_igw" {
  vpc_id = aws_vpc.prakash_vpc.id

  tags = {
    Name = "prakash-igw"
  }
}

# -------------------------
# Route Table
# -------------------------
resource "aws_route_table" "prakash_route_table" {
  vpc_id = aws_vpc.prakash_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.prakash_igw.id
  }

  tags = {
    Name = "prakash-route-table"
  }
}

# -------------------------
# Route Table Association
# -------------------------
resource "aws_route_table_association" "a" {
  count = 2

  subnet_id      = aws_subnet.prakash_subnet[count.index].id
  route_table_id = aws_route_table.prakash_route_table.id
}

# -------------------------
# EKS Cluster Security Group
# -------------------------
resource "aws_security_group" "prakash_cluster_sg" {
  name   = "prakash-cluster-sg"
  vpc_id = aws_vpc.prakash_vpc.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "prakash-cluster-sg"
  }
}

# -------------------------
# EKS Node Security Group
# -------------------------
resource "aws_security_group" "prakash_node_sg" {
  name   = "prakash-node-sg"
  vpc_id = aws_vpc.prakash_vpc.id

  # Learning/lab configuration
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "prakash-node-sg"
  }
}

# -------------------------
# EKS Cluster IAM Role
# -------------------------
resource "aws_iam_role" "prakash_cluster_role" {
  name = "prakash-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "eks.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })
}

# EKS Cluster Policy
resource "aws_iam_role_policy_attachment" "prakash_cluster_role_policy" {
  role       = aws_iam_role.prakash_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# -------------------------
# EKS Node IAM Role
# -------------------------
resource "aws_iam_role" "prakash_node_group_role" {
  name = "prakash-node-group-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "ec2.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })
}

# Worker Node Policy
resource "aws_iam_role_policy_attachment" "prakash_node_group_role_policy" {
  role       = aws_iam_role.prakash_node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

# CNI Policy
resource "aws_iam_role_policy_attachment" "prakash_node_group_cni_policy" {
  role       = aws_iam_role.prakash_node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# ECR Read Only
resource "aws_iam_role_policy_attachment" "prakash_node_group_registry_policy" {
  role       = aws_iam_role.prakash_node_group_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# -------------------------
# EKS Cluster
# -------------------------
resource "aws_eks_cluster" "prakash" {
  name     = "prakash-cluster"
  role_arn = aws_iam_role.prakash_cluster_role.arn

  vpc_config {
    subnet_ids = aws_subnet.prakash_subnet[*].id

    security_group_ids = [
      aws_security_group.prakash_cluster_sg.id
    ]
  }

  depends_on = [
    aws_iam_role_policy_attachment.prakash_cluster_role_policy
  ]
}

# -------------------------
# EKS Node Group
# -------------------------
resource "aws_eks_node_group" "prakash" {
  cluster_name = aws_eks_cluster.prakash.name

  node_group_name = "prakash-node-group"

  node_role_arn = aws_iam_role.prakash_node_group_role.arn

  subnet_ids = aws_subnet.prakash_subnet[*].id

  scaling_config {
    desired_size = 3
    min_size     = 3
    max_size     = 3
  }

  instance_types = ["t3.medium"]

  remote_access {
    ec2_ssh_key = var.ssh_key_name

    source_security_group_ids = [
      aws_security_group.prakash_node_sg.id
    ]
  }

  depends_on = [
    aws_iam_role_policy_attachment.prakash_node_group_role_policy,
    aws_iam_role_policy_attachment.prakash_node_group_cni_policy,
    aws_iam_role_policy_attachment.prakash_node_group_registry_policy
  ]
}
