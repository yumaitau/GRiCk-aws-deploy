mock_provider "aws" {
  override_during = plan

  mock_data "aws_availability_zones" {
    defaults = {
      names = ["ap-southeast-2a", "ap-southeast-2b"]
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:ap-southeast-2:123456789012:key/00000000-0000-0000-0000-000000000000"
    }
  }
}

mock_provider "random" {
  override_during = plan
}

variables {
  container_image       = "ghcr.io/yumaitau/grick@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  allowed_ingress_cidrs = ["203.0.113.0/24"]
  cpu_architecture      = "X86_64"
}

run "secure_test_baseline" {
  command = plan

  assert {
    condition     = aws_db_instance.this.publicly_accessible == false
    error_message = "RDS must not be publicly accessible."
  }

  assert {
    condition     = aws_ecs_task_definition.web.runtime_platform[0].cpu_architecture == "X86_64"
    error_message = "Fargate web task must explicitly target amd64."
  }

  assert {
    condition     = local.container_hardening.user == "nextjs"
    error_message = "Fargate web task must run as the image non-root user."
  }

  assert {
    condition = contains(
      local.container_hardening.linuxParameters.capabilities.drop,
      "ALL",
    )
    error_message = "Fargate web task must drop all Linux capabilities."
  }

  assert {
    condition     = local.container_hardening.linuxParameters.initProcessEnabled == true
    error_message = "Fargate tasks must enable the init process so orphaned children are reaped."
  }

  assert {
    condition = (
      local.container_hardening.linuxParameters.capabilities.add == [] &&
      local.container_hardening.mountPoints == [] &&
      local.container_hardening.portMappings == [] &&
      local.container_hardening.systemControls == [] &&
      local.container_hardening.volumesFrom == []
    )
    error_message = "Fargate task JSON must include ECS-normalized empty collections to prevent perpetual task definition replacement."
  }

  assert {
    condition = anytrue([
      for variable in local.common_environment :
      variable.name == "HOSTNAME" && variable.value == "0.0.0.0"
    ])
    error_message = "Fargate web task must bind Next.js to all interfaces so loopback health checks work."
  }

  assert {
    condition = anytrue([
      for variable in local.common_environment :
      variable.name == "SIGNUP_MODE" && variable.value == "open"
    ])
    error_message = "Fargate tasks must allow the first administrator to self-register."
  }

  assert {
    condition = anytrue([
      for variable in local.common_environment :
      variable.name == "NEXT_PUBLIC_SIGNUP_MODE" && variable.value == "open"
    ])
    error_message = "Fargate tasks must advertise open sign-up for the first administrator."
  }

  assert {
    condition     = aws_ecs_service.web[0].network_configuration[0].assign_public_ip == false
    error_message = "Web tasks must not receive public IPs."
  }

  assert {
    condition     = aws_ecs_service.web[0].deployment_circuit_breaker[0].enable && !aws_ecs_service.web[0].deployment_circuit_breaker[0].rollback
    error_message = "First-create services must not request circuit-breaker rollback; ECS has no prior revision."
  }

  assert {
    condition     = aws_s3_bucket_public_access_block.evidence.block_public_policy
    error_message = "Evidence bucket must block public policies."
  }

  assert {
    condition     = length(aws_guardduty_malware_protection_plan.evidence) == 1
    error_message = "Secure baseline must enable GuardDuty Malware Protection for the evidence bucket."
  }

  assert {
    condition     = aws_guardduty_malware_protection_plan.evidence[0].protected_resource[0].s3_bucket[0].object_prefixes == toset(["ato-evidence/"])
    error_message = "GuardDuty Malware Protection must be scoped to the evidence object prefix."
  }

  assert {
    condition     = aws_guardduty_malware_protection_plan.evidence[0].actions[0].tagging[0].status == "ENABLED"
    error_message = "GuardDuty must tag objects so GRiCk can release or quarantine evidence."
  }

  assert {
    condition = anytrue([
      for variable in local.common_environment :
      variable.name == "EVIDENCE_MALWARE_SCAN_MODE" && variable.value == "storage"
    ])
    error_message = "Fargate tasks must consume storage malware scan tags when protection is enabled."
  }

  assert {
    condition     = aws_elasticache_replication_group.this.transit_encryption_enabled
    error_message = "Redis traffic must require TLS."
  }

  assert {
    condition     = aws_elasticache_replication_group.this.parameter_group_name == aws_elasticache_parameter_group.this.name
    error_message = "ElastiCache must use the BullMQ queue parameter group."
  }

  assert {
    condition     = aws_elasticache_replication_group.this.snapshot_retention_limit == 1
    error_message = "ElastiCache must retain at least one daily snapshot by default."
  }

  assert {
    condition = anytrue([
      for parameter in aws_elasticache_parameter_group.this.parameter :
      parameter.name == "maxmemory-policy" && parameter.value == "noeviction"
    ])
    error_message = "BullMQ requires Redis maxmemory-policy=noeviction."
  }

  assert {
    condition = anytrue([
      for variable in local.common_environment :
      variable.name == "CRON_TIMEZONE" && variable.value == "Australia/Sydney"
    ])
    error_message = "Fargate tasks must set CRON_TIMEZONE for BullMQ schedulers."
  }

  assert {
    condition = alltrue([
      for rule in aws_vpc_security_group_ingress_rule.alb : rule.cidr_ipv4 != "0.0.0.0/0" && rule.cidr_ipv4 != "::/0"
    ])
    error_message = "ALB ingress must not default to the public internet."
  }

  assert {
    condition     = aws_flow_log.this.traffic_type == "ALL"
    error_message = "VPC flow logs must capture all traffic."
  }

  assert {
    condition     = aws_lb.web.access_logs[0].enabled
    error_message = "ALB access logs must be enabled."
  }

  assert {
    condition     = aws_cloudwatch_metric_alarm.alb_unhealthy.threshold == 0
    error_message = "Unhealthy-host alarm must fire on any unhealthy target."
  }

  assert {
    condition     = aws_sns_topic.alarms.kms_master_key_id == aws_kms_key.this.arn
    error_message = "CloudWatch alarm notifications must use the stack customer-managed key."
  }

  assert {
    condition = anytrue([
      for rule in aws_wafv2_web_acl.this[0].rule : rule.name == "AWSManagedRulesAnonymousIpList"
    ])
    error_message = "WAF must include the Anonymous IP managed rule group."
  }
}

