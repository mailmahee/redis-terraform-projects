#==============================================================================
# EKS CLUSTER IAM ROLE
#==============================================================================

resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "eks.amazonaws.com"
      }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.cluster.name
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEKSVPCResourceController" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.cluster.name
}

#==============================================================================
# EKS CLUSTER SECURITY GROUP
#==============================================================================

resource "aws_security_group" "cluster" {
  name        = "${var.cluster_name}-cluster-sg"
  description = "Security group for EKS cluster control plane"
  vpc_id      = var.vpc_id

  tags = merge(
    var.tags,
    {
      Name = "${var.cluster_name}-cluster-sg"
    }
  )
}

# Allow all outbound traffic from cluster
resource "aws_security_group_rule" "cluster_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.cluster.id
  description       = "Allow all outbound traffic"
}

# Allow HTTPS from anywhere (for kubectl access)
resource "aws_security_group_rule" "cluster_ingress_https" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.cluster.id
  description       = "Allow HTTPS access to cluster API"
}

#==============================================================================
# EKS CLUSTER
#==============================================================================

resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids              = concat(var.public_subnet_ids, var.private_subnet_ids)
    endpoint_private_access = var.cluster_endpoint_private_access
    endpoint_public_access  = var.cluster_endpoint_public_access
    security_group_ids      = [aws_security_group.cluster.id]
  }

  enabled_cluster_log_types = var.cluster_enabled_log_types

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.cluster_AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.cluster_AmazonEKSVPCResourceController,
  ]
}

#==============================================================================
# EKS CLUSTER ADDONS
#==============================================================================

# VPC CNI addon
resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "vpc-cni"

  tags = var.tags

  depends_on = [aws_eks_cluster.main]
}

# CoreDNS addon - using null_resource to avoid health check timeouts
# Will be installed but may be DEGRADED until nodes are created
resource "null_resource" "coredns_addon" {
  triggers = {
    cluster_name = aws_eks_cluster.main.name
    aws_region   = var.aws_region
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws eks create-addon \
        --cluster-name ${aws_eks_cluster.main.name} \
        --addon-name coredns \
        --resolve-conflicts OVERWRITE \
        --region ${var.aws_region} \
        --tags '${jsonencode(var.tags)}' \
        || echo "CoreDNS addon already exists or failed - continuing..."
    EOT
  }

  provisioner "local-exec" {
    when       = destroy
    command    = <<-EOT
      aws eks delete-addon \
        --cluster-name ${self.triggers.cluster_name} \
        --addon-name coredns \
        --region ${self.triggers.aws_region} \
        || echo "CoreDNS addon already deleted"
    EOT
    on_failure = continue
  }

  depends_on = [
    aws_eks_cluster.main,
    aws_eks_addon.vpc_cni
  ]
}

# kube-proxy addon
resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.main.name
  addon_name   = "kube-proxy"

  tags = var.tags

  depends_on = [aws_eks_cluster.main]
}

#==============================================================================
# OIDC PROVIDER (for IRSA - IAM Roles for Service Accounts)
#==============================================================================

data "tls_certificate" "cluster" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "cluster" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = var.tags
}
