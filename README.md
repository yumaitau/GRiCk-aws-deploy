# GRiCk AWS Marketplace deploy

Public buyer artifacts for [GRiCk on AWS Marketplace](https://aws.amazon.com/marketplace/pp?sku=8pjp6r3g4mw0nfmf8imsf9z1d). Subscribe on that listing **before** you pull the image or create a stack. The publisher does not host your data.

This repository is CloudFormation, Terraform, Helm, and IAM only. The application image lives in AWS Marketplace ECR:

`709825985650.dkr.ecr.us-east-1.amazonaws.com/yuma-it/grick-aws`

AWS Marketplace always shows `docker login` + `docker pull` for container listings. That snippet only proves the subscription can pull the image. It does not create VPC, ECS, RDS, Redis, S3, or IAM. Use this repo to launch the product.

The GRiCk AWS Marketplace distribution validates its AWS Marketplace entitlement at runtime with AWS License Manager `CheckoutLicense`. Marketplace licensing cannot be disabled through Docker, ECS, Terraform, Helm, or environment configuration. The ECS task role must permit the required AWS License Manager operations.

Use image **1.0.7 or newer** (`linux/amd64` + `linux/arm64`). The `1.0.3` tag is linux/arm64 only. `1.0.5` crashes on boot (`Dynamic require of "node:https"`). `1.0.6` exits after 15 minutes when it re-checkouts the one contract seat. Images `1.0.1` and `1.0.2` allowed a temporary license-disable flag and are unsupported.

## ECS Fargate — CloudFormation (AWS Console)

No Terraform. Upload the template in the CloudFormation console or use the AWS CLI.

Creates VPC, ALB, ECS Fargate (web + worker), RDS PostgreSQL 16, ElastiCache Redis, Secrets Manager, KMS, and a private S3 evidence bucket. The ECS task role already has S3, KMS, and License Manager `CheckoutLicense`.

```sh
git clone https://github.com/yumaitau/GRiCk-aws-deploy.git
cd GRiCk-aws-deploy/cloudformation
```

Console: Create stack → Upload `grick-fargate.yaml` → set **ContainerImage** to a `1.0.3+` listing tag or digest → set **AllowedIngressCidr** to your office/VPN CIDR → acknowledge IAM → Create. Do not use `0.0.0.0/0` unless **AllowInternetIngress** is true. Marketplace product-code parameters are ignored; the image already knows the GRiCk listing.

CLI:

```sh
cp parameters.example.json parameters.json
# edit image and AllowedIngressCidr

aws cloudformation deploy \
  --stack-name grick \
  --template-file grick-fargate.yaml \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides $(python3 -c 'import json; print(" ".join("%s=%s" % (p["ParameterKey"], p["ParameterValue"]) for p in json.load(open("parameters.json"))))')
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

1. Pin `container_image` to this listing’s `1.0.3+` tag or digest.
2. Set `allowed_ingress_cidrs` to your office, VPN, or client CIDR. Leave `allow_internet_ingress` false. `0.0.0.0/0` is rejected unless that flag is true.
3. Leave `certificate_arn` and `ses_from_email` empty for a first HTTP launch without mail.

Do not set `marketplace_enforce_container_license`, `AWS_MARKETPLACE_ENFORCE_CONTAINER_LICENSE`, or buyer-supplied product codes. Those values cannot disable licensing on 1.0.3+.

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
  --set env.EVIDENCE_STORAGE_PROVIDER=s3 \
  --set env.EVIDENCE_S3_BUCKET=<your-bucket> \
  --set secretEnv.STORAGE_PROVIDER=s3
```

Attach [`iam-policy.json`](iam-policy.json) plus S3/KMS (and `ses:SendEmail` if using SES) to the IRSA role. Terminate HTTPS on your Ingress or load balancer.

## Upgrade from 1.0.1 / 1.0.2

Those images could skip `CheckoutLicense` when `AWS_MARKETPLACE_ENFORCE_CONTAINER_LICENSE=false`. That path is removed.

1. Subscribe (or keep an active subscription) in the buyer account.
2. Confirm the ECS task role / IRSA role still allows `license-manager:CheckoutLicense` and the other actions in `iam-policy.json`.
3. Pin `container_image` / Helm `image.tag` to **1.0.7 or newer**.
4. Apply this repository. Existing `marketplace_*` Terraform/CloudFormation values are ignored and can stay in old variable files.
5. New tasks must pass entitlement validation before they serve traffic.

If a 1.0.3+ task starts without a valid entitlement, it exits with a non-zero status and does not serve GRiCk.

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