run "guardduty_explicit_opt_out" {
  command = plan

  variables {
    enable_guardduty_malware_protection = false
  }

  assert {
    condition     = length(aws_guardduty_malware_protection_plan.evidence) == 0
    error_message = "Explicit GuardDuty opt-out must omit the malware protection plan."
  }

  assert {
    condition = anytrue([
      for variable in local.common_environment :
      variable.name == "EVIDENCE_MALWARE_SCAN_MODE" && variable.value == "off"
    ])
    error_message = "Explicit GuardDuty opt-out must disable storage scan-tag enforcement."
  }
}

run "reject_world_open_ingress" {
  command = plan

  variables {
    allowed_ingress_cidrs = ["0.0.0.0/0"]
  }

  expect_failures = [aws_vpc_security_group_ingress_rule.alb]
}

run "allow_world_open_ingress_when_explicit" {
  command = plan

  variables {
    allowed_ingress_cidrs  = ["0.0.0.0/0"]
    allow_internet_ingress = true
  }

  assert {
    condition = anytrue([
      for rule in aws_vpc_security_group_ingress_rule.alb : rule.cidr_ipv4 == "0.0.0.0/0"
    ])
    error_message = "allow_internet_ingress must be able to open the ALB when the buyer opts in."
  }
}

run "migration_only_bootstrap" {
  command = plan

  variables {
    enable_services = false
  }

  assert {
    condition     = length(aws_ecs_service.web) == 0 && length(aws_ecs_service.worker) == 0
    error_message = "Bootstrap must be able to run migration before services exist."
  }

  assert {
    condition     = length(aws_cloudwatch_metric_alarm.web_cpu) == 0
    error_message = "ECS CPU alarms must wait until services exist."
  }
}

run "marketplace_identity_is_not_buyer_configurable" {
  command = plan

  variables {
    marketplace_product_code              = "buyer-forged-product-code"
    marketplace_product_sku               = "buyer-forged-product-sku"
    marketplace_enforce_container_license = false
  }

  assert {
    condition     = length(local.marketplace_environment) == 0
    error_message = "Marketplace product identity and license flags must not be injected into the task environment."
  }

  assert {
    condition = !anytrue([
      for variable in concat(local.common_environment, local.marketplace_environment) :
      contains([
        "AWS_MARKETPLACE_ENFORCE_CONTAINER_LICENSE",
        "AWS_MARKETPLACE_PRODUCT_CODE",
        "AWS_MARKETPLACE_PRODUCT_SKU",
        "AWS_MARKETPLACE_ENABLED",
      ], variable.name)
    ])
    error_message = "Buyer environment must not include Marketplace license controls."
  }

  assert {
    condition     = aws_ecs_service.web[0].deployment_circuit_breaker[0].enable && !aws_ecs_service.web[0].deployment_circuit_breaker[0].rollback
    error_message = "First-create services must not request circuit-breaker rollback."
  }
}

run "reject_latest_image" {
  command = plan

  variables {
    container_image = "ghcr.io/yumaitau/grick:latest"
  }

  expect_failures = [var.container_image]
}

run "reject_unproven_region" {
  command = plan

  variables {
    aws_region = "eu-west-2"
  }

  expect_failures = [var.aws_region]
}

run "reject_fractional_cache_snapshot_retention" {
  command = plan

  variables {
    cache_snapshot_retention_days = 0.5
  }

  expect_failures = [var.cache_snapshot_retention_days]
}
