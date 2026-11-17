# GRiCk on AWS ECS Fargate (CloudFormation)

Native CloudFormation for buyers who do not want Terraform. Same first-launch shape as `deploy/terraform/aws-fargate`: VPC, ALB, ECS Fargate (web + worker), RDS PostgreSQL 16, ElastiCache Redis (TLS, `maxmemory-policy=noeviction` for the BullMQ queue), Secrets Manager, KMS, a private S3 evidence bucket, and GuardDuty Malware Protection for uploaded evidence. Cron jobs run only in the worker task.

Hardening carried over from Terraform: KMS-encrypted ECS, WAF and VPC flow log groups; VPC flow logs (ALL); ALB access logs to a separate SSE-S3 logs bucket; WAF Anonymous IP, Common and Known Bad Inputs rules with WAF logging (authorization, cookie and x-api-key redacted); container init process; ECS role trust scoped by `aws:SourceAccount` and `aws:SourceArn`; SES send scoped to identities in the stack account and Region; optional RDS and ALB deletion protection.

Not in CloudFormation (Terraform only): CloudWatch alarms and the SNS topic, and per-AZ NAT. The evidence bucket logs S3 access to the logs bucket under `s3/evidence/`, as in Terraform.

The AWS Marketplace listing is planned and not yet public. Once it is public, subscribe to the listing before you create the stack. The image is Marketplace ECR, not GHCR.

Source of this template: this directory. Public copy: https://github.com/yumaitau/GRiCk-aws-deploy/tree/main/cloudformation

## Console

1. Open CloudFormation in the target Region (`ap-southeast-2` recommended; `us-east-1` for Marketplace metering proof).
2. Create stack → With new resources → Upload a template file → `grick-fargate.yaml`.
3. Set **Marketplace product code** and **product ID (SKU)** from the listing. Pin **Container image** to this listing tag or digest.
4. Set **AllowedIngressCidr** to your office, VPN or client IPv4 CIDR (required, no default). `0.0.0.0/0` is rejected unless **AllowInternetIngress** is `true`; only do that for a public service behind WAF and HTTPS.
5. Leave **ACM certificate ARN** and **SES From** empty for a first HTTP launch without mail.
6. Acknowledge IAM capabilities. Create.

When the stack is `CREATE_COMPLETE`, open the `ApplicationUrl` output. First user registers at `/sign-up`, then creates the organisation at `/onboarding`. `SignupMode` defaults to `invite_only`, which still admits that first account (bootstrap exception); colleagues then join by invitation. Choose `open` only for a deliberate public service. Consider Amazon Bedrock on that form for in-account AI (Claude in your Region via the task role): ATO explainers, risk summaries, evidence-gap review, and ITSA/CISO draft briefs. Enable the model in Bedrock model access. The stack grants the task role `bedrock:InvokeModel` unless `EnableBedrock=false`. Not required to boot.

## CLI

The template is larger than the 51,200-byte limit for `--template-body`, so upload it to an S3 bucket you own in the target Region and pass its URL.

```sh
cd cloudformation  # in a GRiCk source checkout: cd deploy/cloudformation/aws-fargate
cp parameters.example.json parameters.json
# edit MarketplaceProductCode, MarketplaceProductSku, ContainerImage, AllowedIngressCidr

TEMPLATE_BUCKET=replace-with-your-template-bucket
TEMPLATE_REGION=ap-southeast-2  # the bucket's Region
aws s3 cp grick-fargate.yaml "s3://${TEMPLATE_BUCKET}/grick-fargate.yaml"

aws cloudformation create-stack \
  --stack-name grick \
  --template-url "https://${TEMPLATE_BUCKET}.s3.${TEMPLATE_REGION}.amazonaws.com/grick-fargate.yaml" \
  --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
  --parameters file://parameters.json

aws cloudformation wait stack-create-complete --stack-name grick
aws cloudformation describe-stacks --stack-name grick \
  --query "Stacks[0].Outputs[?OutputKey=='ApplicationUrl'].OutputValue" \
  --output text
```

The image entrypoint waits for Postgres, migrates, then starts. A separate migration task definition is an output if you want an explicit pre-roll.

## Optional parameters

| Parameter | Empty default | Later |
| --- | --- | --- |
| `CertificateArn` + `AppUrl` | HTTP ALB | ACM in the ALB Region. TLS terminates on the ALB. Not an extra IAM role. HTTPS is added on 443 and port 80 then returns a 301 redirect to HTTPS. |
| `SesFromEmail` | No mail | Verified SES identity. Stack sets `EMAIL_PROVIDER=ses` and `ses:SendEmail` on the task role. |
| `DatabaseMultiAz` / `CacheHighAvailability` | Off | Production resilience. |
| `DatabaseDeletionProtection` | Off | Turns on RDS and ALB deletion protection. Enable for production. |
| `EnableAwsBackup` | Off | Daily AWS Backup of RDS + evidence bucket. |
| `EnableBedrock` | On | Grants the task role `bedrock:InvokeModel` on Anthropic Claude models so the onboarding AI default works. Set `false` to omit the grant; onboarding then leaves AI off. |
| `EnableGuardDutyMalwareProtection` | On | Scans `ato-evidence/` uploads and tags results for GRiCk quarantine handling. GuardDuty usage charges and service terms apply. |
| `AllowedIngressCidr` | Required (no default) | Office / VPN / client IPv4 CIDR. `0.0.0.0/0` needs `AllowInternetIngress=true`. |
| `AllowInternetIngress` | `false` | Set `true` only for a public service behind WAF and HTTPS. |

S3 evidence storage is always created. Dual-NAT (per-AZ egress) is Terraform-only.

With `EnableWaf` on, the WAF counts, rather than blocks, the Common Rule Set `SizeRestrictions_BODY` rule, so evidence and import uploads over 8 KB reach the app. The app refuses declared bodies over 25 MB with 413. The other Common Rule Set body rules still block.

## Destroy

Set `DatabaseDeletionProtection=false` (stack update) if you turned it on. Empty the evidence bucket if objects exist, then:

```sh
aws cloudformation delete-stack --stack-name grick
aws cloudformation wait stack-delete-complete --stack-name grick
```

RDS uses `DeletionPolicy: Snapshot` and `UpdateReplacePolicy: Snapshot`: deleting the stack, or an update that replaces the instance, leaves a final DB snapshot. The snapshot is kept (and billed) after the stack is gone; delete it in the RDS console when you no longer need it. The KMS key (`EncryptionKey`) is also retained on delete and replacement, because the snapshot and any AWS Backup recovery points cannot be restored without it; schedule its deletion in the KMS console only after you have deleted them. The ALB logs bucket is retained on delete; empty and remove it yourself when you no longer need the request history.
