locals {
  mlflow_cluster_name   = "mlflow"
  mlflow_container_name = "mlflow"
  mlflow_port           = 5000
}

resource "aws_security_group" "mlflow_lb" {
  name   = "mlflow-lb"
  vpc_id = aws_vpc.this.id
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

resource "aws_alb" "mlflow" {
  name            = "mlflow-alb"
  security_groups = [aws_security_group.mlflow_lb.id]
  subnets         = [
    aws_subnet.benchmarks_subnet1.id,
    aws_subnet.benchmarks_subnet2.id,
  ]
}

resource "aws_alb_target_group" "mlflow" {
  name     = "mlflow-alb-target-group"
  vpc_id   = aws_vpc.this.id
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

resource "aws_security_group" "mlflow_ec2" {
  name   = "security-group--ec2"
  vpc_id = aws_vpc.this.id
  ingress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    security_groups = [aws_security_group.mlflow_lb.id]
  }
  egress {
    cidr_blocks = ["0.0.0.0/0"]
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
  }
}

data "aws_ami" "default" {
  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-2.0.202*-x86_64-ebs"]
  }
  most_recent = true
  owners      = ["amazon"]
}

resource "aws_launch_configuration" "mlflow" {
  iam_instance_profile        = aws_iam_instance_profile.ecs.name
  image_id                    = data.aws_ami.default.id
  instance_type               = "m5.xlarge"
  key_name                    = aws_key_pair.benchmarks_emr_cluster.key_name
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

resource "aws_autoscaling_group" "mlflow" {
  name                 = "mlflow-auto-scaling-group"
  launch_configuration = aws_launch_configuration.mlflow.name
  health_check_type    = "EC2"
  desired_capacity     = 1
  max_size             = 1
  min_size             = 1
  target_group_arns    = [aws_alb_target_group.mlflow.arn]
  termination_policies = ["OldestInstance"]
  vpc_zone_identifier  = [
    aws_subnet.benchmarks_subnet1.id,
    aws_subnet.benchmarks_subnet2.id
  ]
}

resource "aws_ecs_capacity_provider" "this" {
  name = "default-capacity-provider"

  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.mlflow.arn
  }
}

resource "aws_cloudwatch_log_group" "ecs_benchmark" {
  name              = "ecs-benchmark"
  retention_in_days = 1
}

resource "aws_ecs_cluster" "mlflow" {
  name = local.mlflow_cluster_name
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name = aws_ecs_cluster.mlflow.name

  capacity_providers = [aws_ecs_capacity_provider.this.name]
}

resource "aws_ecs_task_definition" "mlflow" {
  family                   = "mlflow"
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
  container_definitions    = jsonencode(
    [
      {
        name         = local.mlflow_container_name
        image        = "781336771001.dkr.ecr.us-west-2.amazonaws.com/mlflow-repository:1.26.1"
        cpu          = 4096
        memory       = 14336
        essential    = true
        portMappings = [
          {
            containerPort = local.mlflow_port
            hostPort      = local.mlflow_port
          }
        ],
        environment = [
          {
            name  = "BUCKET"
            value = var.benchmarks_bucket_name
          },
          {
            name  = "HOST"
            value = aws_db_instance.mflow.address
          },
          {
            name  = "PORT"
            value = tostring(aws_db_instance.mflow.port)
          },
          {
            name  = "DATABASE"
            value = aws_db_instance.mflow.db_name
          },
          {
            name  = "PASSWORD"
            value = var.mysql_password
          },
          {
            name  = "USERNAME"
            value = var.mysql_user
          }
        ],
        logConfiguration = {
          logDriver = "awslogs"
          options   = {
            awslogs-group         = aws_cloudwatch_log_group.ecs_benchmark.id
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
