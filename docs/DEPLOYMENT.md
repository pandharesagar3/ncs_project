# Deployment Guide

Reproduces the full environment in any AWS account. Estimated time: ~20–25 minutes
(Aurora cluster creation is the long pole, ~10–12 min).

## Prerequisites

- Terraform `>= 1.6.0`
- AWS CLI `v2`, configured with credentials for the target account
  (`aws configure` or an SSO profile — `aws sts get-caller-identity` should succeed)
- An IAM principal with permissions to create VPC, EC2, ASG, ELBv2, RDS/Aurora, IAM,
  KMS, S3, DynamoDB, SNS, CloudWatch, and Secrets Manager resources (broad admin access
  is simplest for a one-off deployment; a scoped policy can be derived from the resources
  in each module for a production rollout)
- (Optional) An email address to receive CloudWatch alarm notifications
- (Optional) A registered domain + ACM certificate if you want HTTPS end-to-end

## 1. Clone the repository

```bash
git clone <your-repo-url> dash-cloudops-takehome
cd dash-cloudops-takehome
```

## 2. Bootstrap the remote state backend (one-time, per AWS account)

Terraform state is kept in S3 with DynamoDB locking rather than local state, so multiple
engineers (or a future CI pipeline) can safely run `apply` against the same environment.

```bash
cd modules/state-backend
terraform init
terraform apply -var="bucket_name=dash-cloudops-tfstate-<unique-suffix>" -var="region=us-east-1"
```

Note the two outputs (`bucket_name`, `lock_table_name`) — you'll need them next.

> Bucket names are globally unique across all of AWS — pick something like
> `dash-cloudops-tfstate-<your-company>-<random-string>`.

## 3. Point the environment at that backend

Edit `environments/dev/backend.tf`:

```hcl
terraform {
  backend "s3" {
    bucket         = "dash-cloudops-tfstate-<unique-suffix>"   # from step 2
    key            = "dash-cloudops/dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "dash-cloudops-tf-locks"                  # from step 2
    encrypt        = true
  }
}
```

> Quick local test-drive without remote state? Comment out the whole `backend "s3" {}`
> block and Terraform falls back to a local `terraform.tfstate` file. Fine for a
> throwaway sandbox; switch to the S3 backend before anyone else touches this environment.

## 4. Configure variables

```bash
cd environments/dev
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` — at minimum, set `alert_email` if you want alarm notifications.
Everything else has a sensible default for a dev/demo deployment (see the file's inline
comments for what to change for a production rollout — mainly `single_nat_gateway = false`,
`db_deletion_protection = true`, `db_skip_final_snapshot = false`).

## 5. Init, plan, apply

```bash
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

Terraform will provision, in order: VPC/subnets/NAT/routing → security groups/KMS/IAM →
Aurora cluster (longest step) → ALB → Auto Scaling Group (bootstraps EC2 instances via
`scripts/user_data.sh.tpl`, which installs the app and connects it to Aurora) →
CloudWatch dashboard/alarms/SNS topic.

## 6. Confirm the SNS email subscription

If you set `alert_email`, check that inbox and click "Confirm subscription" in the email
AWS sends — alarms won't be delivered until it's confirmed.

## 7. Access the application

```bash
terraform output app_url
```

Open that URL. You should see the Increment/Decrement counter; each click also updates
"Total interactions across all users," confirming the app→database round trip is working.
It can take 1–2 minutes after `apply` completes for the first instances to pass ALB
health checks.

## 8. Where to find things afterward

```bash
terraform output                     # all outputs: ALB DNS, Aurora endpoints, dashboard name, etc.
```

- **CloudWatch dashboard**: CloudWatch console → Dashboards → `<project>-<env>-overview`
- **Logs**: CloudWatch Logs → `/aws/vpc/<project>-<env>/flow-logs`, and the Aurora
  audit/error/slowquery log groups under `/aws/rds/cluster/...`
- **DB credentials**: Secrets Manager → `<project>-<env>-db-credentials` (the EC2
  instances read this automatically at boot; you generally shouldn't need to)
- **Instance access**: `aws ssm start-session --target <instance-id>` (no SSH key needed)

## 9. Enabling HTTPS (optional)

Once you have a domain and an ACM certificate (in the same region) for it:

```hcl
enable_https        = true
acm_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/xxxxxxxx"
```

```bash
terraform apply
```

Then point a Route 53 (or your DNS provider's) `A`/`ALIAS` record at the ALB's DNS name
(`terraform output alb_dns_name`). HTTP will now 301-redirect to HTTPS.

## 10. Scaling knobs you may want to revisit for production

| Variable | Dev default | Suggested prod value | Why |
|---|---|---|---|
| `single_nat_gateway` | `true` | `false` | AZ-independent egress |
| `db_deletion_protection` | `false` | `true` | Prevent accidental cluster deletion |
| `db_skip_final_snapshot` | `true` | `false` | Guarantee a snapshot exists on teardown |
| `az_count` | `2` | `2` or `3` | 3 if SLA requires tolerating 2 simultaneous AZ issues |
| `db_reader_count` | `1` | `1`–`2`+ | More readers = more read-scaling / failover targets |
| `instance_type` | `t3.micro` | size to sustained load | burstable CPU credits can exhaust under constant load |

## 11. Tearing everything down

```bash
cd environments/dev
terraform destroy
```

If `db_deletion_protection = true` or `db_skip_final_snapshot = false`, Terraform will
require you to either take a manual final snapshot first or temporarily flip those
variables — this is deliberate friction to prevent accidental data loss in a
finance-sector context.

Finally, remove the state backend (only if you're fully done with this account):

```bash
cd modules/state-backend
terraform destroy -var="bucket_name=dash-cloudops-tfstate-<unique-suffix>" -var="region=us-east-1"
```

## 12. Recommended pre-flight checks (not automated in this take-home)

```bash
terraform fmt -recursive           # formatting
terraform validate                 # syntax/type checking, per module and root
checkov -d . --quiet               # security/best-practice static scan (pip install checkov)
```

These aren't wired into a CI pipeline here since none exists for this exercise (see
docs/ARCHITECTURE.md §11), but running them locally before every `apply` is good hygiene
and would be the first automated gate in a real CI/CD pipeline.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| ALB returns 502/503 for several minutes after apply | Instances still bootstrapping / health checks warming up | Wait 1–2 min; check `EC2 → Instance → System log` if it persists |
| `terraform apply` fails acquiring a state lock | Another run is in progress, or a previous run crashed | `terraform force-unlock <lock-id>` only after confirming no other apply is actually running |
| App loads but "Total interactions" shows "unavailable" | EC2 instance role can't reach Secrets Manager or Aurora SG doesn't allow the app SG | Check the instance's IAM role has `secretsmanager:GetSecretValue` on the DB secret, and confirm `db_sg_id` ingress rule references `app_sg_id` |
| Can't SSH to an instance | Expected — SSH is disabled by default | Use `aws ssm start-session --target <instance-id>` |
