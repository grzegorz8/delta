output "master_node_address" {
  value = module.processing.master_node_address
}

output "mlflow_repository_url" {
  value = module.ecr.mlflow_repository_url
}

output "mlflow_address" {
  value = module.mlflow.mlflow_address
}
