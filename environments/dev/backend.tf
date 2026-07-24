# Remote state backend. Fill in bucket/dynamodb_table with the outputs from
# `modules/state-backend` after running that bootstrap once (see docs/DEPLOYMENT.md).
#
# For a first local test-drive you can comment this whole block out and
# Terraform will fall back to local state (./terraform.tfstate) — fine for
# quick iteration, NOT recommended for anything beyond a personal sandbox.

# terraform {
#   backend "s3" {
#     bucket         = "REPLACE-ME-tf-state-bucket"
#     key            = "dash-cloudops/dev/terraform.tfstate"
#     region         = "us-east-1"
#     dynamodb_table = "dash-cloudops-tf-locks"
#     encrypt        = true
#   }
# }
