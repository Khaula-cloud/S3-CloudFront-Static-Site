locals {
  website_dir = "${path.module}/../website"
  use_custom  = var.domain_name != "" && var.acm_certificate_arn != ""
  mime_types = {
    html = "text/html"
    css  = "text/css"
    js   = "application/javascript"
    json = "application/json"
    png  = "image/png"
    jpg  = "image/jpeg"
    jpeg = "image/jpeg"
    svg  = "image/svg+xml"
    ico  = "image/x-icon"
    webp = "image/webp"
  }
}

# ---------------------------------------------------------------
# 1. Isolated, private S3 bucket
# ---------------------------------------------------------------
resource "aws_s3_bucket" "portfolio" {
  bucket        = var.bucket_name
  force_destroy = true # lets `terraform destroy` succeed even when files exist
}

# Block ALL public access (all four settings ON).
# CloudFront reaches the bucket through the OAC policy below, which is NOT "public".
resource "aws_s3_bucket_public_access_block" "portfolio" {
  bucket                  = aws_s3_bucket.portfolio.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "portfolio" {
  bucket = aws_s3_bucket.portfolio.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "portfolio" {
  bucket = aws_s3_bucket.portfolio.id
  versioning_configuration {
    status = "Enabled"
  }
}

# ---------------------------------------------------------------
# 2. Upload the website files
# ---------------------------------------------------------------
resource "aws_s3_object" "site_files" {
  for_each = { for f in fileset(local.website_dir, "**") : f => f if f != "assets/.gitkeep" }

  bucket       = aws_s3_bucket.portfolio.id
  key          = each.value
  source       = "${local.website_dir}/${each.value}"
  etag         = filemd5("${local.website_dir}/${each.value}")
  content_type = lookup(local.mime_types, lower(element(split(".", each.value), length(split(".", each.value)) - 1)), "application/octet-stream")
}

# ---------------------------------------------------------------
# 3. CloudFront CDN + Origin Access Control + HTTPS
# ---------------------------------------------------------------
resource "aws_cloudfront_origin_access_control" "portfolio" {
  name                              = "portfolio-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "portfolio" {
  enabled             = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100" # cheapest edge-location set
  aliases             = local.use_custom ? [var.domain_name] : []

  origin {
    domain_name              = aws_s3_bucket.portfolio.bucket_regional_domain_name
    origin_id                = "S3-portfolio"
    origin_access_control_id = aws_cloudfront_origin_access_control.portfolio.id
  }

  default_cache_behavior {
    target_origin_id       = "S3-portfolio"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id        = "658327ea-f89d-4fab-a63d-7e88639e58f6" # AWS managed: CachingOptimized
  }

  # Private bucket returns 403 for missing keys; show a friendly 404 page instead
  custom_error_response {
    error_code            = 403
    response_code         = 404
    response_page_path    = "/error.html"
    error_caching_min_ttl = 10
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # Free default *.cloudfront.net certificate, or a custom ACM cert when a domain is supplied
  viewer_certificate {
    cloudfront_default_certificate = local.use_custom ? null : true
    acm_certificate_arn            = local.use_custom ? var.acm_certificate_arn : null
    ssl_support_method             = local.use_custom ? "sni-only" : null
    minimum_protocol_version       = local.use_custom ? "TLSv1.2_2021" : null
  }
}

# ---------------------------------------------------------------
# 4. JSON IAM bucket policy (least privilege)
# ---------------------------------------------------------------
resource "aws_s3_bucket_policy" "portfolio" {
  bucket     = aws_s3_bucket.portfolio.id
  depends_on = [aws_s3_bucket_public_access_block.portfolio]

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "PolicyForCloudFrontPrivateContent"
    Statement = [
      {
        Sid       = "AllowCloudFrontServicePrincipalReadOnly"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.portfolio.arn}/*"
        Condition = {
          StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.portfolio.arn }
        }
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.portfolio.arn, "${aws_s3_bucket.portfolio.arn}/*"]
        Condition = {
          Bool = { "aws:SecureTransport" = "false" }
        }
      }
    ]
  })
}
