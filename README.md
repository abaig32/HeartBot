# HeartBot — AI-Powered Cardiac Symptom Chatbot

A fully serverless RAG (Retrieval-Augmented Generation) chatbot built on AWS that helps users understand heart health symptoms. HeartBot retrieves information from a curated cardiac health knowledge base and generates grounded, citation-backed responses using Amazon Nova Micro.

> **Disclaimer:** This chatbot is for informational purposes only and is not a substitute for professional medical advice. Always consult a qualified healthcare provider for medical concerns.

---

## Architecture

```
User (Streamlit Frontend)
        │
        ▼
  API Gateway (HTTP API)
        │
        ▼
  Lambda Function (Python)
        │
        ▼
  Amazon Bedrock
  ├── Nova Micro (LLM)
  ├── Knowledge Base (RAG)
  │   ├── S3 Bucket (Text Files)
  │   └── S3 Vectors (Embeddings)
  │       └── Titan Embeddings V2
  └── Guardrails (PII Protection)
```

---

## Tech Stack

| Layer | Technology |
| --- | --- |
| Frontend | Streamlit |
| API | Amazon API Gateway (HTTP API) |
| Backend | AWS Lambda (Python 3.12) |
| LLM | Amazon Nova Micro |
| Knowledge Base | Amazon Bedrock Knowledge Bases |
| Embeddings | Amazon Titan Embeddings V2 |
| Vector Storage | Amazon S3 Vectors |
| AI Safety | Amazon Bedrock Guardrails |
| Infrastructure | Terraform |

---

## Features

* **RAG Pipeline** — retrieves relevant cardiac health content from a curated knowledge base before generating responses
* **AI Safety Layer** — Bedrock Guardrails enforce PII filtering; off-topic questions are handled by the Lambda prompt template
* **Citation Display** — responses include references to the source documents they were derived from
* **Persistent Chat History** — conversation history is maintained throughout the session
* **Medical Disclaimer** — displayed prominently on every session
* **Serverless** — fully managed, no servers to provision or maintain
* **Infrastructure as Code** — full Terraform configuration to deploy all AWS resources

---

## Project Structure

```
heartbot/
├── app.py                        # Streamlit frontend
├── api.py                        # API Gateway call logic
├── config.py                     # App settings and environment variables
├── requirements.txt              # Python dependencies
├── .env                          # Environment variables (not committed)
├── .gitignore
├── lambda/
│   └── lambda_function.py        # AWS Lambda function
└── terraform/
    ├── main.tf                   # Core infrastructure (S3, Lambda, API GW, Bedrock)
    ├── variables.tf              # Input variable definitions
    ├── outputs.tf                # Output values (API URL, resource IDs, etc.)
    └── terraform.tfvars.example  # Example variable values — copy to terraform.tfvars
```

---

## Setup & Installation

### Prerequisites

