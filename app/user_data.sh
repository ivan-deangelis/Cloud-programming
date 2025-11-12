#!/bin/bash
set -e

# Update system
yum update -y

# Install Python 3 and pip
yum install -y python3 python3-pip

# Create application directory
mkdir -p /opt/image-processor-api
cd /opt/image-processor-api

# Create requirements.txt
cat > requirements.txt << 'EOF'
flask==3.0.0
boto3==1.34.0
EOF

# Install Python dependencies
pip3 install -r requirements.txt

# Create the API application
cat > api.py << 'EOFAPI'
${api_code}
EOFAPI

# Create systemd service
cat > /etc/systemd/system/image-api.service << 'EOFSERVICE'
[Unit]
Description=Image Processor API
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/image-processor-api
Environment="DYNAMODB_TABLE=${dynamodb_table}"
Environment="LAMBDA_PROCESSOR=${lambda_processor}"
Environment="AWS_DEFAULT_REGION=${region}"
ExecStart=/usr/bin/python3 /opt/image-processor-api/api.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOFSERVICE

# Start the service
systemctl daemon-reload
systemctl enable image-api
systemctl start image-api

# Install and configure nginx as reverse proxy
yum install -y nginx

cat > /etc/nginx/conf.d/api.conf << 'EOFNGINX'
server {
    listen 80;
    server_name _;
    
    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
EOFNGINX

# Remove default nginx config
rm -f /etc/nginx/nginx.conf
cat > /etc/nginx/nginx.conf << 'EOFNGINXMAIN'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    access_log /var/log/nginx/access.log;
    
    sendfile on;
    keepalive_timeout 65;
    
    include /etc/nginx/conf.d/*.conf;
}
EOFNGINXMAIN

# Start nginx
systemctl enable nginx
systemctl start nginx