# CloudWatch cannot use alias/aws/sns: grant the alarm service access to
# a customer-managed key, scoped to alarms from this account.
data "aws_iam_policy_document" "alarm_kms" {
  # checkov:skip=CKV_AWS_111:KMS key policies require Resource * on the key itself
  # checkov:skip=CKV_AWS_109:Account-root EnableIAM is the AWS default key-policy statement
  # checkov:skip=CKV_AWS_356:KMS key policies require Resource * on the key itself
  statement {
    sid = "EnableAccountPermissions"
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid = "CloudWatchAlarmDelivery"
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
    actions   = ["kms:Decrypt", "kms:GenerateDataKey*"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:cloudwatch:${var.aws_region}:${data.aws_caller_identity.current.account_id}:alarm:*"]
    }
  }
}

resource "aws_kms_key" "alarms" {
  description             = "GRiCk CloudWatch alarm delivery to SNS"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.alarm_kms.json
}

resource "aws_sns_topic" "alarms" {
  name              = "${local.name}-alarms"
  kms_master_key_id = aws_kms_key.alarms.arn
}

data "aws_iam_policy_document" "alarm_topic" {
  statement {
    sid = "CloudWatchAlarmDelivery"
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alarms.arn]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:cloudwatch:${var.aws_region}:${data.aws_caller_identity.current.account_id}:alarm:*"]
    }
  }
}

resource "aws_sns_topic_policy" "alarms" {
  arn    = aws_sns_topic.alarms.arn
  policy = data.aws_iam_policy_document.alarm_topic.json
}

resource "aws_sns_topic_subscription" "alarms_email" {
  count = var.alarm_notification_email == "" ? 0 : 1

  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_notification_email
}

resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "${local.name}-alb-5xx"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Sum"
  threshold           = 5
  alarm_description   = "GRiCk ALB targets are returning 5xx responses."
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    LoadBalancer = aws_lb.web.arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "alb_unhealthy" {
  alarm_name          = "${local.name}-alb-unhealthy"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Average"
  threshold           = 0
  alarm_description   = "GRiCk web target group has unhealthy hosts."
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    LoadBalancer = aws_lb.web.arn_suffix
    TargetGroup  = aws_lb_target_group.web.arn_suffix
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_storage" {
  alarm_name          = "${local.name}-rds-free-storage"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 2147483648
  alarm_description   = "GRiCk RDS free storage is below 2 GiB."
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.this.id
  }
}

resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${local.name}-rds-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "GRiCk RDS CPU is above 80 percent."
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    DBInstanceIdentifier = aws_db_instance.this.id
  }
}

resource "aws_cloudwatch_metric_alarm" "web_cpu" {
  count = var.enable_services ? 1 : 0

  alarm_name          = "${local.name}-web-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "GRiCk web service CPU is above 80 percent."
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    ClusterName = aws_ecs_cluster.this.name
    ServiceName = aws_ecs_service.web[0].name
  }
}

resource "aws_cloudwatch_metric_alarm" "worker_cpu" {
  count = var.enable_services ? 1 : 0

  alarm_name          = "${local.name}-worker-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "GRiCk worker service CPU is above 80 percent."
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alarms.arn]
  ok_actions          = [aws_sns_topic.alarms.arn]

  dimensions = {
    ClusterName = aws_ecs_cluster.this.name
    ServiceName = aws_ecs_service.worker[0].name
  }
}
