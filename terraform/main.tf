# ============================================================
# MAIN INFRASTRUCTURE — Phase 2, Step 1
# ============================================================
# This file defines the first resources we need:
#   1. S3 bucket for static site files
#   2. Route 53 hosted zone for DNS
#
# We deploy these first because:
#   - The hosted zone gives us nameservers to configure at
#     your registrar
#   - The ACM certificate (added next) needs working DNS
#     to validate domain ownership
# ============================================================

#Test comment 
# ────────────────────────────────────────────────────────────
# S3 BUCKET
# ────────────────────────────────────────────────────────────
# S3 (Simple Storage Service) stores your HTML/CSS files.
#
# SECURITY NOTE: We are NOT enabling S3 static website hosting
# or making the bucket public. Instead, CloudFront will access
# the bucket through an Origin Access Control (OAC) policy.
# This means:
#   - Users can ONLY reach your files through CloudFront
#   - S3 is never directly exposed to the internet
#   - HTTPS is enforced by CloudFront
# ────────────────────────────────────────────────────────────

# The bucket itself — just a container for files
resource "aws_s3_bucket" "site" {
  bucket = var.bucket_name

  # tags help identify resources in the AWS console
  tags = {
    Project = "cloud-resume"
  }
}

# Block ALL public access to the bucket.
# This is a safety net — even if someone misconfigures a
# bucket policy, this setting prevents public exposure.
resource "aws_s3_bucket_public_access_block" "site" {
  bucket = aws_s3_bucket.site.id

  block_public_acls       = true # block public ACLs from being set
  block_public_policy     = true # block public bucket policies
  ignore_public_acls      = true # ignore any existing public ACLs
  restrict_public_buckets = true # restrict public bucket policies
}


# ────────────────────────────────────────────────────────────
# ROUTE 53 HOSTED ZONE
# ────────────────────────────────────────────────────────────
# A hosted zone is a container for DNS records for your domain.
# When you create one, AWS assigns 4 nameservers. You then
# update your registrar to point to these nameservers, which
# tells the internet "AWS Route 53 handles DNS for this domain."
#
# This costs $0.50/month per hosted zone — the only Phase 2
# cost that isn't free tier.
# ────────────────────────────────────────────────────────────

resource "aws_route53_zone" "main" {
  name = var.domain_name

  tags = {
    Project = "cloud-resume"
  }
}


# ────────────────────────────────────────────────────────────
# ACM CERTIFICATE (SSL/TLS)
# ────────────────────────────────────────────────────────────
# Requests a free public certificate from AWS Certificate
# Manager for your domain. CloudFront uses this to serve
# your site over HTTPS.
#
# validation_method = "DNS" means AWS gives us a CNAME record
# to add to DNS. If that record exists, AWS knows you own the
# domain and issues the certificate. Terraform creates the
# record automatically via Route 53 below.
#
# subject_alternative_names includes www.czresume.com so the
# same certificate covers both the root domain and www.
# ────────────────────────────────────────────────────────────

resource "aws_acm_certificate" "site" {
  domain_name               = var.domain_name
  subject_alternative_names = ["www.${var.domain_name}"]
  validation_method         = "DNS"

  tags = {
    Project = "cloud-resume"
  }

  # lifecycle tells Terraform how to handle updates.
  # create_before_destroy ensures a new cert is issued
  # before the old one is deleted — prevents downtime
  # if the cert ever needs to be replaced.
  lifecycle {
    create_before_destroy = true
  }
}


# ────────────────────────────────────────────────────────────
# ACM DNS VALIDATION RECORDS
# ────────────────────────────────────────────────────────────
# ACM gives us one or more DNS records to prove domain
# ownership. This resource creates those records in Route 53
# automatically.
#
# for_each iterates over the validation options — typically
# one CNAME per domain name on the certificate. The toset()
# ensures uniqueness (root and www may share a validation
# record if they're on the same zone).
# ────────────────────────────────────────────────────────────

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.site.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = aws_route53_zone.main.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 300 # 5 minutes — low TTL for validation records
  records = [each.value.record]

  allow_overwrite = true # safe to overwrite if the record already exists
}


# ────────────────────────────────────────────────────────────
# ACM CERTIFICATE VALIDATION (waiter)
# ────────────────────────────────────────────────────────────
# This resource doesn't create anything — it tells Terraform
# to WAIT until AWS has verified the DNS records and actually
# issued the certificate. Without this, CloudFront would try
# to use a certificate that isn't ready yet and fail.
# ────────────────────────────────────────────────────────────

resource "aws_acm_certificate_validation" "site" {
  certificate_arn         = aws_acm_certificate.site.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}


