terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = var.region_name
  # profile = "dev"

}

locals {
  tags = {
    Environment = var.env_name
    Application = var.app_name
    Dept        = "Tech"
    CreatedBy   = "Terraform"
  }
}


terraform {
  backend "s3" {
    bucket = "ncs_terraform-backend"
    key    = "path/to/ndev/services/terraform.tfstate"
    region = "us-east-2"
    encrypt = true
  }
}

locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "terraform"
    Owner       = "Devops"
  }
}

