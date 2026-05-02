# ✅ 解答例: セキュアなVPC / Security Group / IMDSv2強制

resource "aws_vpc" "main_fixed" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "security-dojo-vpc-fixed"
  }
}

# ✅ 修正3-C: プライベートサブネットにNodeを配置
resource "aws_subnet" "private" {
  vpc_id                  = aws_vpc.main_fixed.id
  cidr_block              = "10.0.10.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = false  # ✅ パブリックIPを付与しない

  tags = {
    Name = "security-dojo-private-subnet"
  }
}

# ✅ NATゲートウェイ経由でのみアウトバウンド許可
resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_fixed.id
}

resource "aws_subnet" "public_fixed" {
  vpc_id            = aws_vpc.main_fixed.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "${var.aws_region}a"

  tags = {
    Name = "security-dojo-public-subnet-fixed"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main_fixed.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id  # ✅ NATゲートウェイ経由
  }
}

# ✅ 修正3-D: Security Groupを最小権限に絞る
resource "aws_security_group" "eks_node_sg_fixed" {
  name        = "eks-node-sg-fixed"
  description = "EKS Node Security Group（最小権限）"
  vpc_id      = aws_vpc.main_fixed.id

  # ✅ インバウンドはVPC内からのみ許可
  ingress {
    description = "VPC内からのみ許可"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  # ✅ アウトバウンドはHTTPS（443）のみ許可（AWS API通信用）
  egress {
    description = "HTTPS（AWS API）のみ許可"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ✅ 修正3-E: IMDSv2を強制し、SSRFによるクレデンシャル窃取を防止
resource "aws_launch_template" "eks_node_fixed" {
  name_prefix   = "eks-node-fixed-"
  image_id      = "ami-0abcdef1234567890"
  instance_type = "t3.medium"

  iam_instance_profile {
    name = aws_iam_instance_profile.eks_node_profile_fixed.name
  }

  network_interfaces {
    associate_public_ip_address = false  # ✅ パブリックIPを付与しない
    security_groups             = [aws_security_group.eks_node_sg_fixed.id]
  }

  # ✅ IMDSv2を強制：hop_limitを1にすることでコンテナからのIMDSアクセスを防止
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"   # ✅ IMDSv2強制
    http_put_response_hop_limit = 1            # ✅ コンテナからのアクセスを防止
    instance_metadata_tags      = "disabled"
  }
}

resource "aws_iam_instance_profile" "eks_node_profile_fixed" {
  name = "eks-node-profile-fixed"
  role = aws_iam_role.eks_node_role_fixed.name
}
