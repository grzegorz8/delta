output "master_node_address" {
  value = aws_emr_cluster.benchmarks.master_public_dns
}

output "mlflow_address" {
  value = "http://${aws_alb.mlflow.dns_name}:${local.mlflow_port}"
}
