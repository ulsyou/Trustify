terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 5.60"
    }
  }

  backend "s3" {
    bucket = "tru-demo-tfstate-apse2"
    key = "dev/terraform.tfstate"
    region = "ap-southeast-2"
    dynamodb_table = "tru-demo-tfstate-lock"
    encrypt = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Prefix = var.prefix
      Project = var.project
      Environment = var.environment
      ManagedBy = "terraform"
      Owner = var.owner
      ResponsibleParty = var.responsible_party
    }
  }
}
