#!/bin/bash

REGION1_VPC="vpc-0ed560d9f6a62f1c5"
REGION2_VPC="vpc-0276045eef8f04c3b"
REGION1="us-east-1"
REGION2="us-east-2"

echo "=== Checking ALL resources in Region 1 VPC ==="
echo ""

echo "NAT Gateways:"
aws ec2 describe-nat-gateways --region ${REGION1} --filter "Name=vpc-id,Values=${REGION1_VPC}" --query "NatGateways[*].[NatGatewayId,State]" --output table

echo ""
echo "Network Interfaces:"
aws ec2 describe-network-interfaces --region ${REGION1} --filters "Name=vpc-id,Values=${REGION1_VPC}" --query "NetworkInterfaces[*].[NetworkInterfaceId,Status,Description,SubnetId]" --output table

echo ""
echo "Elastic IPs:"
aws ec2 describe-addresses --region ${REGION1} --filters "Name=domain,Values=vpc" --query "Addresses[*].[AllocationId,PublicIp,AssociationId]" --output table

echo ""
echo "=== Checking ALL resources in Region 2 VPC ==="
echo ""

echo "NAT Gateways:"
aws ec2 describe-nat-gateways --region ${REGION2} --filter "Name=vpc-id,Values=${REGION2_VPC}" --query "NatGateways[*].[NatGatewayId,State]" --output table

eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeaws ec2 describe-network-interfaces --eeeeeeeeeeeeeeeeee--eeeeeeeeeeeeeeeeeeid,eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeaws ec2 describe-.[eeeeeekIneeeeeeeeeeeeeeeeeeesceeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeaws ec2 describe-network-interfaces --eeeeeeeeeeeeeeeeee--eeeeeeeeeeeeeeeeeeid,eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeaws eAddeeeeee[*eeeeeeeeeeeeeeeeeeeeeeeeeAssociationId]" --output table
