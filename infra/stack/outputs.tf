output "site_url" { value = "https://${aws_cloudfront_distribution.main.domain_name}" }
output "cloudfront_domain" { value = aws_cloudfront_distribution.main.domain_name }
output "cloudfront_distribution_id" { value = aws_cloudfront_distribution.main.id }
output "spa_bucket" { value = aws_s3_bucket.spa.bucket }
output "alb_dns_name" { value = aws_lb.api.dns_name }
output "ecs_cluster" { value = aws_ecs_cluster.main.name }
output "ecs_service" { value = aws_ecs_service.api.name }
output "log_group" { value = aws_cloudwatch_log_group.api.name }
