# notification-dispatcher (Lambda)

SQS-triggered Lambda that logs the notification and writes a record to
DynamoDB. This is the serverless counterpart to `services/worker` — same job,
different execution model, useful for comparing tradeoffs in interviews
(cold starts, pay-per-invocation, no cluster to manage, vs. always-on worker
with predictable latency).

## Build & deploy

```bash
npm install --omit=dev
zip -r function.zip index.js node_modules package.json
aws lambda update-function-code \
  --function-name task-platform-notification-dispatcher \
  --zip-file fileb://function.zip
```

This is exactly what the `deploy_lambda` job in `.gitlab-ci.yml` does.

## Placeholder for first `terraform apply`

`terraform/serverless.tf` references `placeholder.zip` so the Lambda
resource has something to deploy on a brand-new account, before CI has ever
run. Generate it once with:

```bash
cd lambda/notification-dispatcher
echo "exports.handler = async () => ({statusCode: 200});" > placeholder-index.js
zip placeholder.zip placeholder-index.js
rm placeholder-index.js
```

CI overwrites the real code after the first deploy; `placeholder.zip` is
git-ignored so it's never mistaken for the real artifact.