* Python 3.12+
* [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5.0
* AWS CLI configured with credentials (`aws configure`)
* AWS Account with Amazon Bedrock access enabled for:
  * `amazon.nova-micro-v1:0`
  * `amazon.titan-embed-text-v2:0`

---

### 1. Clone the repository

```bash
git clone https://github.com/abaig32/HeartBot.git
cd heartbot
```

---

### 2. Deploy AWS Infrastructure with Terraform

```bash
cd terraform

# Copy and edit the example vars file
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your preferred region, environment, etc.

# Initialise Terraform
terraform init

# Preview the changes
terraform plan

# Deploy
terraform apply
```

After `apply` completes, Terraform will print the outputs including your API Gateway URL:

```
api_gateway_url = "https://<id>.execute-api.us-east-1.amazonaws.com/chat"
```

---

### 3. Upload knowledge base documents

Upload your cardiac health source documents (`.txt`, `.pdf`, etc.) to the S3 bucket created by Terraform:

```bash
BUCKET=$(terraform output -raw s3_knowledge_base_bucket)
aws s3 sync path/to/your/documents/ s3://$BUCKET/ --region us-east-1
```

Then trigger a knowledge base ingestion job:

```bash
MSYS_NO_PATHCONV=1 aws bedrock-agent start-ingestion-job \
  --knowledge-base-id $(terraform output -raw knowledge_base_id) \
  --data-source-id $(terraform output -raw knowledge_base_data_source_id) \
  --region us-east-1
```

Wait for the ingestion to complete before proceeding:

```bash
MSYS_NO_PATHCONV=1 aws bedrock-agent list-ingestion-jobs \
  --knowledge-base-id $(terraform output -raw knowledge_base_id) \
  --data-source-id $(terraform output -raw knowledge_base_data_source_id) \
  --region us-east-1
```

---

### 4. Publish the guardrail version

Terraform creates the guardrail but the version must be published manually after every `terraform apply`. Run:

```bash
MSYS_NO_PATHCONV=1 aws bedrock create-guardrail-version \
  --guardrail-identifier $(terraform output -raw guardrail_id) \
  --region us-east-1
```

Note the `version` number returned, then update the Lambda environment variable:

```bash
MSYS_NO_PATHCONV=1 aws lambda update-function-configuration \
  --function-name heartbot-handler-dev \
  --region us-east-1 \
  --environment "Variables={KNOWLEDGE_BASE_ID=$(terraform output -raw knowledge_base_id),GUARDRAIL_ID=$(terraform output -raw guardrail_id),GUARDRAIL_VERSION=<version>,MODEL_ARN=arn:aws:bedrock:us-east-1::foundation-model/amazon.nova-micro-v1:0,ENVIRONMENT=dev}"
```

---

### 5. Configure the frontend

```bash
echo "API_URL=$(terraform output -raw api_gateway_url)" > ../.env
```

---

### 6. Install Python dependencies and run the app

```bash
cd ..
pip install -r requirements.txt
streamlit run app.py
```

The app will open at `http://localhost:8501`

---

## Terraform Configuration

All infrastructure is defined in the `terraform/` directory.

### Resources created

| Resource | Description |
| --- | --- |
| `aws_s3_bucket` | Stores knowledge base source documents |
| `aws_s3vectors_vector_bucket` | S3 Vectors bucket storing embeddings |
| `aws_s3vectors_index` | Vector index (1024-dim, float32, cosine) |
| `aws_bedrockagent_knowledge_base` | Bedrock Knowledge Base backed by S3 Vectors |
| `aws_bedrockagent_data_source` | S3 data source connected to the knowledge base |
| `aws_bedrock_guardrail` | PII protection guardrail |
| `aws_bedrock_guardrail_version` | Published guardrail version |
| `aws_lambda_function` | Python 3.12 handler (packaged from `lambda/`) |
| `aws_apigatewayv2_api` | HTTP API with CORS enabled |
| `aws_apigatewayv2_route` | `POST /chat` route |
| `aws_iam_role` (x3) | Roles for Lambda, Bedrock KB, and API Gateway CloudWatch |
| `aws_cloudwatch_log_group` (x2) | Log groups for Lambda and API Gateway |
| `aws_api_gateway_account` | Account-level CloudWatch role for API Gateway logging |

### Key variables

| Variable | Default | Description |
| --- | --- | --- |
| `aws_region` | `us-east-1` | AWS region |
| `environment` | `dev` | `dev`, `staging`, or `prod` |
| `project_name` | `heartbot` | Prefix for all resource names |
| `llm_model_id` | `amazon.nova-micro-v1:0` | Bedrock LLM model |
| `embedding_model_id` | `amazon.titan-embed-text-v2:0` | Bedrock embedding model |
| `log_retention_days` | `14` | CloudWatch log retention |
| `cors_allow_origins` | `["*"]` | Allowed CORS origins (auto-restricted in staging/prod) |

### Outputs

After `terraform apply`, the following values are printed:

| Output | Description |
| --- | --- |
| `api_gateway_url` | Full `/chat` endpoint URL for your `.env` |
| `knowledge_base_id` | Bedrock Knowledge Base ID |
| `knowledge_base_data_source_id` | Data source ID for ingestion jobs |
| `guardrail_id` | Bedrock Guardrail ID |
| `guardrail_version` | Published guardrail version |
| `s3_knowledge_base_bucket` | S3 bucket name for source documents |
| `s3_vectors_bucket_name` | S3 Vectors bucket name |
| `s3_vectors_index_arn` | ARN of the S3 Vectors index |

### Teardown

```bash
cd terraform
terraform destroy
```

---

## Guardrails & Safety

HeartBot uses a two-layer safety approach:

* **PII Filtering** — Bedrock Guardrails anonymize personal health information including names, phone numbers, email addresses, and SSNs before they reach the model
* **Prompt-based filtering** — the Lambda prompt template instructs Nova Micro to decline questions unrelated to cardiac health, avoiding false positives from Bedrock's topic policy classifier

---

## AWS Infrastructure

### Lambda

* **Runtime:** Python 3.12
* **Timeout:** 30 seconds
* **Memory:** 256 MB
* **Trigger:** API Gateway HTTP API

### Required IAM Permissions (managed by Terraform)

```json
{
  "Effect": "Allow",
  "Action": [
    "bedrock:RetrieveAndGenerate",
    "bedrock:Retrieve",
    "bedrock:InvokeModel",
    "bedrock:ApplyGuardrail"
  ],
  "Resource": [
    "arn:aws:bedrock:us-east-1::foundation-model/*",
    "arn:aws:bedrock:us-east-1:<YOUR_ACCOUNT_ID>:guardrail/*",
    "arn:aws:bedrock:us-east-1:<YOUR_ACCOUNT_ID>:knowledge-base/*"
  ]
}
```

### API Gateway

* **Type:** HTTP API
* **Method:** POST `/chat`
* **CORS:** Enabled
