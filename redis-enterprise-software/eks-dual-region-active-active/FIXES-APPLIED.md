# Terraform Plan Fixes Applied

## Issues Found and Fixed

### ✅ Issue #1: Undeclared variable `project_prefix`
**Error:**
```
Error: Reference to undeclared input variable
on main.tf line 290: export PROJECT_PREFIX="${var.project_prefix}"
```

**Root Cause:** The code was using `var.project_prefix` but the actual variable is `var.user_prefix`

**Fix Applied:**
- Changed `var.project_prefix` to `var.user_prefix` in `main.tf` (lines 290, 313, 339)

**Files Modified:**
- `redis-enterprise-software/eks-dual-region-active-active/main.tf`

---

### ✅ Issue #2: Undeclared variable `aws_profile`
**Error:**
```
Error: Reference to undeclared input variable
on main.tf line 297: export AWS_PROFILE="${var.aws_profile}"
```

**Root Cause:** There is no `aws_profile` variable defined in `variables.tf`

**Fix Applied:**
- Changed `${var.aws_profile}` to `"default"` as a hardcoded value
- Users can override this by setting the AWS_PROFILE environment variable

**Files Modified:**
- `redis-enterprise-software/eks-dual-region-active-active/main.tf` (line 297)

---

### ✅ Issue #3: Undeclared variable `nodes` in redis_cluster module
**Error:**
```
Error: Reference to undeclared input variable
on ../modules/redis-enterprise-eks/modules/redis_cluster/outputs.tf line 18:
value = var.nodes
```

**Root Cause:** The output was referencing `var.nodes` but the actual variable is `var.node_count`

**Fix Applied:**
- Changed `var.nodes` to `var.node_count` in outputs.tf

**Files Modified:**
- `redis-enterprise-software/modules/redis-enterprise-eks/modules/redis_cluster/outputs.tf` (line 18)

---

## Summary of Changes

### Files Modified:
1. ✅ `redis-enterprise-software/eks-dual-region-active-active/main.tf`
   - Line 290: `var.project_prefix` → `var.user_prefix`
   - Line 297: `var.aws_profile` → `"default"`
   - Line 313: `var.project_prefix` → `var.user_prefix`
   - Line 339: `var.project_prefix` → `var.user_prefix`

2. ✅ `redis-enterprise-software/modules/redis-enterprise-eks/modules/redis_cluster/outputs.tf`
   - Line 18: `var.nodes` → `var.node_count`

---

## Next Steps

### 1. Create terraform.tfvars file

If you don't have a `terraform.tfvars` file, create one:

```bash
cp terraform.tfvars.example terraform.tfvars
vim terraform.tfvars
```

**Minimum required content:**
```hcl
# Basic Configuration
owner                  = "mahee_gunturu"
user_prefix            = "micron"
redis_cluster_password = "YourSecurePassword123!"

# Regions
region1 = "us-east-1"
region2 = "us-east-2"

# Cluster Configuration
cluster_name = "redis-enterprise"

# Redis Namespace
redis_namespace = "redis-enterprise"

# Kubectl contexts
region1_kubectl_context = "region1"
region2_kubectl_context = "region2"
```

### 2. Run terraform plan again

```bash
terraform plan
```

This should now work without the previous errors!

### 3. If successful, apply the changes

```bash
terraform apply
```

---

## Important Note About Variable Naming

The codebase uses `user_prefix` as the variable name (not `project_prefix`). This is the existing convention in the codebase.

**In the generated `config.env` file:**
- The variable is exported as `PROJECT_PREFIX` for consistency with the deployment scripts
- But in Terraform, it's sourced from `var.user_prefix`

**Mapping:**
```
terraform.tfvars:  user_prefix = "micron"
       ↓
variables.tf:      variable "user_prefix" { ... }
       ↓
main.tf:           export PROJECT_PREFIX="${var.user_prefix}"
       ↓
config.env:        export PROJECT_PREFIX="micron"
       ↓
deploy scripts:    $PROJECT_PREFIX
```

---

## Verification

After applying these fixes, `terraform plan` should:
1. ✅ Not show any "undeclared variable" errors
2. ✅ Successfully generate the execution plan
3. ✅ Show resources that will be created

---

**All fixes have been applied. You can now run `terraform plan` again!**

