locals {
  mlflow_cluster_name   = "mlflow"
  mlflow_container_name = "mlflow"
  mlflow_port           = 5000
}

/* ========== RDS ========== */

resource "aws_db_instance" "mlflow" {
  engine                 = "mysql"
  engine_version         = "8.0.28"
  instance_class         = "db.m5.large"
  db_name                = "mlflow"
  username               = var.mysql_user
  password               = var.mysql_password
  availability_zone      = var.availability_zone1
  skip_final_snapshot    = true
  allocated_storage      = 50
  db_subnet_group_name   = aws_db_subnet_group.mlflow.name
  vpc_security_group_ids = [aws_security_group.mlflow_db.id]
}

resource "aws_db_subnet_group" "mlflow" {
  name       = "mlflow-database-subnet-group"
  subnet_ids = [var.subnet1_id, var.subnet2_id]
}

/* ========== EC2 ========== */

data "aws_ami" "default" {
  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-2.0.202*-x86_64-ebs"]
  }
  most_recent = true
  owners      = ["amazon"]
}

/* ========== ELB ========== */

resource "aws_alb" "mlflow" {
  name            = "mlflow-alb"
  security_groups = [aws_security_group.mlflow_lb.id]
  subnets         = [var.subnet1_id, var.subnet2_id]
}

resource "aws_alb_target_group" "mlflow" {
  name     = "mlflow-alb-target-group"
  vpc_id   = var.vpc_id
  protocol = "HTTP"
  port     = local.mlflow_port
  stickiness {
    type = "lb_cookie"
  }
  health_check {
    path = "/"
    port = local.mlflow_port
  }
}

resource "aws_launch_configuration" "mlflow" {
  iam_instance_profile        = aws_iam_instance_profile.ecs_instance.name
  image_id                    = data.aws_ami.default.id
  instance_type               = "m5.xlarge"
  associate_public_ip_address = true
  security_groups             = [aws_security_group.mlflow_ec2.id]
  lifecycle {
    create_before_destroy = true
  }
  name_prefix = "mlflow-"
  root_block_device {
    volume_type = "gp2"
    volume_size = 30
  }
  user_data = "#!/bin/bash\necho ECS_CLUSTER=${local.mlflow_cluster_name} >> /etc/ecs/ecs.config"
}

resource "aws_alb_listener" "mlflow" {
  load_balancer_arn = aws_alb.mlflow.arn
  port              = local.mlflow_port
  protocol          = "HTTP"
  default_action {
    target_group_arn = aws_alb_target_group.mlflow.arn
    type             = "forward"
  }
}

/* ========== Autoscaling ========== */

resource "aws_autoscaling_group" "mlflow" {
  name                 = "mlflow-auto-scaling-group"
  launch_configuration = aws_launch_configuration.mlflow.name
  health_check_type    = "EC2"
  desired_capacity     = 1
  max_size             = 1
  min_size             = 1
  target_group_arns    = [aws_alb_target_group.mlflow.arn]
  termination_policies = ["OldestInstance"]
  vpc_zone_identifier  = [var.subnet1_id, var.subnet2_id]
}

/* ========== ECS ========== */

resource "aws_ecs_capacity_provider" "this" {
  name = "default-capacity-provider"
  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.mlflow.arn
  }
}

resource "aws_ecs_cluster" "mlflow" {
  name = local.mlflow_cluster_name
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name       = aws_ecs_cluster.mlflow.name
  capacity_providers = [aws_ecs_capacity_provider.this.name]
}

resource "aws_ecs_task_definition" "mlflow" {
  family                   = "mlflow"
  network_mode             = "host"
  requires_compatibilities = ["EC2"]
  execution_role_arn       = aws_iam_role.mlflow_execution.arn
  task_role_arn            = aws_iam_role.mlflow_task.arn
  container_definitions    = jsonencode(
    [
      {
        name         = local.mlflow_container_name
        image        = "${var.mlflow_repository_url}:latest"
        cpu          = 4096
        memory       = 14336
        essential    = true
        portMappings = [
          {
            containerPort = local.mlflow_port
            hostPort      = local.mlflow_port
          }
        ]
        environment = [
          {
            name  = "ARTIFACT_ROOT"
            value = "s3://${var.benchmarks_bucket_name}/mlflow/"
          },
          {
            name  = "HOST"
            value = aws_db_instance.mlflow.address
          },
          {
            name  = "PORT"
            value = tostring(aws_db_instance.mlflow.port)
          },
          {
            name  = "DATABASE"
            value = aws_db_instance.mlflow.db_name
          }
        ]
        secrets = [
          {
            name      = "PASSWORD"
            valueFrom = aws_secretsmanager_secret_version.mlflow_database_password.arn
          },
          {
            name      = "USERNAME"
            valueFrom = aws_secretsmanager_secret_version.mlflow_database_username.arn
          }
        ]
        logConfiguration = {
          logDriver = "awslogs"
          options   = {
            awslogs-group         = aws_cloudwatch_log_group.mlflow.id
            awslogs-region        = var.region
            awslogs-stream-prefix = "mlflow_"
          }
        }
      }
    ]
  )
}

