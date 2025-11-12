output "cloudfront_domain" {
  value       = aws_cloudfront_distribution.cdn.domain_name
  description = "CloudFront distribution domain name"
}

output "alb_dns_name" {
  value       = aws_lb.app.dns_name
  description = "Application Load Balancer DNS name"
}

output "api_gateway_url" {
  value       = aws_apigatewayv2_api.api.api_endpoint
  description = "API Gateway endpoint URL"
}

output "s3_bucket" {
  value       = aws_s3_bucket.static.bucket
  description = "S3 static website bucket name"
}

output "dynamodb_table" {
  value       = aws_dynamodb_table.image_metadata.name
  description = "DynamoDB table for image metadata"
}

output "lambda_processor_name" {
  value       = aws_lambda_function.processor.function_name
  description = "Lambda function name for image processing"
}

output "api_endpoints" {
  value = {
    upload_image  = "http://${aws_lb.app.dns_name}/api/upload"
    list_images   = "http://${aws_lb.app.dns_name}/api/images"
    get_status    = "http://${aws_lb.app.dns_name}/api/status/<image_id>"
    get_results   = "http://${aws_lb.app.dns_name}/api/results/<image_id>"
    health_check  = "http://${aws_lb.app.dns_name}/health"
  }
  description = "Image Processing API endpoints"
}
