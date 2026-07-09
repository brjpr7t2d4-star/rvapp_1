const express = require('express');
const cors = require('cors');
const fs = require('fs/promises');
const path = require('path');

const app = express();
const PORT = Number(process.env.PORT || 3000);
const dataDir = path.join(__dirname, 'data');
const signupEventsFile = path.join(dataDir, 'signup-events.json');

app.use(cors());
app.use(express.json({ limit: '1mb' }));

async function ensureDataFile() {
  await fs.mkdir(dataDir, { recursive: true });
  try {
    await fs.access(signupEventsFile);
  } catch (_) {
    await fs.writeFile(signupEventsFile, '[]\n', 'utf8');
  }
}

async function readSignupEvents() {
  await ensureDataFile();
  const raw = await fs.readFile(signupEventsFile, 'utf8');
  try {
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch (_) {
    return [];
  }
}

async function writeSignupEvents(events) {
  await ensureDataFile();
  await fs.writeFile(signupEventsFile, `${JSON.stringify(events, null, 2)}\n`, 'utf8');
}

function normalizeString(value) {
  return typeof value === 'string' ? value.trim() : '';
}

app.get('/health', (_req, res) => {
  res.json({ ok: true });
});

app.post('/api/signup-events', async (req, res) => {
  const username = normalizeString(req.body.username);
  const email = normalizeString(req.body.email).toLowerCase();

  if (username.length < 3) {
    res.status(400).json({ error: 'Username must be at least 3 characters.' });
    return;
  }

  if (!email.includes('@')) {
    res.status(400).json({ error: 'A valid email is required.' });
    return;
  }

  const event = {
    id: `${Date.now()}-${Math.random().toString(36).slice(2, 10)}`,
    username,
    email,
    hasProAccess: Boolean(req.body.hasProAccess),
    isTowing: Boolean(req.body.isTowing),
    rigHeightFt: Number(req.body.rigHeightFt) || null,
    rigWeightLbs: Number(req.body.rigWeightLbs) || null,
    rigLengthFt: Number(req.body.rigLengthFt) || null,
    platform: normalizeString(req.body.platform) || 'unknown',
    createdAt: normalizeString(req.body.createdAt) || new Date().toISOString(),
    receivedAt: new Date().toISOString(),
    ip: req.headers['x-forwarded-for'] || req.socket.remoteAddress || null,
  };

  try {
    const events = await readSignupEvents();
    events.push(event);
    await writeSignupEvents(events);
    res.status(201).json({ ok: true, id: event.id });
  } catch (error) {
    console.error('Failed to store signup event:', error);
    res.status(500).json({ error: 'Failed to store signup event.' });
  }
});

app.get('/api/signup-events', async (_req, res) => {
  try {
    const events = await readSignupEvents();
    res.json({ count: events.length, events });
  } catch (error) {
    console.error('Failed to read signup events:', error);
    res.status(500).json({ error: 'Failed to read signup events.' });
  }
});

app.get('/api/signup-stats', async (_req, res) => {
  try {
    const events = await readSignupEvents();
    const daily = {};

    for (const event of events) {
      const dateKey = String(event.createdAt || event.receivedAt || '').slice(0, 10);
      if (!dateKey) {
        continue;
      }
      daily[dateKey] = (daily[dateKey] || 0) + 1;
    }

    res.json({
      totalSignups: events.length,
      proSignups: events.filter((event) => event.hasProAccess).length,
      daily,
    });
  } catch (error) {
    console.error('Failed to compute signup stats:', error);
    res.status(500).json({ error: 'Failed to compute signup stats.' });
  }
});

ensureDataFile()
  .then(() => {
    app.listen(PORT, () => {
      console.log(`Signup tracking API listening on http://localhost:${PORT}`);
    });
  })
  .catch((error) => {
    console.error('Failed to initialize signup tracking API:', error);
    process.exit(1);
  });
