# ⚠️ 【学習用】意図的に脆弱なIAM設定
# このファイルには複数のセキュリティ問題があります。
# 課題3を解決するために何を修正すべきか調査してください。

# EKS Nodeグループ用のIAMロール
resource "aws_iam_role" "eks_node_role" {
  name = "eks-node-role"

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

# ⚠️ 課題3-A: 管理者権限（AdministratorAccess）をNodeに付与している
# Nodeが侵害された場合、攻撃者がAWS全リソースを操作できる
resource "aws_iam_role_policy_attachment" "eks_node_admin" {
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
  role       = aws_iam_role.eks_node_role.name
}

# ⚠️ 課題3-B: カスタムポリシーでも Action: "*", Resource: "*" という最悪のパターン
resource "aws_iam_policy" "app_policy" {
  name        = "app-overpermissive-policy"
  description = "アプリケーション用ポリシー（過剰権限）"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "*"       # ❌ 全アクションを許可
        Resource = "*"       # ❌ 全リソースに対して
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "app_policy_attach" {
  policy_arn = aws_iam_policy.app_policy.arn
  role       = aws_iam_role.eks_node_role.name
}

# EC2インスタンスプロファイル（NodeGroup用）
resource "aws_iam_instance_profile" "eks_node_profile" {
  name = "eks-node-profile"
  role = aws_iam_role.eks_node_role.name
}
