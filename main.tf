terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  allowed_account_ids = ["104629106545"]
  /*assume_role {
    role_arn = "arn:aws:iam::104629106545:role/bursting-mackerel-dev-gha"
    session_name = "thopkins-gha-test"
  }*/
}

resource "random_pet" "base_name" {}

variable "env" {
  type = string
  default = "dev"
}

variable "vpc_id" {
  type = string
  default = "vpc-0a8258827074381b3"
}

locals {
  app_name = "${random_pet.base_name.id}-${var.env}"
}

resource "aws_ecr_repository" "app" {
  name = local.app_name
  force_delete = true
}

resource "aws_ecs_cluster" "app" {
  name = local.app_name
}

resource "aws_cloudwatch_log_group" "app" {
  name = local.app_name
  retention_in_days = 5
}

resource "aws_ecs_task_definition" "app" {
  family = local.app_name 

  task_role_arn = aws_iam_role.task.arn
  execution_role_arn = aws_iam_role.task.arn

  requires_compatibilities = ["FARGATE"]
  network_mode = "awsvpc"

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture = "ARM64"
  }

  cpu = 256
  memory = 512

  container_definitions = jsonencode([
    {
      name = "nginx"
      image = "${aws_ecr_repository.app.repository_url}:1.0.0"
      essential = true

      portMappings = [
        {
          hostPort: 80,
          containerPort: 80,
        },
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group = aws_cloudwatch_log_group.app.name,
          awslogs-region = "us-east-1"
          awslogs-stream-prefix = local.app_name
        }
      }

      linuxParameters = {
        add = ["NET_BIND_SERVICE"]
      }
    }
  ])
}

resource "aws_iam_role" "task" {
  name = "nginx-${local.app_name}" 
  assume_role_policy = jsonencode({
    Version = "2008-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "task" {
  name = "ecs-minimum"
  role = aws_iam_role.task.name 
  policy = jsonencode({
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
        ]

        Resource = [
          "*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:BatchCheckLayerAvailability",
        ]
        Resource = [
          aws_ecr_repository.app.arn,
        ]
      }
    ]
  })
}

resource "aws_ecs_service" "app" {
  name = local.app_name

   cluster = aws_ecs_cluster.app.id
   launch_type = "FARGATE"

   task_definition = aws_ecs_task_definition.app.arn
   desired_count = 2

    network_configuration {
      subnets = data.aws_subnets.private.ids
      security_groups = [aws_security_group.task.id]
    }

    load_balancer {
      target_group_arn = aws_lb_target_group.app_http.arn
      container_name = "nginx"
      container_port = 80
    } 
}

data "aws_subnets" "private" {
  filter {
    name = "vpc-id"
    values = [var.vpc_id]
  }

  filter {
    name = "tag:app"
    values = ["true"]
  }
}

data "aws_subnets" "public" {
  filter {
    name = "vpc-id"
    values = [var.vpc_id]
  }

  filter {
    name = "tag:dmz"
    values = ["true"]
  }
}

resource "aws_security_group" "task" {
  name = "${local.app_name}-task" 
  description = "sg for ${local.app_name} ECS task"
  vpc_id = var.vpc_id
}

resource "aws_lb" "app" {
  name = local.app_name
  load_balancer_type = "application"
  internal = false

  security_groups = [
    aws_security_group.lb.id,
  ]

  subnets = data.aws_subnets.public.ids
}

resource "aws_lb_listener" "app_http" {
  load_balancer_arn = aws_lb.app.arn
  port = 80
  protocol = "HTTP"

  default_action {
    target_group_arn = aws_lb_target_group.app_http.arn
    type = "forward"
  }
}

resource "aws_lb_target_group" "app_http" {
  name = local.app_name 
  port = 80
  protocol = "HTTP"
  vpc_id = var.vpc_id

  target_type = "ip"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "lb" {
  name = "${local.app_name}-lb" 
  description = "sg for ${local.app_name}-${var.env} load balancer"
  vpc_id = var.vpc_id

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "lb_http" {
  security_group_id = aws_security_group.lb.id

  cidr_ipv4 = "0.0.0.0/0"
  from_port = 80
  to_port = 80
  ip_protocol = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "egress" {
  for_each = {
    lb = aws_security_group.lb.id
    task = aws_security_group.task.id
  }
  security_group_id = each.value
  cidr_ipv4 = "0.0.0.0/0"
  ip_protocol = -1
}

resource "aws_vpc_security_group_ingress_rule" "task_http" {
  security_group_id = aws_security_group.task.id

  referenced_security_group_id = aws_security_group.lb.id
  from_port = 80
  to_port = 80
  ip_protocol = "tcp"
}

resource "aws_s3_bucket" "test" {
  bucket = "${local.app_name}-test"
}
