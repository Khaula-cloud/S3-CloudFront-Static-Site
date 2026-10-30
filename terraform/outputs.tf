output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.portfolio.domain_name
}

output "cloudfront_url" {
  value = "https://${aws_cloudfront_distribution.portfolio.domain_name}"
}

output "direct_s3_url_should_fail" {
  value = "https://${aws_s3_bucket.portfolio.bucket_regional_domain_name}/index.html"
}

output "distribution_id" {
  value = aws_cloudfront_distribution.portfolio.id
}
