# Bootstrap - Terraform Remote State Backend

## Purpose

This directory solves the chicken-and-egg problem of Terraform remote state:
you cannot store Terraform state in an S3 bucket until that bucket exists, but
you need Terraform to create the bucket. Bootstrap runs **once** with local
state to create the backend, after which every other configuration in this
project uses remote state stored in that bucket.

## Resources created

| Resource | Name | Purpose |
|---|---|---|
| S3 Bucket | `var.state_bucket_name` | Stores all Terraform remote state files for this project |
| DynamoDB Table | `cloud-ops-lab-tf-locks` | Provides state locking to prevent concurrent apply conflicts |

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5.0 installed
- AWS CLI configured with credentials that have permission to create S3 buckets and DynamoDB tables
- A globally unique S3 bucket name chosen (S3 names are shared across all AWS accounts)

## One-time setup

```bash
cd bootstrap

terraform init

terraform plan -var="state_bucket_name=<your-unique-bucket-name>"

terraform apply -var="state_bucket_name=<your-unique-bucket-name>"
```

After apply completes, note the output values:

```
state_bucket_name = "<your-unique-bucket-name>"
lock_table_name   = "cloud-ops-lab-tf-locks"
```

Use these values in `environments/dev/backend.tf`.

## Important warnings

- **Do not run `terraform destroy` in this directory** while any environment
  is using the remote backend. Destroying the S3 bucket deletes all state
  files, which means Terraform loses track of every resource it has deployed.
- The S3 bucket has `prevent_destroy = true` as a safeguard, but this only
  protects against `terraform destroy` — it does not protect against manual
  deletion via the AWS Console or CLI.
- This directory uses **local state** intentionally. The `terraform.tfstate`
  file generated here should not be committed to version control. It is
  excluded by the root `.gitignore`.

## Why local state here?

All other environments in this project use remote state stored in the S3
bucket this directory creates. Bootstrap itself cannot use that bucket as a
backend before the bucket exists, so local state is the only option for this
one configuration. Once bootstrap has been applied, its local state file is
safe to keep on your machine but is not needed for day-to-day operations.
