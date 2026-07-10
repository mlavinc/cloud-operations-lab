# Cloud Operations Lab

A production-style AWS infrastructure project built to demonstrate real Cloud Engineering skills: Infrastructure as Code, automated monitoring, operational automation, and a full CI/CD deployment pipeline with manual approval gates.

Built incrementally across five sprints, each adding a production capability layer on top of the last.

---

## What This Project Demonstrates

| Skill | Implementation |
|---|---|
| Infrastructure as Code | Terraform with modular structure and remote state |
| Cloud Networking | VPC, subnets, Internet Gateway, route tables |
| Compute | EC2 on Amazon Linux 2023 with IMDSv2 |
| Secure Access | SSM Session Manager (no SSH, no key pairs, no open port 22) |
| IAM | Least-privilege roles, scoped inline policies, instance profiles |
| Observability | CloudWatch Agent, log groups, CPU alarms, SNS email alerts |
| Operational Automation | SSM Run Command documents, bash scripts, DynamoDB event log |
| CI/CD | GitHub Actions with OIDC authentication — no long-lived AWS credentials |
| Deployment Control | GitHub Environments, manual approval gate before `terraform apply` |
| Security | OIDC trust conditions scoped to specific environments, `iam:PassRole` scoped to EC2 |

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                        AWS Account                       │
│                                                          │
│  ┌──────────────────────────────────────────────────┐   │
│  │  VPC  10.0.0.0/16                                │   │
│  │                                                  │   │
│  │  ┌────────────────────────────────────────────┐  │   │
│  │  │  Public Subnet  10.0.1.0/24                │  │   │
│  │  │                                            │  │   │
│  │  │  ┌──────────────────────────────────────┐  │  │   │
│  │  │  │  EC2  t3.micro  Amazon Linux 2023    │  │  │   │
│  │  │  │  - CloudWatch Agent                  │  │  │   │
│  │  │  │  - SSM Session Manager access        │  │  │   │
│  │  │  │  - IAM Instance Profile              │  │  │   │
│  │  │  └──────────────────────────────────────┘  │  │   │
│  │  │                                            │  │   │
│  │  └──────────────────── IGW ───────────────────┘  │   │
│  └──────────────────────────────────────────────────┘   │
│                                                          │
│  CloudWatch          DynamoDB              SSM           │
│  ┌──────────┐       ┌──────────┐       ┌──────────┐     │
│  │ Log Group│       │ ops-logs │       │ Parameter│     │
│  │ CPU Alarm│       │  table   │       │  Store   │     │
│  │ SNS Topic│       │          │       │ Documents│     │
│  └──────────┘       └──────────┘       └──────────┘     │
│                                                          │
│  S3 (Terraform state)    DynamoDB (Terraform locks)      │
└─────────────────────────────────────────────────────────┘
```

---

## Repository Structure

```
cloud-operations-lab/
├── bootstrap/                  # One-time account setup (local state)
│   ├── main.tf                 # S3 state bucket, DynamoDB lock table, GitHub OIDC
│   ├── variables.tf
│   ├── outputs.tf
│   ├── terraform.tfvars        # Your values (gitignored)
│   └── terraform.tfvars.example
│
├── modules/                    # Reusable building blocks
│   ├── vpc/                    # VPC, subnet, IGW, route table, security group
│   ├── iam/                    # EC2 role, instance profile, scoped policies
│   ├── ec2/                    # Instance, AMI data source, CloudWatch agent user_data
│   ├── cloudwatch/             # Log group, CPU alarm, SNS topic
│   ├── dynamodb/               # Ops-logs table (PK: instance_id, SK: log_timestamp)
│   └── ssm/                    # Parameter Store config, Run Command documents
│
├── environments/
│   └── dev/                    # Dev environment composition
│       ├── backend.tf          # S3 remote state configuration
│       ├── providers.tf        # AWS provider with default_tags
│       ├── main.tf             # Wires all modules together
│       ├── variables.tf
│       ├── outputs.tf
│       └── dev.tfvars          # Environment values
│
├── scripts/
│   └── bash/
│       ├── health_check.sh     # Collects instance metrics → DynamoDB
│       └── log_event.sh        # Writes a named event → DynamoDB
│
└── .github/
    └── workflows/
        ├── terraform-plan.yml  # Runs on Pull Requests (fmt, init, validate, plan)
        └── terraform-apply.yml # Runs on merge to main with manual approval
