resource "aws_ecr_repository" "mlflow" {
  name                 = "mlflow"
  image_tag_mutability = "MUTABLE"
}
