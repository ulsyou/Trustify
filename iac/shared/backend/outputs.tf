#region S3 Outputs
output "state_bucket_id" {
  value = aws_s3_bucket.state.id
}

output "state_bucket_arn" {
  value = aws_s3_bucket.state.arn
}
#endregion

#region DynamoDB Outputs
output "lock_table_name" {
  value = aws_dynamodb_table.lock.name
}

output "lock_table_arn" {
  value = aws_dynamodb_table.lock.arn
}
#endregion
