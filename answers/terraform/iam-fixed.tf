# ✅ 解答例: 最小権限IAMとIRSA（IAM Roles for Service Accounts）

# EKS Node用IAMロール（最小権限）
resource "aws_iam_role" "eks_node_role_fixed" {
  name = "eks-node-role-fixed"

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

# ✅ 修正3-A: AdministratorAccessを削除し、EKS Nodeに必要な最小権限のみ付与
resource "aws_iam_role_policy_attachment" "eks_node_worker" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_role_fixed.name
}

resource "aws_iam_role_policy_attachment" "eks_node_cni" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_role_fixed.name
}

resource "aws_iam_role_policy_attachment" "eks_node_ecr" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_role_fixed.name
}

# ✅ 修正3-B: IRSA用IAMロール（Podレベルで必要なAWS権限を分離）
# このロールはbackend ServiceAccountにのみ引き受け可能
data "aws_eks_cluster" "main" {
  name = var.cluster_name
}

resource "aws_iam_role" "backend_irsa_role" {
  name = "backend-irsa-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(data.aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")}"
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(data.aws_eks_cluster.main.identity[0].oidc[0].issuer, "https://", "")}:sub" : "system:serviceaccount:dojo:backend-sa"
          }
        }
      }
    ]
  })
}

data "aws_caller_identity" "current" {}

# ✅ backendアプリが必要なリソースのみアクセス可能な最小権限ポリシー
resource "aws_iam_policy" "backend_minimal_policy" {
  name        = "backend-minimal-policy"
  description = "backendアプリが必要とする最小権限"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = [
          "arn:aws:secretsmanager:ap-northeast-1:*:secret:dojo/backend/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "backend_irsa_attach" {
  policy_arn = aws_iam_policy.backend_minimal_policy.arn
  role       = aws_iam_role.backend_irsa_role.name
}
