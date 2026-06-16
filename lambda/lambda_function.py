import json
import boto3
import os
import logging
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

bedrock_agent_runtime = boto3.client('bedrock-agent-runtime', region_name='us-east-1')

KNOWLEDGE_BASE_ID = os.environ['KNOWLEDGE_BASE_ID']
GUARDRAIL_ID = os.environ['GUARDRAIL_ID']
GUARDRAIL_VERSION = os.environ['GUARDRAIL_VERSION']
MODEL_ARN = os.environ['MODEL_ARN']

CORS_HEADERS = {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type,Authorization',
    'Access-Control-Allow-Methods': 'POST, OPTIONS'
}

def lambda_handler(event, context):
    
    if event.get('httpMethod') == 'OPTIONS':
        return {
            'statusCode': 200,
            'headers': CORS_HEADERS,
            'body': ''
        }

    try:
        
        body = json.loads(event.get('body', '{}'))
        user_query = body.get('query', '')
        session_id = body.get('sessionId')

        logger.info(json.dumps({
            "event": "request_received",
            "query_length": len(user_query),
            "environment": os.environ.get("ENVIRONMENT", "unknown")
        }))

        if not user_query:
            return {
                'statusCode': 400,
                'headers': CORS_HEADERS,
                'body': json.dumps({'error': 'No query provided'})
            }

        
        kwargs = { 
            'input': {
                'text': user_query
            },
            'retrieveAndGenerateConfiguration': {
                'type': 'KNOWLEDGE_BASE',
                'knowledgeBaseConfiguration': {
                    'knowledgeBaseId': KNOWLEDGE_BASE_ID,
                    'modelArn': MODEL_ARN,
                    'generationConfiguration': {
                        'guardrailConfiguration': {
                            'guardrailId': GUARDRAIL_ID,
                            'guardrailVersion': GUARDRAIL_VERSION
                        },
                        'inferenceConfig': {
                            'textInferenceConfig': {
                                'maxTokens': 1024,
                                'temperature': 0.3,
                                'topP': 0.9
                            }
                        },
                        'promptTemplate': {
                            'textPromptTemplate': """You are a heart health assistant.
                            You MUST answer ONLY using the information in $search_results$ below.
                            If the search results are empty or insufficient, say you don't have enough information.
                            Do NOT use any general knowledge. Every claim must come from the search results.

                            $search_results$

                            Question: $query$
                            Answer:"""
                        }
                    },
                    'retrievalConfiguration': {
                        'vectorSearchConfiguration': {
                            'numberOfResults': 5
                        }
                    }
                }
            }
        }

        if session_id:
            kwargs['sessionId'] = session_id

        response = bedrock_agent_runtime.retrieve_and_generate(**kwargs)
        
        answer = response['output']['text']
        citations = response.get('citations', [])
        session_id = response.get('sessionId')
        logger.info(json.dumps({
            "event": "bedrock_response_received",
            "answer_length": len(answer),
            "citation_count": len(citations)
        }))

        return {
            'statusCode': 200,
            'headers': CORS_HEADERS,
            'body': json.dumps({
                'answer': answer,
                'citations': citations,
                'sessionId': session_id
            })
        }

    except json.JSONDecodeError:
        return {
            'statusCode': 400,
            'headers': CORS_HEADERS,
            'body': json.dumps({'error': 'Invalid JSON in request body'})
        }
    
    except ClientError as e:
        error_code = e.response['Error']['Code']
        if error_code == 'ValidationException':
            return {
                'statusCode': 400,
                'headers': CORS_HEADERS,
                'body': json.dumps({'error': f'Validation error: {str(e)}'})
            }
        elif error_code == 'AccessDeniedException':
            return {
                'statusCode': 403,
                'headers': CORS_HEADERS,
                'body': json.dumps({'error': f'Access denied: {str(e)}'})
            }
        else:
            return {
                'statusCode': 500,
                'headers': CORS_HEADERS,
                'body': json.dumps({'error': f'AWS error: {str(e)}'})
            }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': CORS_HEADERS,
            'body': json.dumps({'error': f'Internal error: {str(e)}'})
        }