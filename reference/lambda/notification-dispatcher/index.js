import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, PutCommand } from '@aws-sdk/lib-dynamodb';
import { randomUUID } from 'node:crypto';

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({}));
const TABLE_NAME = process.env.DYNAMODB_TABLE;

// Triggered by SQS (see terraform/serverless.tf event source mapping).
// Demonstrates the serverless alternative to the in-cluster BullMQ worker
// (services/worker) for the same "dispatch a notification" job.
export const handler = async (event) => {
  for (const record of event.Records) {
    const payload = JSON.parse(record.body);
    const { taskId, email, title } = payload;

    console.log(`[lambda] would email ${email}: task "${title}" created`);

    await ddb.send(
      new PutCommand({
        TableName: TABLE_NAME,
        Item: {
          notification_id: randomUUID(),
          taskId,
          email,
          title,
          sentAt: new Date().toISOString(),
        },
      }),
    );
  }
};
