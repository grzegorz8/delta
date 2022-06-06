resource "aws_db_instance" "benchmarks_metastore_service" {
  allocated_storage      = 50
  engine                 = "mysql"
  engine_version         = "8.0.28"
  instance_class         = "db.m5.large"
  db_name                = "hive"
  username               = var.mysql_user
  password               = var.mysql_password
  skip_final_snapshot    = true
  availability_zone      = var.availability_zone1
  db_subnet_group_name   = aws_db_subnet_group.benchmarks_metastore_service.name
  vpc_security_group_ids = [
    aws_security_group.emr_slave.id,
    aws_security_group.emr_master.id
  ]
}

resource "aws_db_subnet_group" "benchmarks_metastore_service" {
  name       = "benchmarks_subnet_group_for_metastore_service"
  subnet_ids = [
    aws_subnet.benchmarks_subnet1.id,
    aws_subnet.benchmarks_subnet2.id
  ]
}

resource "aws_db_instance" "mflow" {
  allocated_storage      = 50
  engine                 = "mysql"
  engine_version         = "8.0.28"
  instance_class         = "db.m5.large"
  db_name                = "mlflow"
  username               = var.mysql_user
  password               = var.mysql_password
  skip_final_snapshot    = true
  availability_zone      = var.availability_zone1
  db_subnet_group_name   = aws_db_subnet_group.mflow.name
  vpc_security_group_ids = [
    aws_security_group.mlflow_ec2.id
  ]
}

resource "aws_db_subnet_group" "mflow" {
  name       = "mflow_database_subnet_group"
  subnet_ids = [
    aws_subnet.benchmarks_subnet1.id,
    aws_subnet.benchmarks_subnet2.id
  ]
}
