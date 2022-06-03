resource "aws_key_pair" "benchmarks_emr_cluster" {
  key_name   = "benchmarks_cluster_key"
  public_key = file(var.emr_public_key_path)
}
