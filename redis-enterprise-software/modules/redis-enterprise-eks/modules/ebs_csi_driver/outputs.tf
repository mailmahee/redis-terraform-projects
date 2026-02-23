output "ebs_csi_driver_role_arn" {
  description = "IAM role ARN for EBS CSI driver"
  value       = aws_iam_role.ebs_csi.arn
}

output "ebs_csi_addon_version" {
  description = "Version of the EBS CSI driver addon"
  value       = aws_eks_addon.ebs_csi.addon_version
}

output "storage_class_name" {
  description = "Name of the created storage class"
  value       = var.storage_class_name
}
