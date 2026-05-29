locals {
  exports_bucket_name   = coalesce(var.exports_bucket_name, "${var.cluster_name}-exports")
  exports_iam_user_name = "${var.cluster_name}-exports-service"
}

resource "aws_s3_bucket" "exports" {
  bucket = local.exports_bucket_name
}

resource "aws_s3_bucket_server_side_encryption_configuration" "exports" {
  bucket = aws_s3_bucket.exports.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Fully private — exports are never served directly to browsers.
resource "aws_s3_bucket_public_access_block" "exports" {
  bucket                  = aws_s3_bucket.exports.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# No S3 lifecycle rule — Opal's cleanup cron is the single authority.
# An S3 rule running independently would delete files without clearing
# result.objectKey in Postgres, causing /download to return 404 instead
# of the expected 410 Gone.

resource "aws_s3_bucket_policy" "exports" {
  bucket = aws_s3_bucket.exports.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.exports.arn,
          "${aws_s3_bucket.exports.arn}/*"
        ]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.exports]
}

# IAM user — scoped read/write/delete for the Opal task-workers service account.
resource "aws_iam_user" "exports" {
  name = local.exports_iam_user_name

  lifecycle {
    ignore_changes = [tags, tags_all]
  }
}

data "aws_iam_policy_document" "exports" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${aws_s3_bucket.exports.arn}/*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.exports.arn]
  }
}

resource "aws_iam_policy" "exports" {
  name   = "${local.exports_iam_user_name}-access"
  policy = data.aws_iam_policy_document.exports.json
}

resource "aws_iam_user_policy_attachment" "exports" {
  user       = aws_iam_user.exports.name
  policy_arn = aws_iam_policy.exports.arn
}
