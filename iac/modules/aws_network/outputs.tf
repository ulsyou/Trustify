#region VPC Outputs
output "vpc_id" {
  value = aws_vpc.this.id
}

output "vpc_cidr_block" {
  value = aws_vpc.this.cidr_block
}
#endregion

#region Subnet Outputs
output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "app_subnet_ids" {
  value = aws_subnet.app[*].id
}

output "database_subnet_ids" {
  value = aws_subnet.database[*].id
}
#endregion

#region Routing & NAT Outputs
output "nat_gateway_ids" {
  value = aws_nat_gateway.this[*].id
}
#endregion

#region RDS DB Subnet Group Outputs
output "database_subnet_group_name" {
  value = aws_db_subnet_group.this.name
}
#endregion
