resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_node_role.arn
  version  = "1.29"

  vpc_config {
    subnet_ids         = [aws_subnet.public.id]
    security_group_ids = [aws_security_group.eks_node_sg.id]
    # ⚠️ パブリックエンドポイントが全IPに公開されている
    endpoint_public_access  = true
    public_access_cidrs     = ["0.0.0.0/0"]  # ❌ 全IPからKubernetes APIにアクセス可能
    endpoint_private_access = false
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_admin,
  ]
}

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "main-node-group"
  node_role_arn   = aws_iam_role.eks_node_role.arn
  subnet_ids      = [aws_subnet.public.id]

  launch_template {
    id      = aws_launch_template.eks_node.id
    version = "$Latest"
  }

  scaling_config {
    desired_size = 2
    min_size     = 1
    max_size     = 5
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_node_admin,
  ]
}
