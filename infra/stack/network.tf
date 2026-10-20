# Own VPC, two public subnets (an ALB needs two AZs). No NAT gateway: Fargate
# tasks get public IPs for outbound-only traffic (ECR, SSM, CloudWatch, Entra
# JWKS) and accept inbound ONLY from the ALB security group.
data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.43.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "${var.name_prefix}-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.name_prefix}-igw" }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false
  tags                    = { Name = "${var.name_prefix}-public-${count.index}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
  tags = { Name = "${var.name_prefix}-public" }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Lock the default SG of this VPC down to nothing.
resource "aws_default_security_group" "default" {
  vpc_id = aws_vpc.main.id
}

# NOTE: description is immutable in AWS (changing it forces SG replacement), so it
# keeps its original text even though the edge is now API Gateway; see the rule below.
resource "aws_security_group" "alb" {
  name        = "${var.name_prefix}-alb"
  description = "ALB: HTTP from CloudFront origin-facing IPs only"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${var.name_prefix}-alb" }
}

# API Gateway HTTP APIs call a public ALB from AWS-owned addresses that are not
# published, so the network layer cannot be narrowed further. The ALB listener's
# default action is a 403; only requests carrying the secret header API Gateway
# injects are forwarded (see api.tf). smoke.sh proves the direct-hit 403.
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  description       = "HTTP; gated by header secret at the listener"
}

resource "aws_security_group" "task" {
  name        = "${var.name_prefix}-task"
  description = "Resource server: 8080 from the ALB only"
  vpc_id      = aws_vpc.main.id
  tags        = { Name = "${var.name_prefix}-task" }
}

resource "aws_vpc_security_group_ingress_rule" "task_from_alb" {
  security_group_id            = aws_security_group.task.id
  referenced_security_group_id = aws_security_group.alb.id
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
}

resource "aws_vpc_security_group_egress_rule" "alb_to_task" {
  security_group_id            = aws_security_group.alb.id
  referenced_security_group_id = aws_security_group.task.id
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
}

resource "aws_vpc_security_group_egress_rule" "task_https_out" {
  security_group_id = aws_security_group.task.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  description       = "ECR, SSM, CloudWatch Logs, Entra JWKS"
}
