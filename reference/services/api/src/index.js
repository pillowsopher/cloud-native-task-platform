import express from 'express';
import client from 'prom-client';
import { pool, initSchema } from './db.js';
import { notificationQueue } from './queue.js';

const app = express();
app.use(express.json());

const register = new client.Registry();
client.collectDefaultMetrics({ register });
const requestCounter = new client.Counter({
  name: 'task_api_requests_total',
  help: 'Total requests handled',
  labelNames: ['route', 'method', 'status'],
  registers: [register],
});

app.get('/healthz', (_req, res) => res.json({ status: 'ok' }));

app.get('/metrics', async (_req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(await register.metrics());
});

app.post('/tasks', async (req, res) => {
  const { title, notify_email: notifyEmail } = req.body;
  if (!title) {
    requestCounter.inc({ route: '/tasks', method: 'POST', status: '400' });
    return res.status(400).json({ error: 'title is required' });
  }

  const { rows } = await pool.query(
    'INSERT INTO tasks (title, notify_email) VALUES ($1, $2) RETURNING *',
    [title, notifyEmail || null],
  );
  const task = rows[0];

  if (notifyEmail) {
    await notificationQueue.add('task-created', { taskId: task.id, email: notifyEmail, title });
  }

  requestCounter.inc({ route: '/tasks', method: 'POST', status: '201' });
  return res.status(201).json(task);
});

app.get('/tasks', async (_req, res) => {
  const { rows } = await pool.query('SELECT * FROM tasks ORDER BY created_at DESC');
  requestCounter.inc({ route: '/tasks', method: 'GET', status: '200' });
  res.json(rows);
});

const port = process.env.PORT || 3000;

initSchema()
  .then(() => app.listen(port, () => console.log(`api listening on ${port}`)))
  .catch((err) => {
    console.error('failed to init schema', err);
    process.exit(1);
  });
