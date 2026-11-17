terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

# The caller owns the label: it states where it deploys and where it sits in the
# ohi:* hierarchy, and hands the resolved context to every module it calls.
module "label" {
  source = "github.com/OmronHealthCare-OHI/terraform-null-label?ref=1.0.0"

  namespace  = "vlt"
  region     = "us"
  stage      = "prd"
  aws_region = "us-west-2" # tag only; not part of the id

  application = "platform"
  module      = "dns" # -> ohi:module = platform-dns; not in the id
  owner       = "cloud-foundations"

  tags = {
    managed-by = "terraform"
  }
}

# The caller's own region. Route 53 is global, so the zones can be managed from
# any region; only the signing key can't.
provider "aws" {
  region              = "us-west-2"
  allowed_account_ids = ["111111111111"]

  default_tags {
    tags = module.label.tags
  }
}

# Route 53 accepts DNSSEC signing keys from us-east-1 only, so the key gets a
# provider of its own; the submodule refuses any other region.
provider "aws" {
  alias               = "us_east_1"
  region              = "us-east-1"
  allowed_account_ids = ["111111111111"]

  default_tags {
    tags = module.label.tags
  }
}

module "dnssec_signing_key" {
  source = "../../modules/signing-key"
  providers = {
    aws = aws.us_east_1
  }

  name                    = "dnssec"
  deletion_window_in_days = 30
  context                 = module.label.context
}

# Two zones, one key.
module "example_com" {
  source = "../.."

  name                 = "example"
  domain_name          = "example.com"
  kms_key_arn          = module.dnssec_signing_key.key_arn
  key_signing_key_name = "primary"
  signing_status       = "SIGNING"
  comment              = "Public DNS for example.com"
  context              = module.label.context

  extra_tags = {
    cost-centre = "platform"
  }
}

module "example_org" {
  source = "../.."

  name        = "example-org"
  domain_name = "example.org"
  kms_key_arn = module.dnssec_signing_key.key_arn
  context     = module.label.context
}

# Chaining: a child label inherits the module's hierarchy and sets its own leaf
# name, so sibling resources stay under one namespace/application.
module "child_label" {
  source = "github.com/OmronHealthCare-OHI/terraform-null-label?ref=1.0.0"

  context = module.example_com.label_context
  name    = "records"
}

output "example_com_domain_zone" {
  description = "example.com's zone in aws-organization's <name>_domain_zone shape"
  value       = module.example_com.zone
}

output "example_com_name_servers" {
  description = "The name servers to delegate example.com to at the registrar"
  value       = module.example_com.name_servers
}

output "example_com_ds_record" {
  description = "The DS record to add at the registrar once delegation has propagated"
  value       = module.example_com.ds_record
}

output "child_id" {
  description = "Name a child label composes from the module's exported context"
  value       = module.child_label.id
}
