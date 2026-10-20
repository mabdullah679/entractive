# Public HTTPS entry point: an API Gateway HTTP API in front of the ALB.
#
# Why not CloudFront + S3? That was built first and passed `terraform plan`, but
# AWS refused to create the distribution on this account:
#   "Your account must be verified before you can add new CloudFront resources."
# An ALB cannot terminate HTTPS without a domain + ACM certificate, and MSAL's
# PKCE flow needs a secure context, so API Gateway's built-in
# https://<id>.execute-api.<region>.amazonaws.com endpoint is the cheapest honest
# way to get a valid certificate without owning a domain. The CloudFront/S3
# version is in git history (see README).
resource "aws_apigatewayv2_api" "edge" {
  name          = "${var.name_prefix}-edge"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "alb" {
  api_id                 = aws_apigatewayv2_api.edge.id
  integration_type       = "HTTP_PROXY"
  integration_method     = "ANY"
  integration_uri        = "http://${aws_lb.api.dns_name}/{proxy}"
  payload_format_version = "1.0"
  timeout_milliseconds   = 29000
  request_parameters = {
    "overwrite:header.X-Origin-Verify" = random_password.origin_verify.result
  }
}

resource "aws_apigatewayv2_integration" "alb_root" {
  api_id                 = aws_apigatewayv2_api.edge.id
  integration_type       = "HTTP_PROXY"
  integration_method     = "ANY"
  integration_uri        = "http://${aws_lb.api.dns_name}/"
  payload_format_version = "1.0"
  timeout_milliseconds   = 29000
  request_parameters = {
    "overwrite:header.X-Origin-Verify" = random_password.origin_verify.result
  }
}

resource "aws_apigatewayv2_route" "proxy" {
  api_id    = aws_apigatewayv2_api.edge.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.alb.id}"
}

resource "aws_apigatewayv2_route" "root" {
  api_id    = aws_apigatewayv2_api.edge.id
  route_key = "ANY /"
  target    = "integrations/${aws_apigatewayv2_integration.alb_root.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.edge.id
  name        = "$default"
  auto_deploy = true
  # Abuse guard on a public demo endpoint.
  default_route_settings {
    throttling_burst_limit = 50
    throttling_rate_limit  = 25
  }
}

locals {
  public_url = trimsuffix(aws_apigatewayv2_stage.default.invoke_url, "/")
}
