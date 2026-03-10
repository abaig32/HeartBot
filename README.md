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
  └── Guardrails (AI Safety)
```

---

## Tech Stack

| Layer | Technology |
|---|---|
| Frontend | Streamlit |
| API | Amazon API Gateway (HTTP API) |
| Backend | AWS Lambda (Python 3.12) |
| LLM | Amazon Nova Micro |
| Knowledge Base | Amazon Bedrock Knowledge Bases |
| Embeddings | Amazon Titan Embeddings V2 |
| Vector Storage | Amazon S3 Vectors |
| AI Safety | Amazon Bedrock Guardrails |
| Infrastructure | Terraform *(coming soon)* |

---

## Features

- **RAG Pipeline** — retrieves relevant cardiac health content from a curated knowledge base before generating responses
- **AI Safety Layer** — Bedrock Guardrails enforce denied topics, PII filtering, and contextual grounding to ensure medically responsible responses
- **Citation Display** — responses include references to the source documents they were derived from
- **Persistent Chat History** — conversation history is maintained throughout the session
- **Medical Disclaimer** — displayed prominently on every session
- **Serverless** — fully managed, no servers to provision or maintain

---

## Project Structure

```
heartbot/
├── app.py                  # Streamlit frontend
├── api.py                  # API Gateway call logic
├── config.py               # App settings and environment variables
├── requirements.txt        # Python dependencies
├── .env                    # Environment variables (not committed)
├── .gitignore
└── lambda/
    └── lambda_function.py  # AWS Lambda function (deployed manually on AWS)
```

---

## Setup & Installation

### Prerequisites
- Python 3.12+
- AWS Account with Bedrock access enabled
- Amazon Bedrock Knowledge Base configured
- API Gateway endpoint deployed

### 1. Clone the repository
```bash
git clone https://github.com/abaig32/HeartBot.git
cd heartbot
```

### 2. Install dependencies
```bash
pip install -r requirements.txt
```

### 3. Configure environment variables
Create a `.env` file in the root directory:
```
API_URL=https://your-api-gateway-url/chat
```

### 4. Run the app
```bash
streamlit run app.py
```

The app will open at `http://localhost:8501`

---

## Guardrails & Safety

HeartBot uses Amazon Bedrock Guardrails to enforce the following policies:

- **Denied Topics** — blocks off-topic medical advice, definitive diagnoses, prescription recommendations, legal advice, and impersonation of medical professionals
- **PII Filtering** — anonymizes personal health information including names, dates of birth, SSNs, and insurance details
- **Contextual Grounding** — ensures responses are grounded in the knowledge base content

---

## AWS Infrastructure

### Lambda
- **Runtime:** Python 3.12
- **Timeout:** 30 seconds
- **Memory:** 256 MB
- **Trigger:** API Gateway HTTP API

### Required IAM Permissions
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
- **Type:** HTTP API
- **Method:** POST `/chat`
- **CORS:** Enabled
