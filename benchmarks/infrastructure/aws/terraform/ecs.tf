resource "aws_security_group" "alb" {
  description = "security-group--alb"
  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
  }
  ingress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
  }
  name   = "security-group--alb"
  vpc_id = aws_vpc.this.id
}

resource "aws_alb" "default" {
  name            = "alb"
  security_groups = [aws_security_group.alb.id]

  subnets = [
    aws_subnet.benchmarks_subnet1.id,
    aws_subnet.benchmarks_subnet2.id,
  ]
}

resource "aws_alb_target_group" "default" {
  health_check {
    path = "/"
  }
  name     = "alb-target-group"
  port     = 8081
  protocol = "HTTP"
  stickiness {
    type = "lb_cookie"
  }
  vpc_id = aws_vpc.this.id
}

resource "aws_security_group" "ec2" {
  description = "security-group--ec2"

  egress {
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
  }

  ingress {
    protocol        = "-1"
    security_groups = [aws_security_group.alb.id]
    from_port       = 0
    to_port         = 0
  }
  name = "security-group--ec2"
  vpc_id = aws_vpc.this.id
}

data "aws_iam_policy_document" "ecs" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      identifiers = ["ec2.amazonaws.com"]
      type        = "Service"
    }
  }
}

resource "aws_iam_role" "ecs" {
  assume_role_policy = data.aws_iam_policy_document.ecs.json
  name               = "ecsInstanceRole"
}


resource "aws_iam_role_policy_attachment" "ecs" {
  role       = aws_iam_role.ecs.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ecs" {
  name = "ecsInstanceProfile"
  role = aws_iam_role.ecs.name
}

data "aws_ami" "default" {
  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-2.0.202*-x86_64-ebs"]
  }

  most_recent = true
  owners      = ["amazon"]
}

resource "aws_launch_configuration" "default" {
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.ecs.name
  image_id                    = data.aws_ami.default.id
  instance_type               = "m5.2xlarge"
  key_name                    = aws_key_pair.benchmarks_emr_cluster.key_name
  security_groups             = [aws_security_group.ec2.id]

  lifecycle {
    create_before_destroy = true
  }

  name_prefix = "lauch-configuration-"

  root_block_device {
    volume_size = 30
    volume_type = "gp2"
  }
  user_data = file("user_data.sh")
}

resource "aws_alb_listener" "default" {
  default_action {
    target_group_arn = aws_alb_target_group.default.arn
    type             = "forward"
  }

  load_balancer_arn = aws_alb.default.arn
  port              = 8081
  protocol          = "HTTP"
}


resource "aws_autoscaling_group" "default" {
  name                 = "auto-scaling-group"
  desired_capacity     = 1
  health_check_type    = "EC2"
  launch_configuration = aws_launch_configuration.default.name
  max_size             = 1
  min_size             = 1

  target_group_arns    = [aws_alb_target_group.default.arn]
  termination_policies = ["OldestInstance"]

  vpc_zone_identifier = [
    aws_subnet.benchmarks_subnet1.id,
    aws_subnet.benchmarks_subnet2.id
  ]
}

resource "aws_ecs_capacity_provider" "this" {
  name = "default-capacity-provider"

  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.default.arn
  }
}

resource "aws_cloudwatch_log_group" "ecs_benchmark" {
  name              = "ecs-benchmark"
  retention_in_days = 1
}

resource "aws_ecs_cluster" "flink_session_cluster" {
  name = "flink-session-cluster"
  lifecycle {
    create_before_destroy = true
  }

  #  configuration {
  #    execute_command_configuration {
  #      log_configuration {
  #        cloud_watch_log_group_name = aws_cloudwatch_log_group.ecs_benchmark.name
  #      }
  #    }
  #  }
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name = aws_ecs_cluster.flink_session_cluster.name

  capacity_providers = [aws_ecs_capacity_provider.this.name]
}

resource "aws_ecs_task_definition" "flink_session_cluster" {
  family                = "flink-session-cluster"
  container_definitions = jsonencode(
    [
      {
        name         = "jobmanager"
        image        = "flink:1.13.0-scala_2.12-java8"
        command      = ["jobmanager"]
        cpu          = 2048
        memory       = 4096
        essential    = true
        portMappings = [
          {
            containerPort = 8081
            hostPort      = 8081
          }
        ],
        environment = [
          {
            name  = "FLINK_PROPERTIES"
            value = "jobmanager.rpc.address: jobmanager\n"
          }
        ],
        logConfiguration = {
          logDriver = "awslogs"
          options   = {
            awslogs-group         = aws_cloudwatch_log_group.ecs_benchmark.id
            awslogs-region        = var.region
            awslogs-stream-prefix = "jobmanager_"
          }
        }
      },
      {
        name        = "taskmanager"
        image       = "flink:1.13.0-scala_2.12-java8"
        command     = ["taskmanager"]
        cpu         = 2048
        memory      = 4096
        essential   = true
        environment = [
          {
            name  = "FLINK_PROPERTIES"
            value = "jobmanager.rpc.address: jobmanager\ntaskmanager.numberOfTaskSlots: 3\n"
          }
        ],
        logConfiguration = {
          logDriver = "awslogs"
          options   = {
            awslogs-group         = aws_cloudwatch_log_group.ecs_benchmark.id
            awslogs-region        = var.region
            awslogs-stream-prefix = "taskmanager_"
          }
        },
        links = ["jobmanager:jobmanager"]
        #      ,
        #        dependsOn = [
        #          {
        #            containerName = "jobmanager"
        #            condition     = "HEALTHY"
        #          }
        #        ]
      }
    ]
  )
  network_mode             = "bridge"
  requires_compatibilities = ["EC2"]
}

data "aws_ecs_task_definition" "flink_session_cluster" {
  task_definition = aws_ecs_task_definition.flink_session_cluster.family
}

resource "aws_ecs_service" "flink_session_cluster" {
  cluster                 = aws_ecs_cluster.flink_session_cluster.id
  depends_on              = [aws_iam_role_policy_attachment.ecs]
  desired_count           = 1
  enable_ecs_managed_tags = true
  force_new_deployment    = true

  load_balancer {
    target_group_arn = aws_alb_target_group.default.arn
    container_name   = "jobmanager"
    container_port   = 8081
  }

  name            = "flink-session-cluster"
  task_definition = "${aws_ecs_task_definition.flink_session_cluster.family}:${data.aws_ecs_task_definition.flink_session_cluster.revision}"
}



