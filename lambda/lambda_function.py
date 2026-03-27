import json
import boto3
import os

# Clients
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

        if not user_query:
            return {
                'statusCode': 400,
                'headers': CORS_HEADERS,
                'body': json.dumps({'error': 'No query provided'})
            }

        
        response = bedrock_agent_runtime.retrieve_and_generate(
            input={
                'text': user_query
            },
            retrieveAndGenerateConfiguration={
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
                                'maxTokens': 512,
                                'temperature': 0.3,
                                'topP': 0.9
                            }
                        },
                        'promptTemplate': {
                            'textPromptTemplate': """You are a heart health assistant. 
                            Use only the provided information to answer questions about heart symptoms.
                            Always recommend consulting a doctor for medical concerns.
                            If the question is not related to heart health, politely decline to answer.

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
        )

        print("API Response:", json.dumps(response, indent=2, default=str))
        
        answer = response['output']['text']
        citations = response.get('citations', [])

        return {
            'statusCode': 200,
            'headers': CORS_HEADERS,
            'body': json.dumps({
                'answer': answer,
                'citations': citations,
            })
        }

    except json.JSONDecodeError:
        return {
            'statusCode': 400,
            'headers': CORS_HEADERS,
            'body': json.dumps({'error': 'Invalid JSON in request body'})
        }
    except bedrock_agent_runtime.exceptions.ValidationException as e:
        return {
            'statusCode': 400,
            'headers': CORS_HEADERS,
            'body': json.dumps({'error': f'Validation error: {str(e)}'})
        }
    except bedrock_agent_runtime.exceptions.AccessDeniedException as e:
        return {
            'statusCode': 403,
            'headers': CORS_HEADERS,
            'body': json.dumps({'error': f'Access denied: {str(e)}'})
        }
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': CORS_HEADERS,
            'body': json.dumps({'error': f'Internal error: {str(e)}'})
        }