provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

# ACM certificate must be in us-east-1 — CloudFront only reads certs from that region.
resource "aws_acm_certificate" "heartbot" {
  provider = aws.us_east_1

  count                     = var.environment == "prod" ? 1 : 0
  domain_name               = "askheartbot.com"
  subject_alternative_names = ["www.askheartbot.com"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = local.common_tags
}

data "aws_route53_zone" "heartbot" {
  name         = "askheartbot.com"
  private_zone = false
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in(var.environment == "prod" ? aws_acm_certificate.heartbot[0].domain_validation_options : []) : dvo.domain_name => {
      name   = dvo.resource_record_name
      type   = dvo.resource_record_type
      record = dvo.resource_record_value
    }
  }

  allow_overwrite = true
  zone_id         = data.aws_route53_zone.heartbot.zone_id
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.record]
}

resource "aws_acm_certificate_validation" "heartbot" {
  provider = aws.us_east_1

  count                   = var.environment == "prod" ? 1 : 0
  certificate_arn         = aws_acm_certificate.heartbot[0].arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation : record.fqdn]
}

resource "aws_cloudfront_response_headers_policy" "security_headers" {
  provider = aws.us_east_1
  name     = "${var.project_name}-security-headers-${var.environment}"

  security_headers_config {
    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      preload                    = true
      override                   = true
    }
    content_type_options {
      override = true
    }
    frame_options {
      frame_option = "DENY"
      override     = true
    }
    xss_protection {
      mode_block = true
      protection = true
      override   = true
    }
  }
}

resource "aws_cloudfront_distribution" "frontend" {
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  price_class         = "PriceClass_100" # US, Canada, Europe only — cheapest option
  aliases             = var.environment == "prod" ? ["askheartbot.com", "www.askheartbot.com"] : []

  origin {
    domain_name              = aws_s3_bucket.frontendbucket.bucket_regional_domain_name
    origin_id                = "S3-${aws_s3_bucket.frontendbucket.bucket}"
    origin_access_control_id = aws_cloudfront_origin_access_control.frontend.id
  }

  default_cache_behavior {
    target_origin_id           = "S3-${aws_s3_bucket.frontendbucket.bucket}"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security_headers.id

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  # Serve index.html for 403/404s so React Router can handle client-side routes.
  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  dynamic "viewer_certificate" {
    for_each = var.environment == "prod" ? [1] : []
    content {
      acm_certificate_arn      = aws_acm_certificate_validation.heartbot[0].certificate_arn
      ssl_support_method       = "sni-only"
      minimum_protocol_version = "TLSv1.2_2021"
    }
  }

  dynamic "viewer_certificate" {
    for_each = var.environment == "prod" ? [] : [1]
    content {
      cloudfront_default_certificate = true
    }
  }

  tags = local.common_tags
}

resource "aws_route53_record" "root" {
  count   = var.environment == "prod" ? 1 : 0
  zone_id = data.aws_route53_zone.heartbot.zone_id
  name    = "askheartbot.com"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.frontend.domain_name
    zone_id                = aws_cloudfront_distribution.frontend.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "www" {
  count   = var.environment == "prod" ? 1 : 0
  zone_id = data.aws_route53_zone.heartbot.zone_id
  name    = "www.askheartbot.com"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.frontend.domain_name
    zone_id                = aws_cloudfront_distribution.frontend.hosted_zone_id
    evaluate_target_health = false
  }
}

output "cloudfront_domain" {
  description = "CloudFront distribution domain — use this before DNS propagates"
  value       = aws_cloudfront_distribution.frontend.domain_name
}
