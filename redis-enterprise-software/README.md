# Redis Enterprise Software Deployments

This directory contains Terraform configurations for deploying Redis Enterprise Software on various platforms.

## Directory Structure

```
redis-enterprise-software/
├── modules/
│   └── redis-enterprise-eks/          # Core reusable EKS module (NO providers)
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── modules/                   # Submodules (VPC, EKS, Redis, etc.)
│
├── eks-single-region/                 # ✅ Wrapper for standalone EKS deployment
│   ├── main.tf                        # Calls ../modules/redis-enterprise-eks
│   ├── provider.tf                    # Defines providers
│   ├── variables.tf
│   ├── outputs.tf
│   ├── terraform.tfvars.example
│   └── README.md
│
├── eks-dual-region/                   # ✅ Wrapper for dual-region EKS deployment
│   ├── main.tf                        # Calls ../modules/redis-enterprise-eks twice
│   ├── provider.tf                    # Defines providers with aliases
│   ├── variables.tf
│   ├── outputs.tf
│   ├── terraform.tfvars.example
│   └── README.md
│
├── redis-enterprise-software-aws-eks/ # ⚠️  DEPRECATED - Use eks-single-region instead
│   └── ...
│
└── eks-dual-region-basic/             # ⚠️  DEPRECATED - Use eks-dual-region instead
    └── ...
```

## Architecture Pattern

This repository follows a **modular wrapper pattern**:

1. **Core Module** (`modules/redis-enterprise-eks/`)
   - Contains all the deployment logic
   - **No provider configurations** (makes it reusable)
   - Can be called by multiple wrappers

2. **Wrappers** (`eks-single-region/`, `eks-dual-region/`)
   - Provide provider configurations
   - Call the core module with appropriate parameters
   - Handle region-specific or multi-region orchestration

### Benefits of This Pattern

- ✅ **Reusability** - Core module can be used in multiple scenarios
- ✅ **Maintainability** - Changes to core logic benefit all wrappers
- ✅ **Flexibility** - Easy to create new deployment patterns (e.g., 3-region, VM-based)
- ✅ **Clarity** - Clear separation between deployment logic and orchestration

## Quick Start

### Single-Region Deployment

```bash
cd eks-single-region/
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your settings
terraform init
terraform apply
```

### Dual-Region Deployment

```bash
cd eks-dual-region/
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your settings
terraform init
terraform apply
```

## Available Deployments

| Deployment | Description | Status | Use Case |
|------------|-------------|--------|----------|
| **eks-single-region** | Single EKS cluster in one region | ✅ Ready | Production single-region deployment |
| **eks-dual-region** | Two EKS clusters with VPC peering | ✅ Ready | Multi-region HA, disaster recovery |
| redis-enterprise-software-aws-eks | Original standalone module | ⚠️  Deprecated | Use eks-single-region instead |
| eks-dual-region-basic | Original dual-region attempt | ⚠️  Deprecated | Use eks-dual-region instead |

## Future Deployments

The modular structure makes it easy to add new deployment patterns:

- **eks-triple-region** - Three regions for global distribution
- **vm-single-region** - Redis Enterprise on EC2 VMs
- **vm-dual-region** - Dual-region VM deployment
- **hybrid** - Mix of EKS and VM deployments

## Migration Guide

### From `redis-enterprise-software-aws-eks/` to `eks-single-region/`

The new `eks-single-region/` wrapper is functionally identical to the old standalone module:

```bash
# Old way
cd redis-enterprise-software-aws-eks/
terraform apply

# New way (same result)
cd eks-single-region/
terraform apply
```

**Why migrate?**
- Uses the reusable core module
- Benefits from future improvements automatically
- Consistent with the new architecture pattern

### From `eks-dual-region-basic/` to `eks-dual-region/`

The new `eks-dual-region/` wrapper uses the proven single-region module:

```bash
# Old way (had issues)
cd eks-dual-region-basic/
terraform apply  # Often failed

# New way (reliable)
cd eks-dual-region/
terraform apply  # Uses proven working module
```

**Why migrate?**
- More reliable (uses proven code)
- Simpler architecture
- Easier to debug

## Support

For issues or questions:
1. Check the README in the specific deployment directory
2. Review the core module documentation in `modules/redis-enterprise-eks/`
3. Open an issue with details about your deployment

## Contributing

When adding new deployment patterns:
1. Create a new wrapper directory (e.g., `eks-triple-region/`)
2. Call the core module from `modules/redis-enterprise-eks/`
3. Add provider configurations in the wrapper
4. Include README.md and terraform.tfvars.example
5. Update this main README with the new deployment option

