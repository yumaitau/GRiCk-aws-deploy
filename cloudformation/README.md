# GRiCk on AWS ECS Fargate (CloudFormation)

Native CloudFormation for buyers who do not want Terraform. Same first-launch shape as the Terraform stack in this repo: VPC, ALB, ECS Fargate (web + worker), RDS PostgreSQL 16, ElastiCache Redis (TLS), Secrets Manager, KMS, and a private S3 evidence bucket.

Subscribe at https://aws.amazon.com/marketplace/pp?sku=8pjp6r3g4mw0nfmf8imsf9z1d before you create the stack. The image is Marketplace ECR, not GHCR.

## Console

1. Open CloudFormation in the target Region (`ap-southeast-2` recommended; `us-east-1` for Marketplace metering proof).
2. Create stack → With new resources → Upload a template file → `grick-fargate.yaml`.
3. Set **Marketplace product code** and **product ID (SKU)** from the listing. Pin **Container image** to this listing tag or digest.
4. Leave **ACM certificate ARN** and **SES From** empty for a first HTTP launch without mail.
5. Acknowledge IAM capabilities. Create.

When the stack is `CREATE_COMPLETE`, open the `ApplicationUrl` output. First user registers at `/sign-up`, then creates the organisation at `/onboarding`.

## CLI

```sh
cd cloudformation
cp parameters.example.json parameters.json
# edit MarketplaceProductCode, MarketplaceProductSku, ContainerImage

aws cloudformation create-stack \
  --stack-name grick \
  --template-body file://grick-fargate.yaml \
  --capabilities CAPABILITY_IAM \
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
| `CertificateArn` + `AppUrl` | HTTP ALB | ACM in the ALB Region. TLS terminates on the ALB. Not an extra IAM role. HTTP still forwards to the target group; HTTPS is added on 443. |
| `SesFromEmail` | No mail | Verified SES identity. Stack sets `EMAIL_PROVIDER=ses` and `ses:SendEmail` on the task role. |
| `DatabaseMultiAz` / `CacheHighAvailability` | Off | Production resilience. |
| `EnableAwsBackup` | Off | Daily AWS Backup of RDS + evidence bucket. |
| `AllowedIngressCidr` | `0.0.0.0/0` | Narrow to your office / VPN. |

S3 evidence storage is always created. Dual-NAT (per-AZ egress) is Terraform-only.

## Destroy

Empty the evidence bucket first if objects exist, then:

```sh
aws cloudformation delete-stack --stack-name grick
aws cloudformation wait stack-delete-complete --stack-name grick
```

RDS uses `DeletionPolicy: Delete` (no final snapshot) to match the Terraform test teardown. Change that in a fork before production data.
