data "aws_availability_zones" "available" {}

locals {
  # Use one subnet per AZ, up to the number of CIDRs provided
  subnet_count = min(
    length(data.aws_availability_zones.available.names),
    length(var.public_subnet_cidrs)
  )
  azs = slice(data.aws_availability_zones.available.names, 0, local.subnet_count)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.2"

  name = var.name
  cidr = var.vpc_cidr
  azs  = local.azs

  manage_default_network_acl = false

  # Subnet layout
  public_subnets  = var.public_subnet_cidrs
  private_subnets = var.private_subnet_cidrs

  # Networking extras
  enable_nat_gateway   = true # 1 per VPC (single_nat_gateway=true)
  single_nat_gateway   = true
  enable_dns_hostnames = true

  tags = {
    Environment = var.name
    Terraform   = "true"
  }
}
