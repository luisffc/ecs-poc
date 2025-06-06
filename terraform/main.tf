terraform {
  required_version = ">= 1.12.1"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.99"
    }
  }
}

provider "aws" { region = var.aws_region }

############################################
# 1. Logging
############################################
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.cluster_name}"
  retention_in_days = 14
}

############################################
# 2. IAM – execution role (task role optional)
############################################
resource "aws_iam_role" "ecs_exec" {
  name               = "${var.cluster_name}-exec-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_assume.json
}

data "aws_iam_policy_document" "ecs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "ecs_exec_attach" {
  role       = aws_iam_role.ecs_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

############################################
# 3. ECS Cluster
############################################
resource "aws_ecs_cluster" "this" {
  name = var.cluster_name
}

############################################
# 4. Security groups
############################################
# ALB SG – allow inbound 80 from Internet
resource "aws_security_group" "alb" {
  name        = "${var.cluster_name}-alb-sg"
  description = "ALB ingress"
  vpc_id      = module.vpc.vpc_id
  ingress {
    protocol    = "tcp"
    from_port   = 80
    to_port     = 80
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Task SG – allow inbound 8080 only from the ALB SG
resource "aws_security_group" "task" {
  name   = "${var.cluster_name}-task-sg"
  vpc_id = module.vpc.vpc_id
  ingress {
    protocol        = "tcp"
    from_port       = 8080
    to_port         = 8080
    security_groups = [aws_security_group.alb.id]
  }
  egress {
    protocol    = "-1"
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

############################################
# 5. Everything per service (for_each over repo names)
############################################
locals { repos = toset(var.ecr_repositories) }

# 5a. Task definitions
resource "aws_ecs_task_definition" "task" {
  for_each                 = local.repos
  family                   = "${each.value}-task"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  execution_role_arn       = aws_iam_role.ecs_exec.arn

  container_definitions = jsonencode([
    {
      name         = each.value
      image        = "${var.aws_account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${each.value}:latest"
      portMappings = [{ containerPort = 8080, protocol = "tcp" }]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-region        = var.aws_region
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-stream-prefix = each.value
        }
      }
      essential = true
    }
  ])
}

# 5b. Load balancers (one per service)
resource "aws_lb" "alb" {
  for_each           = local.repos
  name               = "${replace(each.value, "_", "-")}-alb"
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = module.vpc.public_subnets
}

resource "aws_lb_target_group" "tg" {
  for_each    = local.repos
  name        = "${replace(each.value, "_", "-")}-tg"
  port        = 8080
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = module.vpc.vpc_id
  health_check {
    path     = "/"
    interval = 30
  }
}

resource "aws_lb_listener" "listener" {
  for_each          = local.repos
  load_balancer_arn = aws_lb.alb[each.value].arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg[each.value].arn
  }
}

# 5c. ECS services
resource "aws_ecs_service" "svc" {
  for_each        = local.repos
  name            = "${each.value}-svc"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.task[each.value].arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = module.vpc.private_subnets
    security_groups  = [aws_security_group.task.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.tg[each.value].arn
    container_name   = each.value
    container_port   = 8080
  }

  depends_on = [aws_lb_listener.listener] # ensure LB is ready first
}
