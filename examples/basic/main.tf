terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

# Route 53 is global, but the zone's DNSSEC signing key must live in us-east-1,
# so the module runs with a us-east-1 provider.
provider "aws" {
  region = "us-east-1"
}

# The caller owns the label: it states where it deploys and where it sits in the
# ohi:* hierarchy, and hands the resolved context to every module it calls.
module "label" {
  source = "github.com/OmronHealthCare-OHI/terraform-null-label?ref=1.0.0"

  namespace  = "vlt"
  region     = "us"
  stage      = "prd"
  aws_region = "us-east-1" # tag only; not part of the id

  application = "platform"
}

module "example_com" {
  source = "../.."

  name        = "example"
  domain_name = "example.com"
  context     = module.label.context
}
