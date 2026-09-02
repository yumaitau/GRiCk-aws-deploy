output "application_url" {
  description = "Public GRiCk URL."
  value       = local.application_url
}

output "container_image" {
  description = "Immutable image reference used by every task definition."
  value       = var.container_image
}

output "migration_log_group_name" {
  description = "CloudWatch log group for migration and storage proof tasks."
  value       = aws_cloudwatch_log_group.migration.name
}

output "load_balancer_dns_name" {
  description = "ALB DNS name."
  value       = aws_lb.web.dns_name
}

output "ecs_cluster_name" {
  description = "ECS cluster used by services and one-shot tasks."
  value       = aws_ecs_cluster.this.name
}

output "web_task_definition_arn" {
  description = "Pinned web task definition revision."
  value       = aws_ecs_task_definition.web.arn
}

output "worker_task_definition_arn" {
  description = "Pinned worker task definition revision."
  value       = aws_ecs_task_definition.worker.arn
}

output "migration_task_definition_arn" {
  description = "One-shot migration task definition revision."
  value       = aws_ecs_task_definition.migration.arn
}

output "web_service_arn" {
  description = "Web ECS service ARN, or null during migration-only bootstrap."
  value       = try(aws_ecs_service.web[0].id, null)
}

output "worker_service_arn" {
  description = "Worker ECS service ARN, or null during migration-only bootstrap."
  value       = try(aws_ecs_service.worker[0].id, null)
}

output "application_subnet_ids" {
  description = "Private subnets for Fargate tasks."
  value       = aws_subnet.application[*].id
}

output "task_security_group_id" {
  description = "Security group for Fargate tasks."
  value       = aws_security_group.tasks.id
}

output "database_endpoint" {
  description = "Private RDS endpoint."
  value       = aws_db_instance.this.endpoint
}

output "cache_endpoint" {
  description = "Private TLS Redis/BullMQ primary endpoint."
  value       = "${aws_elasticache_replication_group.this.primary_endpoint_address}:6379"
}

output "evidence_bucket_name" {
  description = "Private KMS-encrypted S3 evidence bucket."
  value       = aws_s3_bucket.evidence.id
}

output "guardduty_malware_protection_plan_arn" {
  description = "GuardDuty Malware Protection for S3 plan ARN, or null when explicitly disabled."
  value       = try(aws_guardduty_malware_protection_plan.evidence[0].arn, null)
}

output "guardduty_malware_protection_status" {
  description = "GuardDuty Malware Protection for S3 plan status, or DISABLED when explicitly disabled."
  value       = try(aws_guardduty_malware_protection_plan.evidence[0].status, "DISABLED")
}

output "kms_key_arn" {
  description = "KMS key used by the ECS workload for evidence and CMK envelope operations."
  value       = aws_kms_key.this.arn
}

output "runtime_secret_arn" {
  description = "Secrets Manager ARN referenced by task definitions. Secret values are never output."
  value       = aws_secretsmanager_secret.runtime.arn
}

output "aws_account_id" {
  description = "Account that owns this deployment."
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "Deployment region."
  value       = var.aws_region
}

output "stack_name" {
  description = "Name prefix used for the ECS cluster and log groups."
  value       = local.name
}

output "marketplace_product_sku" {
  description = "Deprecated. GRiCk 1.0.3+ embeds ProductSKU prod-vgebc2b2lowoq in the Marketplace image."
  value       = "prod-vgebc2b2lowoq"
}

output "marketplace_license_enforcement" {
  description = "Marketplace images 1.0.3+ always enforce CheckoutLicense. Deployment configuration cannot disable it."
  value       = "mandatory"
}
