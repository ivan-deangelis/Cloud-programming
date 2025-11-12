import json
import boto3
import os
from datetime import datetime
import time

# Initialize AWS clients
dynamodb = boto3.resource('dynamodb')

# Get DynamoDB table name from environment variable
TABLE_NAME = os.environ.get('DYNAMODB_TABLE_NAME', 'demo-aws-app-image-metadata')
table = dynamodb.Table(TABLE_NAME)

def handler(event, context):
    """
    Lambda function to simulate ML image processing.
    This is a demonstration that shows the async processing pattern.
    
    Expected event structure:
    {
        "imageId": "unique-image-id",
        "imageName": "photo.jpg",
        "imageUrl": "https://example.com/photo.jpg"
    }
    """
    try:
        print(f"Received event: {json.dumps(event)}")
        
        # Extract parameters
        image_id = event.get('imageId')
        image_name = event.get('imageName', 'unknown.jpg')
        image_url = event.get('imageUrl', 'simulated')
        
        if not image_id:
            raise ValueError("Missing required parameter: imageId")
        
        # Simulate ML processing time
        processing_time = 2
        print(f"Processing image: {image_name} (ID: {image_id})")
        time.sleep(processing_time)
        
        # Simple simulated ML results
        ml_results = {
            "model_version": "v1.0-demo"
        }
        
        # Update DynamoDB with results
        table.update_item(
            Key={'imageId': image_id},
            UpdateExpression='SET #status = :status, #results = :results, #updated = :updated',
            ExpressionAttributeNames={
                '#status': 'status',
                '#results': 'results',
                '#updated': 'updatedAt'
            },
            ExpressionAttributeValues={
                ':status': 'complete',
                ':results': ml_results,
                ':updated': datetime.utcnow().isoformat()
            }
        )
        
        print(f"Successfully processed image {image_id}")
        
        return {
            'statusCode': 200,
            'body': json.dumps({
                'message': 'Image processed successfully',
                'imageId': image_id,
                'results': ml_results
            })
        }
        
    except Exception as e:
        print(f"Error processing image: {str(e)}")
        
        # Update DynamoDB with error status
        if 'image_id' in locals():
            try:
                table.update_item(
                    Key={'imageId': image_id},
                    UpdateExpression='SET #status = :status, #error = :error, #updated = :updated',
                    ExpressionAttributeNames={
                        '#status': 'status',
                        '#error': 'error',
                        '#updated': 'updatedAt'
                    },
                    ExpressionAttributeValues={
                        ':status': 'failed',
                        ':error': str(e),
                        ':updated': datetime.utcnow().isoformat()
                    }
                )
            except Exception as db_error:
                print(f"Error updating DynamoDB: {str(db_error)}")
        
        return {
            'statusCode': 500,
            'body': json.dumps({
                'message': 'Error processing image',
                'error': str(e)
            })
        }
