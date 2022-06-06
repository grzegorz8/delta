output "mlflow_address" {
  value = "http://${aws_alb.mlflow.dns_name}:${local.mlflow_port}"
}
