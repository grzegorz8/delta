#output "master_node_address" {
#  value = aws_emr_cluster.benchmarks.master_public_dns
#}

output "load_balancer_address" {
  value = aws_alb.default.dns_name
}
