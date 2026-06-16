import json
import pytest
from unittest.mock import patch, MagicMock
import sys
import os

# lambda_function reads these at module level, so they must exist before import.
os.environ['KNOWLEDGE_BASE_ID'] = 'ABCDEF1234'
os.environ['GUARDRAIL_ID'] = 'GHIJKL5678'
os.environ['GUARDRAIL_VERSION'] = '1'
os.environ['MODEL_ARN'] = 'arn:aws:bedrock:us-east-1::foundation-model/test'

# lambda/ is not a package; pytest won't discover it without this path injection.
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))
import lambda_function


@pytest.fixture
def valid_event():
    return {
        "body": json.dumps({"query": "What are symptoms of a heart attack?"})
    }

@pytest.fixture
def mock_bedrock_response():
    return {
        "output": {
            "text": "Common symptoms include chest pain and shortness of breath."
        },
        "citations": [
            {
                "retrievedReferences": [
                    {
                        "location": {
                            "s3Location": {
                                "uri": "s3://my-bucket/heart-attack-guide.pdf"
                            }
                        }
                    }
                ]
            }
        ],
        "sessionId": {
            "text": "abc-123"
        }
    }


def test_sessionid_key(valid_event, mock_bedrock_response):
    with patch('lambda_function.bedrock_agent_runtime') as mock_client:
        mock_client.retrieve_and_generate.return_value = mock_bedrock_response

        result = lambda_function.lambda_handler(valid_event, {})

        result = json.loads(result['body'])

        assert result["sessionId"] == {"text": "abc-123"}

def test_valid_query_returns_200(valid_event, mock_bedrock_response):
    with patch('lambda_function.bedrock_agent_runtime') as mock_client:
        mock_client.retrieve_and_generate.return_value = mock_bedrock_response

        result = lambda_function.lambda_handler(valid_event, {})

        assert result['statusCode'] == 200
        body = json.loads(result['body'])
        assert 'answer' in body
        assert 'citations' in body
        assert "chest pain" in body['answer']


def test_empty_query_returns_400():
    event = {"body": json.dumps({"query": ""})}

    result = lambda_function.lambda_handler(event, {})

    assert result['statusCode'] == 400


def test_missing_body_returns_400():
    result = lambda_function.lambda_handler({}, {})

    assert result['statusCode'] == 400


def test_bedrock_error_returns_500(valid_event):
    with patch('lambda_function.bedrock_agent_runtime') as mock_client:
        mock_client.retrieve_and_generate.side_effect = Exception("Bedrock unavailable")

        result = lambda_function.lambda_handler(valid_event, {})

        assert result['statusCode'] == 500

def test_invalid_json_returns_400():
    event = {"body": "This is random text"}
    result = lambda_function.lambda_handler(event, {})
    assert result["statusCode"] == 400

def test_options_request_returns_200():
    event = {"httpMethod": "OPTIONS"}
    result = lambda_function.lambda_handler(event, {})
    assert result['statusCode'] == 200