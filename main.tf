terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40"
    }
  }
}

provider "aws" {
  region = var.region
}

locals {
  project = var.project
}

####################
# Networking (VPC) #
####################

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = { Name = "${local.project}-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${local.project}-igw" }
}

resource "aws_subnet" "public" {
  for_each = {
    a = { az = var.azs[0], cidr = var.public_subnets[0] }
    b = { az = var.azs[1], cidr = var.public_subnets[1] }
  }
  vpc_id                  = aws_vpc.main.id
  availability_zone       = each.value.az
  cidr_block              = each.value.cidr
  map_public_ip_on_launch = true
  tags = { Name = "${local.project}-public-${each.key}" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "${local.project}-public-rt" }
}

resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  route_table_id = aws_route_table.public.id
  subnet_id      = each.value.id
}

#######################
# ALB + EC2 + ASG     #
#######################

resource "aws_security_group" "alb" {
  name        = "${local.project}-alb-sg"
  description = "Allow HTTP from anywhere"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${local.project}-alb-sg" }
}

resource "aws_security_group" "ec2" {
  name        = "${local.project}-ec2-sg"
  description = "Allow HTTP from ALB"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "HTTP from ALB"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = { Name = "${local.project}-ec2-sg" }
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

resource "aws_launch_template" "web" {
  name_prefix   = "${local.project}-lt-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"
  user_data = base64encode(<<-EOF
              #!/bin/bash
              dnf -y install nginx
              echo "<h1>${local.project} - EC2</h1>" > /usr/share/nginx/html/index.html
              systemctl enable nginx
              systemctl start nginx
            EOF
  )
  vpc_security_group_ids = [aws_security_group.ec2.id]
  tags = { Name = "${local.project}-lt" }
}

resource "aws_lb" "app" {
  name               = "${local.project}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [for s in aws_subnet.public : s.id]
  tags               = { Name = "${local.project}-alb" }
}

resource "aws_lb_target_group" "app" {
  name        = "${local.project}-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"
  health_check {
    path = "/"
    port = "traffic-port"
  }
  tags = { Name = "${local.project}-tg" }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_autoscaling_group" "web" {
  name                = "${local.project}-asg"
  desired_capacity    = 2
  max_size            = 2
  min_size            = 2
  vpc_zone_identifier = [for s in aws_subnet.public : s.id]

  launch_template {
    id      = aws_launch_template.web.id
    version = "$Latest"
  }

  target_group_arns = [aws_lb_target_group.app.arn]
  health_check_type = "ELB"

  tag {
    key                 = "Name"
    value               = "${local.project}-web"
    propagate_at_launch = true
  }
}

################
# S3 (Static)  #
################

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "static" {
  bucket = "${local.project}-static-${random_id.suffix.hex}"
  tags   = { Name = "${local.project}-static" }
}

# Block public access at the bucket level
resource "aws_s3_bucket_public_access_block" "static" {
  bucket                  = aws_s3_bucket.static.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Ownership controls
resource "aws_s3_bucket_ownership_controls" "static" {
  bucket = aws_s3_bucket.static.id
  rule { object_ownership = "BucketOwnerPreferred" }
}

# Upload index.html in the bucket
resource "aws_s3_object" "index_html" {
  bucket       = aws_s3_bucket.static.id
  key          = "index.html"
  source       = "${path.module}/web/index.html"
  content_type = "text/html"
  etag         = filemd5("${path.module}/web/index.html")
}

########################
# API Gateway + Lambda  #
#########################

resource "aws_iam_role" "lambda_exec" {
  name               = "${local.project}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Create zip from external Python file
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda_function/handler.py"
  output_path = "${path.module}/lambda_function.zip"
}

resource "aws_lambda_function" "hello" {
  function_name    = "${local.project}-hello"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "handler.handler"          # file: handler.py | func: handler
  runtime          = "python3.12"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
}

# API Gateway (HTTP API)
resource "aws_apigatewayv2_api" "api" {
  name          = "${local.project}-api"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.hello.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "api_proxy" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "ANY /api/{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGWInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.hello.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*/*"
}

###############################
# CloudFront OAC (for S3 origin)
###############################

resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "${local.project}-oac"
  description                       = "OAC for ${local.project} S3 origin"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_origin_request_policy" "api_minimal" {
  name = "${local.project}-api-minimal"

  headers_config {
    header_behavior = "none"
  }

  cookies_config {
    cookie_behavior = "none"
  }

  query_strings_config {
    query_string_behavior = "all"
  }
}

#####################
# CloudFront (3 origins)
#####################

# derive API domain (strip https://)
locals {
  api_domain = replace(aws_apigatewayv2_api.api.api_endpoint, "https://", "")
}

data "aws_cloudfront_cache_policy" "cached" {
  name = "Managed-CachingOptimized"
}
data "aws_cloudfront_cache_policy" "disabled" {
  name = "Managed-CachingDisabled"
}
data "aws_cloudfront_origin_request_policy" "allviewer" {
  name = "Managed-AllViewer"
}

resource "aws_cloudfront_distribution" "cdn" {
  enabled             = true
  comment             = "${local.project} distribution"
  default_root_object = "index.html"

# --- ORIGIN 1: S3 (private via OAC) ---
  origin {
    origin_id   = "s3-static"
    domain_name = aws_s3_bucket.static.bucket_regional_domain_name

    s3_origin_config {
      origin_access_identity = ""
    }

    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }


  # --- ORIGIN 2: ALB (EC2 app) ---
  origin {
    origin_id   = "alb-app"
    domain_name = aws_lb.app.dns_name
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # --- ORIGIN 3: API Gateway (Lambda) ---
  origin {
    origin_id   = "apigw"
    domain_name = local.api_domain
    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # Default: static site
  default_cache_behavior {
    target_origin_id       = "s3-static"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    cache_policy_id        = data.aws_cloudfront_cache_policy.cached.id
  }

  # /app/* -> ALB
  ordered_cache_behavior {
    path_pattern             = "/app/*"
    target_origin_id         = "alb-app"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = data.aws_cloudfront_cache_policy.disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.allviewer.id
  }

  # /api/* -> API Gateway
  ordered_cache_behavior {
    path_pattern             = "/api/*"
    target_origin_id         = "apigw"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    cache_policy_id          = data.aws_cloudfront_cache_policy.disabled.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.api_minimal.id
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = { Name = "${local.project}-cdn" }
}

#############################################
# S3 policy: allow reads only from this CDN #
#############################################

resource "aws_s3_bucket_policy" "oac_read" {
  bucket = aws_s3_bucket.static.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid: "AllowCloudFrontServicePrincipalReadOnly",
        Effect: "Allow",
        Principal: { Service: "cloudfront.amazonaws.com" },
        Action: ["s3:GetObject"],
        Resource: ["${aws_s3_bucket.static.arn}/*"],
        Condition: {
          StringEquals: {
            "AWS:SourceArn": aws_cloudfront_distribution.cdn.arn
          }
        }
      }
    ]
  })
}
