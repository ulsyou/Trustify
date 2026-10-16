#region VPC
resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support = var.enable_dns_support

  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}
#endregion

#region Internet Gateway
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name_prefix}-igw"
  }
}
#endregion

#region Subnets
# 1. Public Subnets (ALB & NAT Gateways)
resource "aws_subnet" "public" {
  count = length(var.availability_zones)

  vpc_id = aws_vpc.this.id
  cidr_block = cidrsubnet(var.vpc_cidr, 4, count.index)
  availability_zone = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.name_prefix}-public-${var.availability_zones[count.index]}"
    Tier = "public"
  }
}

# 2. Private App Subnets (ECS Fargate Tasks)
resource "aws_subnet" "app" {
  count = length(var.availability_zones)

  vpc_id = aws_vpc.this.id
  cidr_block = cidrsubnet(var.vpc_cidr, 4, count.index + length(var.availability_zones))
  availability_zone = var.availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.name_prefix}-app-${var.availability_zones[count.index]}"
    Tier = "private-app"
  }
}

# 3. Private Database Subnets (Isolated RDS PostgreSQL)
resource "aws_subnet" "database" {
  count = length(var.availability_zones)

  vpc_id = aws_vpc.this.id
  cidr_block = cidrsubnet(var.vpc_cidr, 4, count.index + (2 * length(var.availability_zones)))
  availability_zone = var.availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.name_prefix}-db-${var.availability_zones[count.index]}"
    Tier = "private-db"
  }
}
#endregion

#region Public Route Table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name = "${var.name_prefix}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  count = length(var.availability_zones)

  subnet_id = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}
#endregion

#region NAT Gateways
resource "aws_eip" "nat" {
  count = var.nat_gateway_count

  domain = "vpc"

  tags = {
    Name = "${var.name_prefix}-nat-eip-${count.index + 1}"
  }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  count = var.nat_gateway_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id = aws_subnet.public[count.index].id

  tags = {
    Name = "${var.name_prefix}-nat-${count.index + 1}"
  }

  depends_on = [aws_internet_gateway.this]
}
#endregion

#region Private App Route Tables
resource "aws_route_table" "app" {
  count = var.nat_gateway_count

  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[count.index].id
  }

  tags = {
    Name = "${var.name_prefix}-app-rt-${count.index + 1}"
  }
}

resource "aws_route_table_association" "app" {
  count = length(var.availability_zones)

  subnet_id = aws_subnet.app[count.index].id
  route_table_id = aws_route_table.app[count.index % var.nat_gateway_count].id
}
#endregion

#region Private Database Route Tables
resource "aws_route_table" "database" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.name_prefix}-db-rt"
  }
}

resource "aws_route_table_association" "database" {
  count = length(var.availability_zones)

  subnet_id = aws_subnet.database[count.index].id
  route_table_id = aws_route_table.database.id
}
#endregion

#region RDS DB Subnet Group
resource "aws_db_subnet_group" "this" {
  name = "${var.name_prefix}-db-subnet-group"
  subnet_ids = aws_subnet.database[*].id

  tags = {
    Name = "${var.name_prefix}-db-subnet-group"
  }
}
#endregion
