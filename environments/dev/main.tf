# Computed once and shared between the ec2 and cloudwatch modules to avoid
# a circular dependency (ec2 needs the name for the agent config; cloudwatch
# needs the ec2 instance_id for the alarm dimension).
locals {
  log_group_name = "/${var.project_name}/${var.environment}/ops"
}

module "vpc" {
  source = "../../modules/vpc"

  project_name       = var.project_name
  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  public_subnet_cidr = var.public_subnet_cidr
  availability_zone  = var.availability_zone
}

module "iam" {
  source = "../../modules/iam"

  project_name = var.project_name
  environment  = var.environment
}

module "ec2" {
  source = "../../modules/ec2"

  project_name          = var.project_name
  environment           = var.environment
  vpc_id                = module.vpc.vpc_id
  subnet_id             = module.vpc.public_subnet_id
  instance_profile_name = module.iam.instance_profile_name
  instance_type         = var.instance_type
  log_group_name        = local.log_group_name
}

module "cloudwatch" {
  source = "../../modules/cloudwatch"

  project_name   = var.project_name
  environment    = var.environment
  instance_id    = module.ec2.instance_id
  alarm_email    = var.alarm_email
  log_group_name = local.log_group_name
}
