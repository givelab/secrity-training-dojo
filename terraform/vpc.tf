# ⚠️ 【学習用】意図的に脆弱なVPC/ネットワーク設定
# このファイルには複数のセキュリティ問題があります。

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "security-dojo-vpc"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  # ⚠️ 課題3-C: パブリックサブネットにEC2を配置しパブリックIPを自動付与
  map_public_ip_on_launch = true

  tags = {
    Name = "security-dojo-public-subnet"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# ⚠️ 課題3-D: Security Groupが全ポートのインバウンドを0.0.0.0/0から許可している
resource "aws_security_group" "eks_node_sg" {
  name        = "eks-node-sg"
  description = "EKS Node Security Group"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "全トラフィックを許可（脆弱）"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]   # ❌ 全IPからの全ポートを許可
  }

  egress {
    description = "全アウトバウンドを許可（脆弱）"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]   # ❌ マイニングプールなど任意の外部へ通信可能
  }
}

# ⚠️ 課題3-E: EKS NodeのEC2インスタンスでIMDSv1が有効（SSRFに脆弱）
resource "aws_launch_template" "eks_node" {
  name_prefix   = "eks-node-"
  image_id      = "ami-0abcdef1234567890"
  instance_type = "t3.medium"

  iam_instance_profile {
    name = aws_iam_instance_profile.eks_node_profile.name
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.eks_node_sg.id]
  }

  # ⚠️ 問題: metadata_optionsが設定されていないため、IMDSv1がデフォルトで有効
  # IMDSv1はSSRF攻撃でクレデンシャルを窃取される脆弱性がある
  # 修正方法: metadata_options { http_tokens = "required" } を追加する

  tags = {
    Name = "eks-node"
  }
}
