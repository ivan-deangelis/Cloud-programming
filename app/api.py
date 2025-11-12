from flask import Flask, request, jsonify
import boto3
import uuid
import json
import os
from datetime import datetime

app = Flask(__name__)

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')
lambda_client = boto3.client('lambda')

# Get configuration from environment variables
DYNAMODB_TABLE = os.environ.get('DYNAMODB_TABLE_NAME') or os.environ.get('DYNAMODB_TABLE')
LAMBDA_PROCESSOR = os.environ.get('LAMBDA_PROCESSOR_NAME') or os.environ.get('LAMBDA_PROCESSOR')

# DynamoDB table reference
table = dynamodb.Table(DYNAMODB_TABLE) if DYNAMODB_TABLE else None

@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'service': 'image-processing-api',
        'timestamp': datetime.utcnow().isoformat()
    })


@app.route('/api/upload', methods=['POST'])
def upload_image():
    """
    Simulate image upload and trigger asynchronous processing.
    
    Expected JSON payload:
    {
        "imageName": "photo.jpg",
        "imageUrl": "https://example.com/photo.jpg" (optional)
    }
    
    Returns: imageId and initial status
    """
    try:
        # Get JSON data
        data = request.get_json()
        
        if not data:
            return jsonify({'error': 'No JSON data provided'}), 400
        
        image_name = data.get('imageName')
        image_url = data.get('imageUrl', 'simulated://image-data')
        
        if not image_name:
            return jsonify({'error': 'imageName is required in JSON body'}), 400
        
        # Generate unique image ID
        image_id = str(uuid.uuid4())
        
        # Create metadata record in DynamoDB
        timestamp = datetime.utcnow().isoformat()
        table.put_item(
            Item={
                'imageId': image_id,
                'status': 'processing',
                'imageName': image_name,
                'imageUrl': image_url,
                'createdAt': timestamp,
                'updatedAt': timestamp
            }
        )
        
        # Invoke Lambda asynchronously
        lambda_payload = {
            'imageId': image_id,
            'imageName': image_name,
            'imageUrl': image_url
        }
        
        lambda_client.invoke(
            FunctionName=LAMBDA_PROCESSOR,
            InvocationType='Event',  # Asynchronous invocation
            Payload=json.dumps(lambda_payload)
        )
        
        return jsonify({
            'message': 'Image processing started',
            'imageId': image_id,
            'status': 'processing',
            'imageName': image_name,
            'createdAt': timestamp
        }), 201
        
    except Exception as e:
        app.logger.error(f"Error processing request: {str(e)}")
        return jsonify({'error': f'Request failed: {str(e)}'}), 500


@app.route('/api/status/<image_id>', methods=['GET'])
def get_status(image_id):
    """
    Get the processing status of an image.
    
    Returns: current status and metadata
    """
    try:
        response = table.get_item(Key={'imageId': image_id})
        
        if 'Item' not in response:
            return jsonify({'error': 'Image not found'}), 404
        
        item = response['Item']
        
        # Build response
        result = {
            'imageId': image_id,
            'status': item.get('status'),
            'imageName': item.get('imageName'),
            'imageUrl': item.get('imageUrl'),
            'createdAt': item.get('createdAt'),
            'updatedAt': item.get('updatedAt')
        }
        
        # Include error if present
        if 'error' in item:
            result['error'] = item['error']
        
        return jsonify(result), 200
        
    except Exception as e:
        app.logger.error(f"Error getting status: {str(e)}")
        return jsonify({'error': f'Failed to get status: {str(e)}'}), 500


@app.route('/api/results/<image_id>', methods=['GET'])
def get_results(image_id):
    """
    Get the analysis results for a processed image.
    
    Returns: full results including ML inference output
    """
    try:
        response = table.get_item(Key={'imageId': image_id})
        
        if 'Item' not in response:
            return jsonify({'error': 'Image not found'}), 404
        
        item = response['Item']
        
        # Check if processing is complete
        if item.get('status') != 'complete':
            return jsonify({
                'imageId': image_id,
                'status': item.get('status'),
                'message': 'Processing not yet complete'
            }), 202  # Accepted but not ready
        
        # Return full results
        result = {
            'imageId': image_id,
            'status': item.get('status'),
            'imageName': item.get('imageName'),
            'imageUrl': item.get('imageUrl'),
            'results': item.get('results', {}),
            'createdAt': item.get('createdAt'),
            'updatedAt': item.get('updatedAt')
        }
        
        return jsonify(result), 200
        
    except Exception as e:
        app.logger.error(f"Error getting results: {str(e)}")
        return jsonify({'error': f'Failed to get results: {str(e)}'}), 500


@app.route('/api/images', methods=['GET'])
def list_images():
    """
    List all images and their status.
    
    Returns: list of all images with basic info
    """
    try:
        response = table.scan()
        items = response.get('Items', [])
        
        # Sort by creation time (most recent first)
        items.sort(key=lambda x: x.get('createdAt', ''), reverse=True)
        
        # Return simplified list
        results = [
            {
                'imageId': item.get('imageId'),
                'imageName': item.get('imageName'),
                'status': item.get('status'),
                'createdAt': item.get('createdAt')
            }
            for item in items
        ]
        
        return jsonify({
            'count': len(results),
            'images': results
        }), 200
        
    except Exception as e:
        app.logger.error(f"Error listing images: {str(e)}")
        return jsonify({'error': f'Failed to list images: {str(e)}'}), 500


if __name__ == '__main__':
    # Bind to 5000 so Nginx can proxy :80 -> :5000
    app.run(host='0.0.0.0', port=5000, debug=False)