# ────────────────────────────────────────────────────────────
# CLOUDFRONT ORIGIN ACCESS CONTROL (OAC)
# ────────────────────────────────────────────────────────────
# OAC is a security policy that tells CloudFront how to
# authenticate when requesting files from S3.
#
# With OAC, CloudFront signs every request to S3 using
# SigV4 (AWS's request signing protocol). S3 verifies
# the signature and only serves files if the request
# came from this specific CloudFront distribution.
#
# This replaces the older "Origin Access Identity" (OAI)
# approach — OAC is the current AWS recommendation.
# ────────────────────────────────────────────────────────────

resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "oac-${var.bucket_name}"
  description                       = "OAC for ${var.domain_name} S3 bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always" # always sign requests to S3
  signing_protocol                  = "sigv4"  # use AWS SigV4 signing
}


# ────────────────────────────────────────────────────────────
# CLOUDFRONT DISTRIBUTION
# ────────────────────────────────────────────────────────────
# The CDN that sits in front of S3 and serves your site.
# This is what users actually connect to.
#
# Key behaviors:
#   - Redirects HTTP → HTTPS (enforces encryption)
#   - Caches files at 300+ edge locations globally
#   - Uses your ACM certificate for your custom domain
#   - Only talks to S3 via OAC (bucket stays private)
# ────────────────────────────────────────────────────────────

resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html" # serves index.html when someone visits the root URL
  aliases             = [var.domain_name, "www.${var.domain_name}"]
  comment             = "CloudFront distribution for ${var.domain_name}"

  # origin defines where CloudFront fetches files from
  origin {
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id                = "s3-${var.bucket_name}"
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  # default_cache_behavior controls how CloudFront handles
  # requests that don't match any specific path patterns
  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]         # static site only needs read methods
    cached_methods   = ["GET", "HEAD"]         # cache responses for these methods
    target_origin_id = "s3-${var.bucket_name}" # which origin to fetch from

    # forwarded_values controls what CloudFront passes through
    # to the origin. For a static site, we don't need query
    # strings or cookies — caching is simpler without them.
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https" # HTTP → HTTPS redirect
    min_ttl                = 0                   # minimum cache time in seconds
    default_ttl            = 3600                # default cache: 1 hour
    max_ttl                = 86400               # maximum cache: 24 hours
    compress               = true                # enable gzip/brotli compression
  }

  # price_class controls which edge locations CloudFront uses.
  # PriceClass_100 = US, Canada, Europe only — cheapest option.
  # Your resume doesn't need Asian or South American edge nodes.
  price_class = "PriceClass_100"

  # restrictions — required block even if you're not restricting
  restrictions {
    geo_restriction {
      restriction_type = "none" # no geographic restrictions
    }
  }

  # viewer_certificate configures HTTPS using your ACM cert
  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.site.certificate_arn
    ssl_support_method       = "sni-only"     # Server Name Indication — standard, no extra cost
    minimum_protocol_version = "TLSv1.2_2021" # enforces modern TLS — no outdated protocols
  }

  tags = {
    Project = "cloud-resume"
  }

  # CloudFront depends on the certificate being validated first
  depends_on = [aws_acm_certificate_validation.site]
}


# ────────────────────────────────────────────────────────────
# S3 BUCKET POLICY — CloudFront access only
# ────────────────────────────────────────────────────────────
# This policy allows ONLY the CloudFront distribution to read
# from the bucket. No other access is permitted.
#
# The condition block uses aws:SourceArn to restrict access
# to this specific CloudFront distribution — even other
# CloudFront distributions in your account can't read the
# bucket.
# ────────────────────────────────────────────────────────────

resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudFrontOnly"
        Effect = "Allow"
        Principal = {
          Service = "cloudfront.amazonaws.com"
        }
        Action   = "s3:GetObject"
        Resource = "${aws_s3_bucket.site.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.site.arn
          }
        }
      }
    ]
  })
}


# ────────────────────────────────────────────────────────────
# ROUTE 53 DNS RECORDS — point domain to CloudFront
# ────────────────────────────────────────────────────────────
# A records (type "A") map a domain name to an IP address.
# With alias = true, Route 53 maps directly to an AWS
# resource (CloudFront) without needing a specific IP.
#
# We create two records:
#   - czresume.com (root domain)
#   - www.czresume.com (www subdomain)
# Both point to the same CloudFront distribution.
# ────────────────────────────────────────────────────────────

# Root domain → CloudFront
resource "aws_route53_record" "root" {
  zone_id = aws_route53_zone.main.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = aws_cloudfront_distribution.site.hosted_zone_id
    evaluate_target_health = false # CloudFront doesn't support health checks here
  }
}

# www subdomain → CloudFront
resource "aws_route53_record" "www" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "www.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = aws_cloudfront_distribution.site.hosted_zone_id
    evaluate_target_health = false
  }
}
