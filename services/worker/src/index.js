import { Worker } from 'bullmq';
import pg from 'pg';

const { Pool } = pg;

const pool = new Pool({
  connectionString: process.env.DATABASE_URL || 'postgres://postgres:postgres@postgres:5432/tasks',
});

const connection = {
  host: process.env.REDIS_HOST || 'redis',
  port: Number(process.env.REDIS_PORT || 6379),
};

async function sendNotification(email, title) {
  // Free-tier note: swap this for AWS SES (sandbox mode is free for verified
  // addresses) once you want real email delivery. Logging keeps the demo
  // runnable with zero external dependencies.
  console.log(`[notify] would email ${email}: task "${title}" created`);
}

const worker = new Worker(
  'notifications',
  async (job) => {
    const { taskId, email, title } = job.data;
    await sendNotification(email, title);
    await pool.query('UPDATE tasks SET status = $1 WHERE id = $2', ['notified', taskId]);
  },
  { connection },
);

worker.on('completed', (job) => console.log(`job ${job.id} completed`));
worker.on('failed', (job, err) => console.error(`job ${job?.id} failed`, err));

console.log('worker listening for notification jobs');
