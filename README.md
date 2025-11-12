# 🧭 AWS Web Application Infrastructure (Terraform)

This project provisions a **complete AWS architecture** for a modern web application using **Terraform**.  
It includes both **static and dynamic content delivery**, **scalable compute**, and **serverless APIs**, all fronted by a global **CloudFront CDN**.

---

### 🏗️ Core Components

| Layer | AWS Service | Purpose |
|:------|:-------------|:---------|
| **Edge** | **CloudFront** | Global CDN that routes traffic based on URL paths: <br> `/` → S3, `/app/*` → ALB (EC2), `/api/*` → API Gateway (Lambda) |
| **Static Hosting** | **S3 (Website)** | Stores and serves static web assets (HTML, CSS, JS) publicly |
| **Backend Compute** | **EC2 + Auto Scaling + ALB** | Runs the main web application dynamically across multiple Availability Zones |
| **Serverless API** | **Lambda + API Gateway (HTTP API)** | Handles `/api/*` requests using a lightweight serverless function |
| **Networking** | **VPC + Subnets + IGW** | Provides network isolation and public access via two subnets in different AZs |
| **Security** | **Security Groups** | Control inbound/outbound traffic for ALB and EC2 instances |
| **Database** | **DynamoDB** | For learning purposes, for lambda+ec2 use case
---

## ⚙️ Key Terraform Components

### 1️⃣ **VPC and Networking**
- **VPC**: Provides a private, isolated network (`10.0.0.0/16`).
- **Subnets**: Two *public subnets* across two availability zones.
- **Internet Gateway + Route Tables**: Enables public internet access.
- **Auto-scaling Groups**: Each subnet hosts EC2 instances behind the ALB.

### 2️⃣ **EC2 + Auto Scaling + Load Balancer**
- **Launch Template**: Defines an Amazon Linux 2023 EC2 with a simple NGINX web server (`t3.micro`).
- **Auto Scaling Group (ASG)**: Maintains 2 EC2 instances (1 per subnet).
- **Application Load Balancer (ALB)**: Balances HTTP requests across instances.
- **Target Group**: Health checks `/` on port 80.

**Result:**  
App is accessible via the ALB’s DNS name and scales automatically.

---

### 3️⃣ **S3 Static Hosting**
- S3 bucket with website hosting enabled.
- Public access (for simplicity) using ACL and bucket policy.
- Serves static web assets like `index.html`.

**Access example:**  
`http://<bucket-name>.s3-website-<region>.amazonaws.com`

---

### 4️⃣ **Lambda + API Gateway**
- **Lambda Function** (`lambda_function/handler.py`):
  ```python
   def lambda_handler(event, context):
      return {
         "statusCode": 200,
         "headers": {"Content-Type": "application/json"},
         "body": '{"message":"Hello from Lambda via API Gateway!"}'
      }
  ```
- **IAM Role**: Grants the Lambda basic execution permissions.
- **API Gateway (HTTP API)**: Proxies `/api/*` requests directly to the Lambda.
- **Lambda Permission**: Allows API Gateway to invoke the function.

**Access example:**  
`https://<api-id>.execute-api.<region>.amazonaws.com/api/test`

---

### 5️⃣ **CloudFront Distribution**
CloudFront acts as a global CDN and smart router:

| Path | Origin | Behavior |
|:------|:--------|:----------|
| `/api/*` | API Gateway endpoint | No caching, forwards all headers and methods |
| `/app/*` | ALB DNS | No caching, used for dynamic web app pages |
| `/` (default) | S3 Website | Cached (static assets, HTML, JS, etc.) |

**Default root object:** `index.html`  

---

## 🧩 Folder Structure

```
tf-aws-app/
├── main.tf                 # Main infrastructure definition
├── variables.tf            # Configurable inputs (region, CIDRs, etc.)
├── outputs.tf              # Outputs (URLs, endpoints, etc.)
└── lambda_function/
    └── handler.py          # Python Lambda source code
```

---

## 🚀 Deployment Instructions

### Prerequisites
- AWS account with appropriate permissions
- AWS CLI configured (`aws configure`)
- Env variables setup for aws cli
- Terraform ≥ 1.6.0 installed
- S3 bucket name and region available

---

### 1️⃣ Initialize Terraform
```bash
terraform init
```

### 2️⃣ Validate the configuration
```bash
terraform validate
```

### 3️⃣ Preview what will be created
```bash
terraform plan
```

### 4️⃣ Deploy the infrastructure
```bash
terraform apply
```

Approve when prompted (`yes`).

---

## 🧾 Outputs

After successful deployment, Terraform prints (main ones, lambda+ec2 use case ones are excluded):

| Output | Description |
|:--------|:-------------|
| `cloudfront_domain` | Main CDN URL (entry point for users) |
| `alb_dns_name` | Internal application endpoint (via ALB) |
| `api_gateway_url` | API endpoint (Lambda backend) |
| `s3_bucket` | Static assets bucket name |

Example:
```
cloudfront_domain = d12345abcdef.cloudfront.net
alb_dns_name      = demo-aws-app-alb-123456789.eu-west-1.elb.amazonaws.com
api_gateway_url   = https://abc123.execute-api.eu-west-1.amazonaws.com
s3_bucket         = demo-aws-app-static-a1b2c3d4
```

---

## 🔍 Testing

1. **Visit CloudFront:**

   ```
   https://<cloudfront_domain>/
   ```
   → should show your `index.html`.

2. **Test the EC2/ALB Application:**

    ```bash
    curl -i "https://$(terraform output -raw cloudfront_domain)/app/health"
    ```

    → should return the NGINX welcome page or your custom application response.

    **Alternative - Direct ALB access:**

    ```bash
    curl -i "http://$(terraform output -raw alb_dns_name)/health"
    ```

    → bypasses CloudFront and hits the ALB directly.

3. **Test the Lambda API:**
    ```bash
    curl -i "https://$(terraform output -raw cloudfront_domain)/api/test"
    ```
    → returns `{ "message": "Hello from Lambda" }`.

4. **Test the EC2+Lambda Use Case**
    ```bash
    ./test-api.sh
    ```

---

## 🧹 Cleanup

To destroy all resources and avoid charges:
```bash
terraform destroy
```

---

## 🧑‍💻 Author

Ivan De Angelis
