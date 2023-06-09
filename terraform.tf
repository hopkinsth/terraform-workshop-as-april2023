terraform {
  backend "s3" {
    bucket = "rv-thopkins-sandbox-tfstate"
    key = "bursting-mackerel-dev.tfstate"
    region = "us-east-1"
  }
}