data "aws_ecs_task_definition" "mlflow" {
  task_definition = aws_ecs_task_definition.mlflow.family
}

resource "aws_ecs_service" "mlflow" {
  name                    = "mlflow"
  task_definition         = "${aws_ecs_task_definition.mlflow.family}:${data.aws_ecs_task_definition.mlflow.revision}"
  cluster                 = aws_ecs_cluster.mlflow.id
  depends_on              = [aws_iam_role_policy_attachment.ecs_instance]
  desired_count           = 1
  wait_for_steady_state   = true
  enable_ecs_managed_tags = true
  force_new_deployment    = true
  load_balancer {
    target_group_arn = aws_alb_target_group.mlflow.arn
    container_name   = local.mlflow_container_name
    container_port   = local.mlflow_port
  }
}

/* ========== IAM ========== */

data "aws_iam_policy_document" "ec2_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      identifiers = ["ec2.amazonaws.com"]
      type        = "Service"
    }
  }
}

resource "aws_iam_role" "ecs_instance" {
  name               = "ecsInstanceRole"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role_policy.json
}

resource "aws_iam_role_policy_attachment" "ecs_instance" {
  role       = aws_iam_role.ecs_instance.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ecs_instance" {
  name = "ecsInstanceProfile"
  role = aws_iam_role.ecs_instance.name
}


resource "aws_iam_role" "mlflow_execution" {
  name               = "mlflowTaskExecutionRole"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role_policy.json
}

data "aws_iam_policy_document" "ecs_assume_role_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      identifiers = ["ecs-tasks.amazonaws.com"]
      type        = "Service"
    }
  }
}

resource "aws_iam_role_policy_attachment" "mlflow_execution" {
  role       = aws_iam_role.mlflow_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role_policy" "mlflow_secrets" {
  name   = "mlflowSecretsRolePolicy"
  role   = aws_iam_role.mlflow_execution.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": [
        "arn:aws:secretsmanager:${var.region}:${local.accountId}:secret:mlflowDatabase*"
      ]
    }
  ]
}
EOF
}

resource "aws_iam_role" "mlflow_task" {
  name               = "mlflowTaskRole"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume_role_policy.json
}

resource "aws_iam_role_policy" "mlflow_task" {
  name   = "mlflowTaskPolicy"
  role   = aws_iam_role.mlflow_execution.id
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Resource": "arn:aws:s3:::${var.benchmarks_bucket_name}",
      "Action": [
        "s3:ListBucket"
      ]
    },
    {
      "Effect": "Allow",
      "Resource": "arn:aws:s3:::${var.benchmarks_bucket_name}/*",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject"
      ]
    }
  ]
}
EOF
}

/* ========== Cloudwatch ========== */

resource "aws_cloudwatch_log_group" "mlflow" {
  name              = "mlflow"
  retention_in_days = 1
}

/* ========== Secrets Manager ========== */

resource "aws_secretsmanager_secret" "mlflow_database_username" {
  name                    = "mlflowDatabaseUsername"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "mlflow_database_username" {
  secret_id     = aws_secretsmanager_secret.mlflow_database_username.id
  secret_string = var.mysql_user
}

resource "aws_secretsmanager_secret" "mlflow_database_password" {
  name                    = "mlflowDatabasePassword"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "mlflow_database_password" {
  secret_id     = aws_secretsmanager_secret.mlflow_database_password.id
  secret_string = var.mysql_password
}

/* ========== VPC ========== */

resource "aws_security_group" "mlflow_db" {
  name   = "mlflow-db-security-group"
  vpc_id = var.vpc_id
  ingress {
    description     = "Allow inbound traffic only from mlflow."
    from_port       = 3306
    to_port         = 3306
    protocol        = "TCP"
    security_groups = [aws_security_group.mlflow_ec2.id]
  }
  egress {
    description = "Allow all outbound traffic."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "mlflow_lb" {
  name   = "mlflow-lb-security-group"
  vpc_id = var.vpc_id
  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
  }
  egress {
    cidr_blocks = ["0.0.0.0/0"]
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
  }
}

resource "aws_security_group" "mlflow_ec2" {
  name   = "mlflow-ec2-security-group"
  vpc_id = var.vpc_id
  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.mlflow_lb.id]
  }
  ingress {
    description = "Allow inbound traffic from given IP."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["${var.user_ip_address}/32"]
  }
  egress {
    cidr_blocks = ["0.0.0.0/0"]
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
  }
}