```

---

## CI/CD Pipeline

The deployment workflow is designed to resemble how a real Cloud Engineering team operates.

```
Developer
    │
    ▼
Pull Request
    │
    ├── terraform fmt   (fails if code is not formatted)
    ├── terraform init
    ├── terraform validate
    └── terraform plan  (output posted as PR comment)
    │
    ▼
Code Review + Plan Review
    │
    ▼
Merge to main
    │
    ▼
terraform-apply.yml triggered
    │
    ▼  ← GitHub Environment "dev" — pauses here
Manual Approval (required reviewer clicks Approve)
    │
    ▼
terraform apply
```

### Why OIDC instead of AWS Access Keys

GitHub OIDC lets GitHub Actions request a short-lived AWS credential scoped to a specific job, without any long-lived secret stored anywhere. The credential expires when the job ends. There is nothing to rotate, nothing to leak.

### Two separate IAM roles

| Role | Trust condition | Permissions |
|---|---|---|
| `github-ci` | Any ref in this repository | `ReadOnlyAccess` + state backend |
| `github-apply` | Only jobs running in `environment: dev` | Custom write policy + state backend |

The apply role cannot be assumed by a PR workflow because a PR job has a different OIDC `sub` claim (`ref:refs/heads/...`) than an environment job (`environment:dev`). This is enforced cryptographically — it is not just a workflow condition that can be bypassed.

---

## Sprint-by-Sprint Build Log

### Sprint 1 — Foundation

Establishes the infrastructure skeleton. No application code — just the networking, compute, and access plumbing.

- **Bootstrap**: S3 bucket (versioned, public access blocked) stores the Terraform state file. DynamoDB table provides state locking so concurrent `terraform apply` runs cannot corrupt state.
- **VPC**: Isolated network with a public subnet, Internet Gateway, and route table.
- **Security Group**: Egress-only. No inbound ports are open. SSM Session Manager communicates outbound to the SSM endpoint — it does not need port 22.
- **EC2**: `t3.micro` running Amazon Linux 2023. No SSH key pair. Access is exclusively through SSM Session Manager.
- **IAM**: Instance role with `AmazonSSMManagedInstanceCore` — the minimum set of permissions for SSM to function.

### Sprint 2 — CloudWatch Monitoring

Adds observability. You can now see what the instance is doing without logging in.

- **CloudWatch Agent**: Installed via EC2 `user_data`. Configured to collect system logs.
- **Log collection fix**: Amazon Linux 2023 uses `systemd-journald` and does not populate `/var/log/messages` or `/var/log/secure` by default. `rsyslog` is installed via `user_data` to bridge `journald` output into those files.
- **CloudWatch Alarm**: Triggers when CPU utilisation exceeds 80% for two consecutive 5-minute periods.
- **SNS Topic**: Receives the alarm notification and forwards it by email. You must confirm the subscription in your inbox before alerts are delivered.
- **IAM update**: `CloudWatchAgentServerPolicy` added to the instance role.

### Sprint 3 — Operational Automation

The instance can now report its own health and log arbitrary events to a persistent store.

- **DynamoDB ops-logs table**: Each item is keyed by `instance_id` (partition) and `log_timestamp` (sort). A TTL attribute automatically expires entries after 30 days so the table does not grow indefinitely.
- **SSM Parameter Store**: Stores the DynamoDB table name and region so bash scripts can look up their target at runtime without hard-coding values.
- **SSM Run Command documents**: Two documents embed the bash scripts and can be executed from the AWS Console or CLI without SSH.
  - `health-check`: Collects CPU idle, load average, free memory, and disk usage, then writes a structured item to DynamoDB.
  - `log-event`: Writes a named event with an optional message to DynamoDB. Useful for marking deployments, maintenance windows, and so on.
- **Line-ending fix**: Bash scripts created on Windows contain CRLF line endings. The `#!/bin/bash\r` shebang is not recognised by the Linux kernel. Terraform normalises CRLF to LF using `replace()` before embedding the script in the SSM document.
- **IAM update**: Scoped inline policy adds `dynamodb:PutItem` (table ARN only) and `ssm:GetParameter` (specific parameter path only).

