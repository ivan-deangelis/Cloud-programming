#!/bin/bash

# Test script for Image Processing API
# This script demonstrates the complete workflow using curl

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Get Cloudfront domain from Terraform output
echo -e "${BLUE}Getting Cloudfront domain from Terraform...${NC}"
CLOUDFRONT_DOMAIN="$(terraform output -raw cloudfront_domain 2>/dev/null || echo "")"

if [ -z "$CLOUDFRONT_DOMAIN" ]; then
    echo -e "${RED}Error: Could not get Cloudfront domain. Make sure you've run 'terraform apply' first.${NC}"
    exit 1
fi

# if not error, let's append the /app path from ec2
CLOUDFRONT_DOMAIN="$(echo $CLOUDFRONT_DOMAIN)/app"

echo -e "${GREEN}Cloudfront Domain: ${CLOUDFRONT_DOMAIN}${NC}\n"
# Test 1: Health Check
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Test 1: Health Check${NC}"
echo -e "${BLUE}========================================${NC}"
echo "curl http://${CLOUDFRONT_DOMAIN}/health"
curl -s http://${CLOUDFRONT_DOMAIN}/health | python3 -m json.tool
echo -e "\n"

# Wait a moment
sleep 1

# Test 2: Upload Image (Simulated)
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Test 2: Upload Image for Processing${NC}"
echo -e "${BLUE}========================================${NC}"
echo "curl -X POST http://${CLOUDFRONT_DOMAIN}/api/upload -H \"Content-Type: application/json\" -d '{\"imageName\":\"sunset-beach.jpg\"}'"
UPLOAD_RESPONSE=$(curl -s -X POST http://${CLOUDFRONT_DOMAIN}/api/upload \
  -H "Content-Type: application/json" \
  -d '{"imageName":"sunset-beach.jpg","imageUrl":"https://example.com/sunset.jpg"}')

echo "$UPLOAD_RESPONSE" | python3 -m json.tool

# Extract image ID
IMAGE_ID=$(echo "$UPLOAD_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('imageId', ''))" 2>/dev/null || echo "")
echo -e "\n${GREEN}Image ID: ${IMAGE_ID}${NC}\n"

if [ -z "$IMAGE_ID" ] || [ "$IMAGE_ID" == "null" ]; then
    echo -e "${RED}Error: Failed to upload image${NC}"
    exit 1
fi

# Test 3: Check Status (should be processing)
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Test 3: Check Processing Status${NC}"
echo -e "${BLUE}========================================${NC}"
echo "curl http://${CLOUDFRONT_DOMAIN}/api/status/${IMAGE_ID}"
curl -s http://${CLOUDFRONT_DOMAIN}/api/status/${IMAGE_ID} | python3 -m json.tool
echo -e "\n"

# Test 4: Wait for processing and get results
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Test 4: Wait for Processing to Complete${NC}"
echo -e "${BLUE}========================================${NC}"
echo -e "${YELLOW}Waiting for Lambda to process image (this may take a few seconds)...${NC}\n"

MAX_ATTEMPTS=15
ATTEMPT=0
STATUS="processing"

while [ "$STATUS" == "processing" ] && [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    sleep 2
    ATTEMPT=$((ATTEMPT + 1))
    echo -e "${YELLOW}Attempt $ATTEMPT/$MAX_ATTEMPTS...${NC}"
    
    STATUS_RESPONSE=$(curl -s http://${CLOUDFRONT_DOMAIN}/api/status/${IMAGE_ID})
    STATUS=$(echo "$STATUS_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('status', ''))" 2>/dev/null || echo "processing")
    
    if [ "$STATUS" == "complete" ]; then
        echo -e "${GREEN}✓ Processing complete!${NC}\n"
        break
    elif [ "$STATUS" == "failed" ]; then
        echo -e "${RED}✗ Processing failed!${NC}"
        echo "$STATUS_RESPONSE" | python3 -m json.tool
        exit 1
    fi
done

if [ "$STATUS" != "complete" ]; then
    echo -e "${YELLOW}Warning: Processing is still ongoing. Showing current status...${NC}"
fi

# Test 5: Get Results
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Test 5: Get Analysis Results${NC}"
echo -e "${BLUE}========================================${NC}"
echo "curl http://${CLOUDFRONT_DOMAIN}/api/results/${IMAGE_ID}"
RESULTS=$(curl -s http://${CLOUDFRONT_DOMAIN}/api/results/${IMAGE_ID})
echo "$RESULTS" | python3 -m json.tool
echo -e "\n"

sleep 2

# Test 6: List All Images
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Test 6: List All Images${NC}"
echo -e "${BLUE}========================================${NC}"
echo "curl http://${CLOUDFRONT_DOMAIN}/api/images"
curl -s http://${CLOUDFRONT_DOMAIN}/api/images | python3 -m json.tool
echo -e "\n"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✓ All tests completed successfully!${NC}"
echo -e "${GREEN}========================================${NC}"
