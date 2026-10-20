output "site_url" { value = local.public_url }
output "alb_dns_name" { value = aws_lb.api.dns_name }
output "ecs_cluster" { value = aws_ecs_cluster.main.name }
output "ecs_service" { value = aws_ecs_service.api.name }
output "log_group" { value = aws_cloudwatch_log_group.api.name }
