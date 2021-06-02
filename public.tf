module "public_label" {
  source  = "cloudposse/label/null"
  version = "0.24.1"

  attributes = ["public"]
  tags = merge(
    var.public_subnets_additional_tags,
    map(var.subnet_type_tag_key, format(var.subnet_type_tag_value_format, "public"))
  )

  context = module.this.context
}

locals {
  public_subnet_count        = local.enabled && var.max_subnet_count == 0 ? length(flatten(data.aws_availability_zones.available.*.names)) : var.max_subnet_count
  public_route_expr_enabled  = local.enabled && signum(length(var.vpc_default_route_table_id)) == 1
  public_network_acl_enabled = local.enabled && signum(length(var.public_network_acl_id)) == 0 ? 1 : 0
  vpc_default_route_table_id = local.enabled ? signum(length(var.vpc_default_route_table_id)) : 0
  public_secure_nacl         = local.enabled && var.secure_nacl ? 1 : 0
  ingress_public_nacl_rules  = var.ingress_public_nacl_rules
  egress_public_nacl_rules   = var.egress_public_nacl_rules
}

resource "aws_subnet" "public" {
  count             = local.availability_zones_count
  vpc_id            = join("", data.aws_vpc.default.*.id)
  availability_zone = element(var.availability_zones, count.index)

  cidr_block = cidrsubnet(
    signum(length(var.cidr_block)) == 1 ? var.cidr_block : join("", data.aws_vpc.default.*.cidr_block),
    ceil(log(local.public_subnet_count * 2, 2)),
    local.public_subnet_count + count.index
  )

  map_public_ip_on_launch = var.map_public_ip_on_launch

  tags = merge(
    module.public_label.tags,
    {
      "Name" = format("%s%s%s", module.public_label.id, local.delimiter, local.az_map[element(var.availability_zones, count.index)])
    }
  )

  lifecycle {
    ignore_changes = [tags.kubernetes, tags.SubnetType]
  }
}

resource "aws_route_table" "public" {
  count  = local.public_route_expr_enabled ? 0 : local.enabled_count
  vpc_id = join("", data.aws_vpc.default.*.id)

  tags = module.public_label.tags
}

resource "aws_route" "public" {
  count                  = local.public_route_expr_enabled ? 0 : local.enabled_count
  route_table_id         = join("", aws_route_table.public.*.id)
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = var.igw_id

  timeouts {
    create = var.aws_route_create_timeout
    delete = var.aws_route_delete_timeout
  }
}

resource "aws_route_table_association" "public" {
  count          = local.public_route_expr_enabled ? 0 : local.availability_zones_count
  subnet_id      = element(aws_subnet.public.*.id, count.index)
  route_table_id = aws_route_table.public[0].id
}

resource "aws_route_table_association" "public_default" {
  count          = local.public_route_expr_enabled ? local.availability_zones_count : 0
  subnet_id      = element(aws_subnet.public.*.id, count.index)
  route_table_id = var.vpc_default_route_table_id
}

resource "aws_network_acl" "public" {
  count      = local.public_network_acl_enabled
  vpc_id     = var.vpc_id
  subnet_ids = aws_subnet.public.*.id

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

  tags = module.public_label.tags
}

#### updated
resource "aws_network_acl" "public_secure_nacl" {
  count      = local.public_secure_nacl
  vpc_id     = var.vpc_id
  subnet_ids = aws_subnet.public.*.id

  dynamic "egress" {
    for_each = [for rule_obj in local.egress_public_nacl_rules : {
      from_port  = rule_obj.from_port
      to_port    = rule_obj.to_port
      rule_no    = rule_obj.rule_num
      cidr_block = rule_obj.cidr
      protocol   = rule_obj.protocol
      action     = rule_obj.action
      icmp_code  = rule_obj.icmp_code
      icmp_type  = rule_obj.icmp_type
    }]
    content {
      protocol   = egress.value["protocol"]
      rule_no    = egress.value["rule_no"]
      action     = egress.value["action"]
      cidr_block = egress.value["cidr_block"]
      from_port  = egress.value["from_port"]
      to_port    = egress.value["to_port"]
      icmp_code  = egress.value["icmp_code"]
      icmp_type  = egress.value["icmp_type"]
    }
  }

  dynamic "ingress" {
    for_each = [for rule_obj in local.ingress_public_nacl_rules : {
      from_port  = rule_obj.from_port
      to_port    = rule_obj.to_port
      rule_no    = rule_obj.rule_num
      cidr_block = rule_obj.cidr
      protocol   = rule_obj.protocol
      action     = rule_obj.action
      icmp_code  = rule_obj.icmp_code
      icmp_type  = rule_obj.icmp_type
    }]
    content {
      protocol   = ingress.value["protocol"] 
      rule_no    = ingress.value["rule_no"]
      action     = ingress.value["action"]
      cidr_block = ingress.value["cidr_block"]
      from_port  = ingress.value["from_port"]
      to_port    = ingress.value["to_port"]
      icmp_code  = ingress.value["icmp_code"]
      icmp_type  = ingress.value["icmp_type"]
    }
  }

  tags = module.public_label.tags
}

