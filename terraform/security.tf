# Shared with browser tests so the deployed CSP is exercised before release.
locals {
  security_headers = jsondecode(file("${path.module}/security-headers.json"))
}
resource "aws_cloudfront_response_headers_policy" "security" {
  name = "cloud-resume-security"
  security_headers_config {
    content_security_policy {
      content_security_policy = local.security_headers["Content-Security-Policy"]
      override                = true
    }
    content_type_options { override = true }
    frame_options {
      frame_option = "DENY"
      override     = true
    }
    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = false
      preload                    = false
      override                   = true
    }
  }
}
