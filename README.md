# GRiCk AWS Marketplace deploy

Public buyer artifacts for [GRiCk on AWS Marketplace](https://aws.amazon.com/marketplace/pp?sku=8pjp6r3g4mw0nfmf8imsf9z1d). Subscribe on that listing **before** you pull the image or create a stack. The publisher does not host your data.

This repository is CloudFormation, Terraform, Helm, and IAM only. The application image lives in AWS Marketplace ECR:

`709825985650.dkr.ecr.us-east-1.amazonaws.com/yuma-it/grick-aws`

AWS Marketplace always shows `docker login` + `docker pull` for container listings. That snippet only proves the subscription can pull the image. It does not create VPC, ECS, RDS, Redis, S3, or IAM. Use this repo to launch the product.

## ECS Fargate — CloudFormation (AWS Console)

No Terraform. Upload the template in the CloudFormation console or use the AWS CLI.

Creates VPC, ALB, ECS Fargate (web + worker), RDS PostgreSQL 16, ElastiCache Redis, Secrets Manager, KMS, and a private S3 evidence bucket. The ECS task role already has S3, KMS, and License Manager `CheckoutLicense`.

```sh
git clone https://github.com/yumaitau/GRiCk-aws-deploy.git
cd GRiCk-aws-deploy/cloudformation
```

Console: Create stack → Upload `grick-fargate.yaml` → set **ContainerImage**, **MarketplaceProductCode**, **MarketplaceProductSku** from the listing → acknowledge IAM → Create.

CLI:

```sh
cp parameters.example.json parameters.json
# edit product code, product ID, image

aws cloudformation create-stack \
  --stack-name grick \
  --template-body file://grick-fargate.yaml \
  --capabilities CAPABILITY_IAM \
  --parameters file://parameters.json
```

Open the `ApplicationUrl` output. First user registers at `/sign-up`, then creates the organisation at `/onboarding`. No seed admin is baked into the image.

HTTPS later: ACM certificate in the ALB Region, then set `CertificateArn` and `AppUrl`. TLS terminates on the ALB. It is not an extra IAM role.

Outbound email later: verify an Amazon SES identity, then set `SesFromEmail`.

Details: [`cloudformation/README.md`](cloudformation/README.md).

## ECS Fargate — Terraform

Same stack as CloudFormation if you already use Terraform.

```sh
git clone https://github.com/yumaitau/GRiCk-aws-deploy.git
cd GRiCk-aws-deploy/terraform
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

1. Pin `container_image` to this listing’s tag or digest (example uses `:1.0.1`).
2. Set `marketplace_product_code` and `marketplace_product_sku` from the listing. Empty values disable the license check and Marketplace tasks will fail checkout.
3. Leave `certificate_arn` and `ses_from_email` empty for a first HTTP launch without mail.

```sh
terraform init
terraform apply -var-file=terraform.tfvars
terraform output application_url
```

Optional: `./bootstrap.sh -var-file=terraform.tfvars` runs migration and an S3 write-proof before starting services. Ordinary `terraform apply` is enough.

Full variable notes: [`terraform/README.md`](terraform/README.md). Dual-NAT (per-AZ egress) is Terraform-only.

## Amazon EKS

Helm does **not** create RDS, Redis, or S3. Provision those plus an IRSA role first, then:

```sh
helm upgrade --install grick charts/grick --namespace grick --create-namespace \
  -f charts/grick/values-aws-marketplace.yaml \
  --set env.AWS_MARKETPLACE_PRODUCT_CODE=<product-code> \
  --set env.AWS_MARKETPLACE_PRODUCT_SKU=<product-id> \
  --set env.EVIDENCE_STORAGE_PROVIDER=s3 \
  --set env.EVIDENCE_S3_BUCKET=<your-bucket> \
  --set secretEnv.STORAGE_PROVIDER=s3
```

Attach [`iam-policy.json`](iam-policy.json) plus S3/KMS (and `ses:SendEmail` if using SES) to the IRSA role. Terminate HTTPS on your Ingress or load balancer.

## Health

- `GET /livez` — process liveness
- `GET /readyz` — configuration, database, and storage (503 if dependencies are down)

## Cost

You pay AWS directly for Fargate, ALB, NAT, RDS, ElastiCache, S3, KMS, Secrets Manager, CloudWatch, and optional WAF/Backup. Marketplace contract charges are separate.

## Destroy

CloudFormation:

```sh
aws cloudformation delete-stack --stack-name grick
```

Terraform:

```sh
cd terraform
GRICK_ALLOW_DESTROY=yes ./destroy.sh -var-file=terraform.tfvars
```

Empty the evidence bucket first if objects exist.

## Support

https://grick.snagspot.app
