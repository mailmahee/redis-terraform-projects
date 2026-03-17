#!/bin/bash
# Validate that all required values can be extracted

set -e

TERRAFORM_DIR="../.."
cd "$TERRAFORM_DIR"

echo "Validating Terraform state..."
terraform output -raw region1 >/dev/null || { echo "❌ Missing region1 output"; exit 1; }
terraform output -raw region2 >/dev/null || { echo "❌ Missing region2 output"; exit 1; }
terraform output -raw user_prefix >/dev/null || { echo "❌ Missing user_prefix output"; exit 1; }

echo "Validating terraform.tfvars..."
grep -q "^redis_namespace" terraform.tfvars || { echo "❌ Missing redis_namespace"; exit 1; }
grep -q "^region1_kubectl_context" terraform.tfvars || { echo "❌ Missing region1_kubectl_context"; exit 1; }
grep -q "^region2_kubectl_context" terraform.tfvars || { echo "❌ Missing region2_kubectl_context"; exit 1; }

echo "✅ All required values can be extracted!"