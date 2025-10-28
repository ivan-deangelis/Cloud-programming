output "cloudfront_domain" {
  value = aws_cloudfront_distribution.cdn.domain_name
}

output "alb_dns_name" {
  value = aws_lb.app.dns_name
}

output "api_gateway_url" {
  value = aws_apigatewayv2_api.api.api_endpoint
}

output "s3_bucket" {
  value = aws_s3_bucket.static.bucket
}
