locals {
  ssm_prefix = "/${var.name_prefix}"
  image      = "${data.aws_ecr_repository.api.repository_url}:${var.image_tag}"
}

data "aws_ecr_repository" "api" {
  name = "${var.name_prefix}-resource-server"
}

# Owned by the bootstrap stack and by the operator (values are Entra IDs).
data "aws_ssm_parameter" "entra" {
  for_each = toset(["tenant-id", "spa-client-id", "api-client-id", "api-scope"])
  name     = "${local.ssm_prefix}/${each.key}"
}

# Shared secret between API Gateway and the ALB: the ALB only forwards requests
# that carry it, so hitting the ALB's public DNS name directly gets a 403.
resource "random_password" "origin_verify" {
  length  = 40
  special = false
}

resource "aws_cloudwatch_log_group" "api" {
  name              = "/ecs/${var.name_prefix}-resource-server"
  retention_in_days = 7
}

# ---- ALB -------------------------------------------------------------------
resource "aws_lb" "api" {
  name                       = "${var.name_prefix}-alb"
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.alb.id]
  subnets                    = aws_subnet.public[*].id
  drop_invalid_header_fields = true
  idle_timeout               = 60
}

resource "aws_lb_target_group" "api" {
  name                 = "${var.name_prefix}-tg"
  port                 = 8080
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = aws_vpc.main.id
  deregistration_delay = 15
  health_check {
    path                = "/actuator/health/readiness"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.api.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "forbidden"
      status_code  = "403"
    }
  }
}

resource "aws_lb_listener_rule" "from_gateway" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
  condition {
    http_header {
      http_header_name = "X-Origin-Verify"
      values           = [random_password.origin_verify.result]
    }
  }
  condition {
    path_pattern {
      values = ["/*"]
    }
  }
}

# ---- ECS -------------------------------------------------------------------
resource "aws_ecs_cluster" "main" {
  name = "${var.name_prefix}-cluster"
}

data "aws_iam_policy_document" "ecs_tasks_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task_execution" {
  name                 = "${var.name_prefix}-task-exec"
  assume_role_policy   = data.aws_iam_policy_document.ecs_tasks_trust.json
  permissions_boundary = "arn:aws:iam::${data.aws_caller_identity.me.account_id}:policy/portfolio-ci-boundary"
}

data "aws_caller_identity" "me" {}

resource "aws_iam_role_policy_attachment" "task_execution" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "task_execution_ssm" {
  statement {
    actions   = ["ssm:GetParameters"]
    resources = [for p in data.aws_ssm_parameter.entra : p.arn]
  }
}

resource "aws_iam_role_policy" "task_execution_ssm" {
  name   = "read-entra-ids"
  role   = aws_iam_role.task_execution.id
  policy = data.aws_iam_policy_document.task_execution_ssm.json
}

resource "aws_ecs_task_definition" "api" {
  family                   = "${var.name_prefix}-resource-server"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.task_execution.arn
  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }
  container_definitions = jsonencode([{
    name         = "resource-server"
    image        = local.image
    essential    = true
    portMappings = [{ containerPort = 8080, protocol = "tcp" }]
    # Runs as uid 10001 (Dockerfile.aws). The entrypoint writes /app/spa/config.js
    # at start, so the root filesystem stays writable.
    stopTimeout = 30
    environment = [
      { name = "CORS_ALLOWED_ORIGINS", value = local.public_url },
      { name = "PUBLIC_URL", value = local.public_url },
      { name = "AZURE_REQUIRED_ROLE", value = var.required_role },
      { name = "LOGGING_LEVEL_ORG_SPRINGFRAMEWORK_SECURITY_OAUTH2_SERVER_RESOURCE", value = "INFO" },
    ]
    secrets = [
      { name = "AZURE_TENANT_ID", valueFrom = data.aws_ssm_parameter.entra["tenant-id"].arn },
      { name = "AZURE_CLIENT_ID", valueFrom = data.aws_ssm_parameter.entra["api-client-id"].arn },
      { name = "SPA_CLIENT_ID", valueFrom = data.aws_ssm_parameter.entra["spa-client-id"].arn },
      { name = "API_SCOPE", valueFrom = data.aws_ssm_parameter.entra["api-scope"].arn },
    ]
    healthCheck = {
      command     = ["CMD-SHELL", "curl -fsS http://127.0.0.1:8080/actuator/health/liveness | grep -q UP || exit 1"]
      interval    = 15
      timeout     = 5
      retries     = 3
      startPeriod = 90
    }
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.api.name
        awslogs-region        = "ap-southeast-2"
        awslogs-stream-prefix = "api"
      }
    }
  }])
}

resource "aws_ecs_service" "api" {
  name                               = "${var.name_prefix}-resource-server"
  cluster                            = aws_ecs_cluster.main.id
  task_definition                    = aws_ecs_task_definition.api.arn
  desired_count                      = var.desired_count
  launch_type                        = "FARGATE"
  health_check_grace_period_seconds  = 120
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  wait_for_steady_state              = true
  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }
  network_configuration {
    subnets          = aws_subnet.public[*].id
    security_groups  = [aws_security_group.task.id]
    assign_public_ip = true
  }
  load_balancer {
    target_group_arn = aws_lb_target_group.api.arn
    container_name   = "resource-server"
    container_port   = 8080
  }
  depends_on = [aws_lb_listener_rule.from_gateway]
}
