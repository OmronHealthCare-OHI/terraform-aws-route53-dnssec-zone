terraform {
  # optional() object attributes, and override_* / mock_provider in tests.
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # 6.x: data.aws_region exposes `region` (the signing-key submodule's
      # us-east-1 check reads it).
      version = ">= 6.0"
    }
  }
}
