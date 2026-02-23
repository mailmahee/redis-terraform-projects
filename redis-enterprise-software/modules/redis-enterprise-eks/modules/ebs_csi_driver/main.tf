#==============================================================================
# EBS CSI DRIVER IAM ROLE (IRSA - IAM Roles for Service Accounts)
#==============================================================================

data "aws_iam_policy_document" "ebs_csi_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    effect  = "Allow"

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:ebs-csi-controller-sa"]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.oidc_issuer_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ebs_csi" {
  name               = "${var.cluster_name}-ebs-csi-driver-role"
  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume_role.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.ebs_csi.name
}

#==============================================================================
# EBS CSI DRIVER ADDON
#==============================================================================

resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = var.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = var.ebs_csi_driver_version
  service_account_role_arn = aws_iam_role.ebs_csi.arn

  tags = var.tags

  depends_on = [
    aws_iam_role_policy_attachment.ebs_csi
  ]
}

#==============================================================================
# STORAGE CLASS (GP3 for Redis Enterprise)
#==============================================================================

resource "kubectl_manifest" "gp3_storage_class" {
  yaml_body = <<-YAML
    apiVersion: storage.k8s.io/v1
    kind: StorageClass
    metadata:
      name: ${var.storage_class_name}
      annotations:
        storageclass.kubernetes.io/is-default-class: "${var.set_as_default}"
    provisioner: ebs.csi.aws.com
    parameters:
      type: gp3
      encrypted: "true"
      fsType: xfs
    volumeBindingMode: WaitForFirstConsumer
    allowVolumeExpansion: true
  YAML

  depends_on = [aws_eks_addon.ebs_csi]
}
