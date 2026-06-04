# HeartBot Runbook

## Alarms
| Alarm | Threshold | What it means |
|---|---|---|
| Lambda Errors | >5 in 5 min | Lambda is crashing on requests |
| Lambda Duration | >25s average | Bedrock calls are timing out |
| API Gateway 4xx | >10 in 5 min | Bad requests spiking, possible abuse |

## Diagnosing Issues

### Lambda errors spiking
1. Open CloudWatch Logs for /aws/lambda/heartbot-handler-prod
2. Run this Logs Insights query:
    ```
    filter event = "request_received"
    | sort @timestamp desc
    | limit 20
    ```
3. Check for patterns — is it one query type failing or all requests?

### Bedrock not responding
1. Check AWS Service Health Dashboard for Bedrock in us-east-1
2. Check Lambda duration alarm — if avg > 25s, Bedrock is slow or down
3. No automatic failover exists — communicate downtime to users

### High 4xx rate
1. Could be malformed requests or someone probing the API
2. Check API Gateway logs for source IPs
3. If abuse, consider enabling WAF rate limiting

## Recovery
- **Frontend down**: Invalidate CloudFront cache, re-run frontend GitHub Actions workflow
- **Lambda broken**: Revert last commit, push to main, pipeline redeploys automatically
- **Knowledge base corrupted**: Documents replicated to us-west-2 — restore from replica bucket