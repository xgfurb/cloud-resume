# ============================================================
# OUTPUTS
# ============================================================
# Outputs display values after `terraform apply` completes.
# They're useful for:
#   - Seeing resource IDs/URLs without digging through the
#     AWS console
#   - Passing values between Terraform modules
#   - Feeding values into CI/CD pipelines
#
# After apply, you'll see these printed in your terminal.
# You can also retrieve them later with `terraform output`.
# ============================================================

# The nameservers you need to enter at your domain registrar.
# There will be 4 values — copy all of them.
output "nameservers" {
  description = "Set these as custom nameservers at your domain registrar"
  value       = aws_route53_zone.main.name_servers
}

# The S3 bucket name — useful for manual uploads and CI/CD
output "s3_bucket_name" {
  description = "S3 bucket name for static site files"
  value       = aws_s3_bucket.site.id
}

# The Route 53 hosted zone ID — needed by other resources
output "hosted_zone_id" {
  description = "Route 53 hosted zone ID"
  value       = aws_route53_zone.main.zone_id
}

# CloudFront distribution ID — needed for cache invalidation
# in CI/CD (when you push new files, you tell CloudFront to
# stop serving the cached version and fetch the new one)
output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID for cache invalidation"
  value       = aws_cloudfront_distribution.site.id
}

# The URL where your site is live
output "site_url" {
  description = "Live site URL"
  value       = "https://${var.domain_name}"
}

# API Gateway endpoint — this is the URL your frontend
# JavaScript calls to get/increment the visitor count.
# Drop this into index.html to wire up the counter.
output "api_url" {
  description = "Visitor counter API endpoint"
  value       = "${aws_apigatewayv2_api.counter_api.api_endpoint}/count"
}
