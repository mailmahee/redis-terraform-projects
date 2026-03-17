#!/bin/bash

export AWS_PROFILE=eks_micron

echo "=== Finding and deleting Load Balancers in Region 1 (us-east-1) ==="
aws elbv2 describe-load-balancers --region us-east-1 --query "LoadBalancers[?VpcId=='vpc-0ed560d9f6a62f1c5'].[LoadBalancerArn,LoadBalancerName,Type]" --output table

lb_arns=$(aws elbv2 describe-load-balancers --region us-east-1 --query "LoadBalancers[?VpcId=='vpc-0ed560d9f6a62f1c5'].LoadBalancerArn" --output text)

for lb_arn in $lb_arns; do
    echo "Deleting Load Balancer: $lb_arn"
    aws elbv2 delete-load-balancer --region us-east-1 --load-balancer-arn $lb_arn
done

echo ""
echo "=== Finding and deleting Load Balancers in Region 2 (us-east-2) ==="
aws elbv2 describe-load-balancers --region us-east-2 --query "LoadBalancers[?VpcId=='vpc-0276045eef8f04c3b'].[LoadBalancerArn,LoadBalancerName,Type]" --output table

lb_arns=$(aws elbv2 describe-load-balancers --region us-east-2 --query "LoadBalancers[?VpcId=='vpc-0276045eef8f04c3b'].LoadBalancerArn" --output text)

for lb_arn in $lb_arns; do
           ele           ele           ele
                                                                           lb_arn
done

echo ""
echo "✅ Load balancers deleted. Waiting 60 seconds for ENIs to be released..."
sleep 60
echo "Done! Terraform destroy should now proceed."
