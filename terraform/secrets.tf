resource "random_password" "better_auth" {
  length  = 48
  special = false
}

resource "random_password" "auth" {
  length  = 48
  special = false
}

resource "random_password" "app" {
  length  = 48
  special = false
}

# Dedicated key for webhook signing secrets and connector credentials (#681). Never derived from
# the auth secrets, so rotating them leaves stored secrets readable.
resource "random_password" "workflow_webhook_encryption" {
  length  = 48
  special = false
}

# Assurance bundle integrity seal key (#547): its own value, never the auth secret.
resource "random_password" "certification_signing" {
  length  = 48
  special = false
}

# Next decodes NEXT_SERVER_ACTIONS_ENCRYPTION_KEY with atob and imports it as a
# raw AES-GCM key, so it must be base64 of 16, 24 or 32 bytes.
resource "random_bytes" "server_actions" {
  length = 32
}

resource "aws_secretsmanager_secret" "runtime" {
  name_prefix             = "${local.name}-runtime-"
  description             = "GRiCk runtime connection strings, Redis/BullMQ URL, and application secrets"
  kms_key_id              = aws_kms_key.this.arn
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "runtime" {
  secret_id = aws_secretsmanager_secret.runtime.id
  secret_string = jsonencode({
    DATABASE_URL                       = "postgresql://grickadmin:${random_password.database.result}@${aws_db_instance.this.address}:5432/grick?sslmode=require"
    REDIS_URL                          = "rediss://:${random_password.cache.result}@${aws_elasticache_replication_group.this.primary_endpoint_address}:6379"
    VALKEY_URL                         = "rediss://:${random_password.cache.result}@${aws_elasticache_replication_group.this.primary_endpoint_address}:6379"
    BETTER_AUTH_SECRET                 = random_password.better_auth.result
    AUTH_SECRET                        = random_password.auth.result
    APP_SECRET                         = random_password.app.result
    WORKFLOW_WEBHOOK_ENCRYPTION_KEY    = random_password.workflow_webhook_encryption.result
    CERTIFICATION_SIGNING_SECRET       = random_password.certification_signing.result
    NEXT_SERVER_ACTIONS_ENCRYPTION_KEY = random_bytes.server_actions.base64
  })
}

