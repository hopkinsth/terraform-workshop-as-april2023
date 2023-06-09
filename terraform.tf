resource "aws_s3_bucket" "state" {
  bucket = "${local.app_name}-${var.env}-tfstate"
}

terraform {
  backend "s3" {
    bucket = "rv-thopkins-sandbox-tfstate"
    key = "bursting-mackerel-dev.tfstate"
    region = "us-east-1"
  }
}
