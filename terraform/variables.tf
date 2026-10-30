variable "region" {
  type    = string
  default = "us-east-2"
}

variable "bucket_name" {
  type        = string
  default     = "portfolio-website-assets1-tf"
  description = "Globally unique S3 bucket name. Change it if Terraform reports the name is taken."
}

# ---- OPTIONAL custom domain mapping (leave empty = zero cost, uses *.cloudfront.net) ----
variable "domain_name" {
  type        = string
  default     = ""
  description = "Custom domain, e.g. www.example.com"
}

variable "acm_certificate_arn" {
  type        = string
  default     = ""
  description = "ACM certificate ARN for domain_name. MUST be issued in us-east-1 for CloudFront."
}
