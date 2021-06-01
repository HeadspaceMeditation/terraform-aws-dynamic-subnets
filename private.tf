module "private_label" {
  source  = "cloudposse/label/null"
  version = "0.24.1"

  attributes = ["private"]
  tags = merge(
    var.private_subnets_additional_tags,
    map(var.subnet_type_tag_key, format(var.subnet_type_tag_value_format, "private"))
  )

  context = module.this.context
}

locals {
  private_subnet_count        = var.max_subnet_count == 0 ? length(flatten(data.aws_availability_zones.available.*.names)) : var.max_subnet_count
  private_network_acl_enabled = signum(length(var.private_network_acl_id)) == 0 ? 1 : 0
  private_secure_nacl         = local.enabled && var.secure_nacl ? 1 : 0
  local_private_nacl_rules  = var.local_private_nacl_rules
}

resource "aws_subnet" "private" {
  count             = local.enabled ? local.availability_zones_count : 0
  vpc_id            = join("", data.aws_vpc.default.*.id)
  availability_zone = element(var.availability_zones, count.index)

  cidr_block = cidrsubnet(
    signum(length(var.cidr_block)) == 1 ? var.cidr_block : join("", data.aws_vpc.default.*.cidr_block),
    ceil(log(local.private_subnet_count * 2, 2)),
    count.index
  )

  tags = merge(
    module.private_label.tags,
    {
      "Name" = format("%s%s%s", module.private_label.id, local.delimiter, local.az_map[element(var.availability_zones, count.index)])
    }
  )

  lifecycle {
    # Ignore tags added by kops or kubernetes
    ignore_changes = [tags.kubernetes, tags.SubnetType]
  }
}

resource "aws_route_table" "private" {
  count  = local.enabled ? local.availability_zones_count : 0
  vpc_id = join("", data.aws_vpc.default.*.id)

  tags = merge(
    module.private_label.tags,
    {
      "Name" = format("%s%s%s", module.private_label.id, local.delimiter, local.az_map[element(var.availability_zones, count.index)])
    }
  )
}

resource "aws_route_table_association" "private" {
  count          = local.enabled ? local.availability_zones_count : 0
  subnet_id      = element(aws_subnet.private.*.id, count.index)
  route_table_id = element(aws_route_table.private.*.id, count.index)
}

resource "aws_network_acl" "private" {
  count      = local.enabled ? local.private_network_acl_enabled : 0
  vpc_id     = var.vpc_id
  subnet_ids = aws_subnet.private.*.id

  egress {
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
    protocol   = "-1"
  }

  ingress {
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
    protocol   = "-1"
  }

  tags = module.private_label.tags
}

#### updated
resource "aws_network_acl" "private_secure_nacl" {
  count      = local.private_secure_nacl
  vpc_id     = var.vpc_id
  subnet_ids = aws_subnet.private.*.id

  dynamic "egress" {
    for_each = [for rule_obj in local.private_nacl_rules : {
      port       = rule_obj.port
      rule_no    = rule_obj.rule_num
      cidr_block = rule_obj.cidr
      protocol   = rule_obj.protocol
      action     = rule_obj.action
    }]
    content {
      protocol   = egress.value["protocol"]
      rule_no    = egress.value["rule_no"]
      action     = egress.value["action"]
      cidr_block = egress.value["cidr_block"]
      from_port  = egress.value["port"]
      to_port    = egress.value["port"]
    }
  }

  dynamic "ingress" {
    for_each = [for rule_obj in local.private_nacl_rules : {
      port       = rule_obj.port
      rule_no    = rule_obj.rule_num
      cidr_block = rule_obj.cidr
      protocol   = rule_obj.protocol
      action     = rule_obj.action
    }]
    content {
      protocol   = ingress.value["protocol"]
      rule_no    = ingress.value["rule_no"]
      action     = ingress.value["action"]
      cidr_block = ingress.value["cidr_block"]
      from_port  = ingress.value["port"]
      to_port    = ingress.value["port"]
    }
  }

  tags = module.private_label.tags
}

locals {
  private_nacl_rules = local.local_private_nacl_rules
}