### Sprint 4 — GitHub Actions CI

Every Pull Request now gets an automated Terraform plan posted as a comment. No human needs to run Terraform locally to review an infrastructure change.

- **GitHub OIDC Provider**: Registered once in the AWS account via bootstrap. GitHub Actions presents a signed JWT; AWS verifies it and issues temporary credentials.
- **CI IAM Role**: `ReadOnlyAccess` is sufficient for `terraform plan`. Scoped to this repository's OIDC subject so no other repository can assume it.
- **Plan output capture**: `terraform plan` output is redirected to a file using `tee` and `PIPESTATUS`. The PR comment step reads directly from that file, avoiding size limits and the unreliable `steps.*.outputs.stdout` mechanism.

### Sprint 5 — Controlled Deployment

`terraform apply` runs only after a merge to `main` and explicit human approval. No accidental or automatic infrastructure changes.

- **GitHub Environment**: A named environment called `dev` is created in repository settings with required reviewers. The apply job is blocked at the environment gate until approval.
- **Apply IAM Role**: A separate role with write permissions across all managed services. Its trust policy uses `StringEquals` to match `environment:dev` in the OIDC `sub` claim — a condition that is only satisfied when the job explicitly references the protected environment.
- **`iam:PassRole` scoping**: The most sensitive permission is double-restricted: it can only be used to pass roles whose names match the project naming convention, and only to the EC2 service. It cannot be used to escalate privileges to any other service.

---

## Prerequisites

- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) configured with credentials that have `AdministratorAccess` (for initial bootstrap only)
- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5
- A GitHub repository (your fork of this project)
- An AWS account (all resources are Free Tier compatible)

---

## Getting Started

### 1. Bootstrap (one-time)

The bootstrap runs with **local state** and creates the S3 bucket and DynamoDB table that will hold state for all subsequent environments.

```bash
cd bootstrap
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
terraform init
terraform plan
terraform apply
```

Note the outputs — you will need `ci_role_arn` and `apply_role_arn` in a later step.

### 2. Add GitHub Secrets

In your repository: **Settings → Secrets and variables → Actions**

| Secret name | Value |
|---|---|
| `AWS_CI_ROLE_ARN` | Output of `terraform output ci_role_arn` from bootstrap |
| `AWS_APPLY_ROLE_ARN` | Output of `terraform output apply_role_arn` from bootstrap |

### 3. Create the GitHub Environment

In your repository: **Settings → Environments → New environment**

- Name: `dev` (exact, lowercase)
- Enable **Required reviewers** and add yourself
- Save protection rules

### 4. Deploy via Pull Request

```bash
git checkout -b feature/initial-deploy
# Make any small change to environments/dev/dev.tfvars (e.g. add a comment)
git add .
git commit -m "chore: trigger initial deploy"
git push -u origin feature/initial-deploy
```

Open a Pull Request targeting `main`. The `Terraform Plan` workflow runs automatically and posts plan output as a PR comment. Review the plan, then merge.

After merge, the `Terraform Apply` workflow is triggered. It pauses at the environment approval gate. Go to **Actions**, click the run, click **Review deployments**, and approve. `terraform apply` runs.

### 5. Connect to the instance (no SSH required)

```bash
# Get the instance ID from Terraform output
cd environments/dev
terraform output instance_id

# Start an SSM Session Manager session
aws ssm start-session --target <instance-id>
```

### 6. Run the automation scripts

From the AWS Console: **Systems Manager → Run Command → Run a command**

Select the document `cloud-ops-lab-dev-health-check` or `cloud-ops-lab-dev-log-event`, choose your instance, and run.

Or from the CLI:

```bash
# Health check
aws ssm send-command \
  --document-name "cloud-ops-lab-dev-health-check" \
  --targets "Key=instanceids,Values=<instance-id>" \
  --query "Command.CommandId" --output text

# Log a custom event
aws ssm send-command \
  --document-name "cloud-ops-lab-dev-log-event" \
  --parameters '{"EventType":["deployment"],"Message":["Deployed v1.0"]}' \
  --targets "Key=instanceids,Values=<instance-id>" \
  --query "Command.CommandId" --output text
```

