terraform {
  # optional() object attributes, and key_signing_keys' validation reading
  # signing_status (cross-variable validation, 1.9). Checked with
  # `terraform validate -no-tests` on 1.9.0. The tests need more, 1.14
  # (README.md, "Local development").
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
