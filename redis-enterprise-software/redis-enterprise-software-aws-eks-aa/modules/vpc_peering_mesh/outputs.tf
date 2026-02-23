#==============================================================================
# VPC PEERING MESH MODULE OUTPUTS
#==============================================================================

output "peering_connection_ids" {
  description = "Map of peering connection IDs"
  value = {
    for key, conn in aws_vpc_peering_connection.cross_region :
    key => conn.id
  }
}

output "peering_connection_status" {
  description = "Status of each peering connection"
  value = {
    for key, conn in aws_vpc_peering_connection.cross_region :
    key => conn.accept_status
  }
}

output "region_pairs" {
  description = "List of region pairs that have been peered"
  value = [
    for key, pair in local.peering_map :
    "${pair.requester_key} <-> ${pair.accepter_key}"
  ]
}
