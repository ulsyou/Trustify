locals {
  bucket_name = "${var.prefix}-${var.project}-tfstate-${var.region_code}"
  table_name = "${var.prefix}-${var.project}-tfstate-lock"
}

#region S3 State Bucket
resource "aws_s3_bucket" "state" {
  bucket = local.bucket_name
  force_destroy = false
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls = true
  block_public_policy = true
  ignore_public_acls = true
  restrict_public_buckets = true
}
#endregion

#region DynamoDB State Lock Table
resource "aws_dynamodb_table" "lock" {
  name = local.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}
#endregion
