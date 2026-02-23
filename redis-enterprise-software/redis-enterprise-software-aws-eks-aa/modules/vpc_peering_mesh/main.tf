#==============================================================================
# VPC PEERING MESH FOR MULTI-REGION ACTIVE-ACTIVE
#==============================================================================
# Creates a full mesh of VPC peering connections between all regions
# Enables Redis Enterprise clusters to communicate across regions for Active-Active
#==============================================================================

# Create all unique region pairs for peering
locals {
  # Convert region keys to list for indexed iteration
  region_keys = keys(var.region_configs)

  # Generate all unique pairs of regions using indices (avoid duplicates and self-peering)
  region_pairs = flatten([
    for req_idx in range(length(local.region_keys)) : [
      for acc_idx in range(length(local.region_keys)) : {
        requester_key                     = local.region_keys[req_idx]
        accepter_key                      = local.region_keys[acc_idx]
        requester_region                  = local.region_keys[req_idx]
        accepter_region                   = local.region_keys[acc_idx]
        requester_vpc_id                  = var.region_configs[local.region_keys[req_idx]].vpc_id
        accepter_vpc_id                   = var.region_configs[local.region_keys[acc_idx]].vpc_id
        requester_cidr                    = var.region_configs[local.region_keys[req_idx]].vpc_cidr
        accepter_cidr                     = var.region_configs[local.region_keys[acc_idx]].vpc_cidr
        requester_public_route_table_id   = var.region_configs[local.region_keys[req_idx]].public_route_table_id
        accepter_public_route_table_id    = var.region_configs[local.region_keys[acc_idx]].public_route_table_id
        requester_private_route_table_ids = var.region_configs[local.region_keys[req_idx]].private_route_table_ids
        accepter_private_route_table_ids  = var.region_configs[local.region_keys[acc_idx]].private_route_table_ids
      }
      if req_idx < acc_idx # Only create one connection per pair using numeric comparison
    ]
  ])

  # Create map for easy lookup
  peering_map = {
    for pair in local.region_pairs :
    "${pair.requester_key}-${pair.accepter_key}" => pair
  }
}

#==============================================================================
# VPC PEERING CONNECTIONS
#==============================================================================

# Create VPC peering connections between all region pairs
resource "aws_vpc_peering_connection" "cross_region" {
  for_each = local.peering_map
  provider = aws.region1 # Requester region

  # Requester VPC configuration
  vpc_id = each.value.requester_vpc_id

  # Accepter VPC configuration (different region)
  peer_vpc_id = each.value.accepter_vpc_id
  peer_region = each.value.accepter_region

  # Don't auto-accept (need to accept in peer region)
  auto_accept = false

  tags = merge(
    {
      Name      = "${var.name_prefix}-peering-${each.key}"
      Requester = each.value.requester_key
      Accepter  = each.value.accepter_key
      Owner     = var.owner
      Project   = var.project
      Purpose   = "Redis Active-Active Cross-Region Communication"
    },
    var.tags
  )
}

#==============================================================================
# PEERING CONNECTION ACCEPTERS
#==============================================================================

# Auto-accept peering connections (requires provider for accepter region)
resource "aws_vpc_peering_connection_accepter" "cross_region" {
  for_each = local.peering_map
  provider = aws.region2 # Accepter region

  vpc_peering_connection_id = aws_vpc_peering_connection.cross_region[each.key].id
  auto_accept               = true

  tags = merge(
    {
      Name    = "${var.name_prefix}-peering-accepter-${each.key}"
      Owner   = var.owner
      Project = var.project
      Side    = "Accepter"
    },
    var.tags
  )
}

#==============================================================================
# PUBLIC ROUTE TABLE UPDATES FOR CROSS-REGION TRAFFIC
#==============================================================================

# Add routes in requester public route tables to accepter VPCs
resource "aws_route" "requester_public_to_accepter" {
  for_each = local.peering_map
  provider = aws.region1 # Requester region

  route_table_id            = each.value.requester_public_route_table_id
  destination_cidr_block    = each.value.accepter_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.cross_region[each.key].id

  depends_on = [aws_vpc_peering_connection_accepter.cross_region]
}

# Add routes in accepter public route tables to requester VPCs
resource "aws_route" "accepter_public_to_requester" {
  for_each = local.peering_map
  provider = aws.region2 # Accepter region

  route_table_id            = each.value.accepter_public_route_table_id
  destination_cidr_block    = each.value.requester_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.cross_region[each.key].id

  depends_on = [aws_vpc_peering_connection_accepter.cross_region]
}

#==============================================================================
# PRIVATE ROUTE TABLE UPDATES FOR CROSS-REGION TRAFFIC
#==============================================================================
# Using count-based approach with static var.private_subnet_count to avoid
# unknown for_each keys at plan time. The actual route table IDs are looked
# up by index at apply time.
#==============================================================================

# Add routes in requester private route tables to accepter VPCs
# Using var.private_subnet_count (static) to avoid unknown count at plan time
resource "aws_route" "requester_private_to_accepter" {
  count    = length(local.region_pairs) > 0 ? var.private_subnet_count : 0
  provider = aws.region1 # Requester region

  route_table_id            = local.region_pairs[0].requester_private_route_table_ids[count.index]
  destination_cidr_block    = local.region_pairs[0].accepter_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.cross_region[keys(local.peering_map)[0]].id

  depends_on = [aws_vpc_peering_connection_accepter.cross_region]
}

# Add routes in accepter private route tables to requester VPCs
resource "aws_route" "accepter_private_to_requester" {
  count    = length(local.region_pairs) > 0 ? var.private_subnet_count : 0
  provider = aws.region2 # Accepter region

  route_table_id            = local.region_pairs[0].accepter_private_route_table_ids[count.index]
  destination_cidr_block    = local.region_pairs[0].requester_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.cross_region[keys(local.peering_map)[0]].id

  depends_on = [aws_vpc_peering_connection_accepter.cross_region]
}