Check the results in DynamoDB: **Console → DynamoDB → Tables → cloud-ops-lab-dev-ops-logs → Explore table items**

### 7. Tear down

```bash
cd environments/dev
terraform destroy -var-file="dev.tfvars"

# Only if you want to remove the bootstrap resources too
cd ../../bootstrap
terraform destroy
```

---

## Key Design Decisions

**No SSH, no key pairs.** SSM Session Manager provides shell access without opening any inbound ports. There is no private key to manage, rotate, or accidentally commit.

**Remote state with locking.** State is stored in S3 (versioned) with DynamoDB providing locks. This prevents state corruption from concurrent runs and allows the CI pipeline to share state safely.

**Modular Terraform.** Each module has a single responsibility: `vpc`, `iam`, `ec2`, `cloudwatch`, `dynamodb`, `ssm`. Adding a new environment means writing a new composition in `environments/` that wires the same modules with different inputs.

**Conditional IAM policy with a boolean flag.** The ops-automation inline policy uses `count = var.enable_ops_automation ? 1 : 0`. A boolean variable is known at plan time; using the DynamoDB table ARN directly in `count` would cause Terraform to fail because computed values are not resolved until apply.

**OIDC `sub` claim scoped to a GitHub Environment.** When a GitHub Actions job specifies `environment: dev`, the OIDC token's `sub` field becomes `repo:{org}/{repo}:environment:dev`. The apply IAM role's trust policy matches only this exact string. A workflow without `environment: dev` produces a different `sub` and cannot assume the role — even if it knows the ARN.

---

## AWS Free Tier Compatibility

| Resource | Free Tier limit | This project |
|---|---|---|
| EC2 | 750 hours/month t2.micro or t3.micro | 1 instance |
| S3 | 5 GB storage, 20,000 GET requests | < 1 MB state file |
| DynamoDB | 25 GB storage, 200M requests/month | 2 tables, minimal traffic |
| CloudWatch | 10 custom metrics, 5 GB log ingestion | 1 alarm, system logs only |
| SSM | Free for Parameter Store standard tier and Run Command | Standard tier only |
| SNS | 1 million publishes/month | 1 topic, alarm-triggered only |

> **Note:** The t3.micro instance is Free Tier eligible only in accounts created after 2024. If your account uses t2.micro for the Free Tier, update `instance_type` in `dev.tfvars`.

---

## Troubleshooting

**`terraform init` fails with "module does not exist"**
All modules must be present in `modules/`. Check that `modules/dynamodb/` and `modules/ssm/` exist. If cloning a fresh checkout, these directories should be present. If missing, the Sprint 3 commit may not have been included.

**CloudWatch logs not appearing**
On Amazon Linux 2023, `rsyslog` must be installed for `/var/log/messages` to exist. The EC2 `user_data` installs it, but the instance must be re-created (not just restarted) for `user_data` to re-run. Use `terraform taint module.ec2.aws_instance.ops` then `terraform apply`.

**SSM Run Command returns exit code 127**
This usually means the script shebang line contains a Windows carriage return (`\r`). The Terraform SSM module normalises line endings with `replace(..., "\r\n", "\n")`. If you edited the bash scripts on Windows and re-applied, the document will have been recreated with LF endings. Check with `aws ssm get-document --name cloud-ops-lab-dev-health-check` and look for `\r` characters.

**GitHub Actions: "Given variables file dev.tfvars does not exist"**
The file `environments/dev/dev.tfvars` must be committed. Named `*.tfvars` files (not `terraform.tfvars` or `*.auto.tfvars`) are intentionally tracked by this repository's `.gitignore`. Run `git ls-files environments/dev/dev.tfvars` to confirm it is tracked, then `git add` it if not.

**OIDC authentication fails on apply workflow**
The apply role trust policy uses `StringEquals` on the OIDC `sub` claim. The job must reference `environment: dev` (exact name). Verify the GitHub Environment is named `dev` (lowercase) in repository Settings. Also confirm `AWS_APPLY_ROLE_ARN` secret is set.

---

## License

This project is for portfolio and educational purposes.
