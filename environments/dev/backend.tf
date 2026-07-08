terraform {
  backend "s3" {
    bucket         = "cloudopslab-tfstate-mlavinc"
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "cloud-ops-lab-tf-locks"
    encrypt        = true
  }
}
