output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  value = module.vpc.public_subnets
}

output "private_subnet_ids" {
  value = module.vpc.private_subnets
}

output "service_urls" {
  description = "Public URLs for each service"
  value = {
    for repo, alb in aws_lb.alb : repo => "http://${alb.dns_name}"
  }
}

output "task_security_group_id" { value = aws_security_group.task.id }
