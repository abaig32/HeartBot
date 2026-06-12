# HeartBot — AI-Powered Cardiac Health Assistant

> A fully serverless RAG chatbot built on AWS that helps users understand heart health. Live at [askheartbot.com](https://askheartbot.com)

## Architecture

![HeartBot Architecture](architecture.png)

## Overview

HeartBot is a serverless RAG AI cardiac chatbot fully hosted on AWS. It helps users understand their cardiac health, it can answer questions about heart attack symptoms, hypertension, lifestyle changes, and other cardiovascular topics. It allows for a centralized way to get grounded, citation-backed information without having to search several different sources because it retrieves information from vetted health content and generates responses using Amazon Nova Micro with AI safety guardrails to ensure medically responsible answers. I built this project out of a genuine interest in healthcare technology and to demonstrate end-to-end cloud engineering on a real, deployed product.

## Tech Stack

| Layer | Technology |
|---|---|
| Frontend | React |
| CDN | Amazon CloudFront |
| DNS | Amazon Route 53 |
| API | Amazon API Gateway |
| Compute | AWS Lambda (Python 3.12) |
| LLM | Amazon Nova Micro |
| Knowledge Base | Amazon Bedrock Knowledge Bases |
| Embeddings | Amazon Titan Embeddings V2 |
| Vector Store | Amazon S3 Vectors |
| Storage | Amazon S3 |
| AI Safety | Amazon Bedrock Guardrails |
| IaC | Terraform |
| CI/CD | GitHub Actions |
| Monitoring | Amazon CloudWatch + SNS |

## Key Design Decisions

**Origin Access Control**
For the frontend hosting, I chose CloudFront with Origin Access Control over making the S3 bucket publicly accessible. OAC signs every request between CloudFront and S3 using AWS Signature Version 4, this ensures that the bucket is never accessible publicly. I chose OAC over the older Origin Access Identity because it's more secure, is the recommended AWS approach, and supports all the S3 features including KMS Encryption. 

**RAG Pipeline**
For the prompting and response generation, I chose to use a RAG pipeline over pure prompting. RAG or Retrieval Augmented Generation pulls information from a dedicated knowledge base that contains cited and sourced documentation about a specific topic. Compared to pure prompting, which uses the model itself to generate responses or searching the web, RAG allows for the response to use primary information that provides the best experience for users. Since HeartBot is a healthcare project, it has to provide the most accurate information. RAG allows for that as I can provide it a knowledge base of accurate information.

**Remote Terraform State**
For the deployment, I chose to have a remote Terraform state. I chose this over having a local state because it will protect the state from alteration locally and it will allow for the state to be fetched to other computers if I have collaborators on the project. The backend uses S3's native lockfile to prevent concurrent applies, ensuring the infrastructure is never modified by two processes simultaneously. 

**Two-Layer AI Safety**
I used a two-layer AI safety approach by using Bedrock Guardrails for PII filtering and prompt engineering in the Lambda to restrict off-topic questions. I needed the guardrails to ensure that sensitive information could not be displayed by the model. This ensures things like SSN, phone numbers, and email remain anonymous whenever HeartBot generates a response. I needed to have the prompt engineering to ensure that HeartBot does not provide invalid information like diagnosis for users and only uses the information from the knowledge base. This makes sure that HeartBot only provides general information about a specific cardiac issue rather than diagnosing a user with a condition.

## Problems solved

**S3 Vectors 2048-byte metadata limit**
Bedrock Knowledge Base ingestion was failing silently. The root cause was S3 Vectors enforcing a 2048-byte limit on chunk metadata, which the default chunking strategy exceeded with large source documents. Fixed by restructuring the knowledge base into 14 small, focused files and tuning the chunking configuration to `max_tokens: 300` with 20% overlap.

**Guardrail anonymizing 911 as a phone number**
The PII guardrail was configured with `PHONE` anonymization, which caused it to redact "911" from responses — breaking any answer that referenced emergency services. Fixed by removing `PHONE` from the PII entity config. `NAME`, `EMAIL`, `SSN`, and `AGE` remain anonymized.

**RAG not retrieving from knowledge base**
Early responses were ignoring the knowledge base entirely and falling back to Nova Micro's general knowledge. The issue was the Lambda prompt template not correctly referencing the `$search_results$` variable in the expected format. Fixed by rewriting the prompt template to explicitly scope responses to knowledge base content only.

**CI/CD pipeline blocked on alarm email variable**
`terraform apply` was failing in GitHub Actions because `var.alarm_email` had no default and was not being passed to the pipeline. Fixed by adding `TF_VAR_ALARM_EMAIL` as a GitHub secret and referencing it as an environment variable in the workflow's apply step.

**State lock conflicts during development**
Concurrent or interrupted `terraform apply` runs left stale lock files in the S3 backend, blocking subsequent runs. Resolved with `terraform force-unlock` and documented the pattern to prevent recurrence.

**CloudFront CNAMEAlreadyExists across environments**
When standing up the dev environment, Terraform attempted to attach `askheartbot.com` as a CloudFront alias on the dev distribution, which failed because the domain was already claimed by the prod distribution. Fixed by making the ACM certificate, certificate validation records, CloudFront aliases, and Route 53 DNS records conditional on `var.environment == "prod"` using `count`. The dev CloudFront distribution is accessible via its default `*.cloudfront.net` domain only.

**Default workspace state contained live prod DNS records**
After migrating to named workspaces, the legacy default workspace still tracked the same physical Route 53 records as the prod workspace. Running `terraform destroy` on default would have deleted the live DNS records for `askheartbot.com`. Used terraform state rm to detach the shared resources from the default state before destroying, preserving the live infrastructure.

## Features

- Answers questions about heart attack symptoms, warning signs, and when to seek emergency care
- Offers cited information about cardiac health
- Provides ways to improve lifestyle to better your cardiac health
- Answers questions about hypertension, warning signs, and when to seek emergency care
- Offers information about warning signs of worsening heart health
- Contains guidelines that ensure users get only recommended, cited information rather than a diagnosis
- Filters personal information from responses to protect user privacy
- Displays source references alongside responses so users can verify information

## CI/CD

**Terraform pipeline** (`terraform.yml`)

Triggers on changes to `terraform/` via push or pull request to either `main` or `develop`. The pipeline detects the target branch and selects the corresponding Terraform workspace and var file automatically:

| Branch | Workspace | Var file |
|---|---|---|
| `develop` | `dev` | `dev.tfvars` |
| `main` | `prod` | `prod.tfvars` |

On pull requests, runs `init`, `fmt -check`, `validate`, and `plan`, then posts the plan as a PR comment so infrastructure changes are reviewable before merge. On push, runs `terraform apply -auto-approve` against the appropriate workspace. The `alarm_email` variable is injected at runtime via `TF_VAR_ALARM_EMAIL` GitHub secret so sensitive values are never committed.

**Frontend pipeline** (`frontend.yml`)

Triggers on changes to `frontend/` on push to `main` or `develop`. Deploys to the environment-matched S3 bucket and CloudFront distribution:

| Branch | S3 Bucket | CloudFront |
|---|---|---|
| `develop` | `heartbot-frontend-dev` | `CLOUDFRONT_DISTRIBUTION_ID_DEV` |
| `main` | `heartbot-frontend-prod` | `CLOUDFRONT_DISTRIBUTION_ID_PROD` |

Injects `VITE_API_URL` at build time from the matching GitHub secret so the API Gateway URL is never committed. Syncs the built `dist/` to S3 with `--delete` to remove stale files, then invalidates the CloudFront distribution so users receive the new build immediately.

## Setup & Deployment

### Prerequisites
- Terraform >= 1.5.0
- AWS CLI configured with credentials (`aws configure`)
- Node.js 20+
- AWS account with Amazon Bedrock access enabled for:
  - `amazon.nova-micro-v1:0`
  - `amazon.titan-embed-text-v2:0`

---

### 1. Clone the repository
```bash
git clone https://github.com/abaig32/HeartBot.git
cd HeartBot
```

---

### 2. Deploy AWS infrastructure
```bash
cd terraform
terraform init
terraform workspace new dev   # or 'prod' for production
terraform workspace select dev
terraform plan -var-file=dev.tfvars
terraform apply -var-file=dev.tfvars
```

After `apply` completes, note the outputs — you will need `api_gateway_url` and `knowledge_base_id`.

---

### 3. Upload knowledge base documents
```bash
aws s3 sync path/to/your/documents/ s3://$(terraform output -raw s3_knowledge_base_bucket)/ --region us-east-1
```

---

### 4. Trigger knowledge base ingestion
```bash
aws bedrock-agent start-ingestion-job \
  --knowledge-base-id $(terraform output -raw knowledge_base_id) \
  --data-source-id $(terraform output -raw knowledge_base_data_source_id) \
  --region us-east-1
```

Check ingestion status:
```bash
aws bedrock-agent list-ingestion-jobs \
  --knowledge-base-id $(terraform output -raw knowledge_base_id) \
  --data-source-id $(terraform output -raw knowledge_base_data_source_id) \
  --region us-east-1
```

Wait until status shows `COMPLETE` before proceeding.

---

### 5. Configure and deploy the frontend
```bash
cd ../frontend
echo "VITE_API_URL=$(cd ../terraform && terraform output -raw api_gateway_url)" > .env
npm install
npm run build
aws s3 sync dist/ s3://$(cd ../terraform && terraform output -raw s3_knowledge_base_bucket | sed 's/knowledge-base/frontend/')/ \
  --delete \
  --cache-control "public, max-age=31536000, immutable"
```

Invalidate the CloudFront cache:
```bash
aws cloudfront create-invalidation \
  --distribution-id <your-distribution-id> \
  --paths "/*"
```

---

### 6. Access the application

Visit https://askheartbot.com or the CloudFront domain from terraform output cloudfront_domain for dev.

---

## Cost

# HeartBot Monthly Cost Breakdown

Estimated monthly cost for the production environment at low traffic (~100 requests/day).

| Service | Usage | Estimated Cost |
|---|---|---|
| Amazon Bedrock (Nova Micro) | ~3000 requests/month | ~$0.50 |
| Amazon Bedrock Knowledge Base | Retrieval queries | ~$0.30 |
| AWS Lambda | ~3000 invocations, 256MB, ~5s avg | ~$0.00 (free tier) |
| API Gateway | ~3000 requests | ~$0.01 |
| CloudFront | ~3000 requests + static assets | ~$0.01 |
| S3 (knowledge base + frontend) | < 1GB storage | ~$0.02 |
| S3 Vectors | Vector index storage | ~$0.10 |
| Route 53 | 1 hosted zone | ~$0.50 |
| CloudWatch | Logs + dashboards + alarms | ~$0.05 |
| SNS | Email notifications | ~$0.00 |
| S3 Replication (us-west-2) | < 1GB replicated | ~$0.02 |
| **Total** | | **~$1.50/month** |

- Dev environment has no CloudFront custom domain or Route 53 records — no additional fixed costs

## Notes
- Lambda stays within free tier at this traffic level (1M requests/month free)
- Bedrock costs scale linearly with usage — heaviest cost driver
- Route 53 hosted zone is the largest fixed cost regardless of traffic
- Replica bucket uses STANDARD_IA storage class to minimize DR cost

## Disclaimer

HeartBot is for informational purposes only and is not a substitute for professional medical advice, diagnosis, or treatment. Always consult a qualified healthcare provider for medical concerns.

