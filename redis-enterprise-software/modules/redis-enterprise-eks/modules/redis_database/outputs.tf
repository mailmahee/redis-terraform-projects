output "database_name" {
  description = "Name of the Redis Enterprise database"
  value       = var.create_database ? var.database_name : null
}

output "database_namespace" {
  description = "Kubernetes namespace of the database"
  value       = var.create_database ? var.namespace : null
}

output "database_port" {
  description = "Port of the Redis database"
  value       = var.create_database ? var.database_port : null
}

output "database_memory_size" {
  description = "Memory size of the database"
  value       = var.create_database ? var.memory_size : null
}

output "database_replication_enabled" {
  description = "Whether replication is enabled"
  value       = var.create_database ? var.replication : null
}
