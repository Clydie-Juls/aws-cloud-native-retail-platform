# Resource 1: AWS vpc
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(var.tags, { Name = "${var.environment_name}-vpc" })
  lifecycle {
    prevent_destroy = false
  }
}

# Resource 2: AWS igw
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = merge(var.tags, { Name = "${var.environment_name}-igw" })
}

# Resource 3: AWS public subnets
resource "aws_subnet" "public_subnets" {
  for_each                = { for idx, az in local.azs : az => local.public_subnets[idx] }
  availability_zone       = each.key
  cidr_block              = each.value
  map_public_ip_on_launch = true
  vpc_id                  = aws_vpc.main.id
  tags                    = merge(var.tags, { Name = "${var.environment_name}-public-${each.key}" })
}

# Resource 4: AWS private subnets
resource "aws_subnet" "private_subnets" {
  for_each          = { for idx, az in local.azs : az => local.public_subnets[idx] }
  availability_zone = each.key
  cidr_block        = each.value
  vpc_id            = aws_vpc.main.id
  tags              = merge(var.tags, { Name = "${var.environment_name}-private-${each.key}" })
}

# resource 5: Elastic IP for NAT gateway
resource "aws_eip" "eip" {
  tags = merge(var.tags, { Name = "${var.environment_name}-nat-eip" })
}

# resource 6: NAT gateway
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.eip.id
  subnet_id     = values(aws_subnet.public_subnets)[0].id
  tags          = merge(var.tags, { Name = "${var.environment_name}-nat" })
  depends_on    = [aws_internet_gateway.igw]
}

# resource 7: Public route table
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = merge(var.tags, { Name = "${var.environment_name}-public-rt" })
}

#resource 8: Public route table associate to public subnet
resource "aws_route_table_association" "public_rt_assoc" {
  for_each       = aws_subnet.public_subnets
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public_rt.id
}

# resource 9: Private route table
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.nat.id
  }
  tags = merge(var.tags, { Name = "${var.environment_name}-private-rt" })
}

#resource 8: Private route table associate to public subnet
resource "aws_route_table_association" "private_rt_assoc" {
  for_each       = aws_subnet.private_subnets
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private_rt.id
}