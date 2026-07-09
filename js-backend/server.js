const express = require('express');
const cors = require('cors');
const fs = require('fs/promises');
const path = require('path');

const app = express();
const PORT = Number(process.env.PORT || 3000);
const dataDir = path.join(__dirname, 'data');
const signupEventsFile = path.join(dataDir, 'signup-events.json');
const analyticsEventsFile = path.join(dataDir, 'analytics-events.json');

app.use(cors());
app.use(express.json({ limit: '1mb' }));

async function ensureDataFiles() {
  await fs.mkdir(dataDir, { recursive: true });
  const files = [signupEventsFile, analyticsEventsFile];

  for (const filePath of files) {
    try {
      await fs.access(filePath);
    } catch (_) {
      await fs.writeFile(filePath, '[]\n', 'utf8');
    }
  }
}

async function readJsonArray(filePath) {
  await ensureDataFiles();
  const raw = await fs.readFile(filePath, 'utf8');
  try {
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed : [];
  } catch (_) {
    return [];
  }
}

async function writeJsonArray(filePath, values) {
  await ensureDataFiles();
  await fs.writeFile(filePath, `${JSON.stringify(values, null, 2)}\n`, 'utf8');
}

async function readSignupEvents() {
  return readJsonArray(signupEventsFile);
}

async function writeSignupEvents(events) {
  await writeJsonArray(signupEventsFile, events);
}

async function readAnalyticsEvents() {
  return readJsonArray(analyticsEventsFile);
}

async function writeAnalyticsEvents(events) {
  await writeJsonArray(analyticsEventsFile, events);
}

function normalizeString(value) {
  return typeof value === 'string' ? value.trim() : '';
}

function toDateKey(value) {
  return String(value || '').slice(0, 10);
}

function toSafeInt(value, fallback) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    return fallback;
  }
  return Math.floor(parsed);
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
      const dateKey = toDateKey(event.createdAt || event.receivedAt);
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

app.post('/api/analytics/events', async (req, res) => {
  const eventName = normalizeString(req.body.eventName);
  const userId = normalizeString(req.body.userId);
  const sessionId = normalizeString(req.body.sessionId);
  const platform = normalizeString(req.body.platform) || 'unknown';

  if (eventName.length < 2) {
    res.status(400).json({ error: 'eventName is required and must be at least 2 characters.' });
    return;
  }

  const rawProperties = req.body.properties;
  const properties = rawProperties && typeof rawProperties === 'object' && !Array.isArray(rawProperties)
    ? rawProperties
    : {};

  const event = {
    id: `${Date.now()}-${Math.random().toString(36).slice(2, 10)}`,
    eventName,
    userId: userId || null,
    sessionId: sessionId || null,
    platform,
    properties,
    occurredAt: normalizeString(req.body.occurredAt) || new Date().toISOString(),
    receivedAt: new Date().toISOString(),
    ip: req.headers['x-forwarded-for'] || req.socket.remoteAddress || null,
  };

  try {
    const events = await readAnalyticsEvents();
    events.push(event);
    await writeAnalyticsEvents(events);
    res.status(201).json({ ok: true, id: event.id });
  } catch (error) {
    console.error('Failed to store analytics event:', error);
    res.status(500).json({ error: 'Failed to store analytics event.' });
  }
});

app.get('/api/analytics/events', async (req, res) => {
  const eventNameFilter = normalizeString(req.query.eventName);
  const userIdFilter = normalizeString(req.query.userId);
  const limit = Math.min(1000, Math.max(1, toSafeInt(req.query.limit, 200)));

  try {
    let events = await readAnalyticsEvents();
    if (eventNameFilter) {
      events = events.filter((event) => normalizeString(event.eventName) === eventNameFilter);
    }
    if (userIdFilter) {
      events = events.filter((event) => normalizeString(event.userId) === userIdFilter);
    }

    const sorted = events.sort((a, b) => String(b.occurredAt || b.receivedAt).localeCompare(String(a.occurredAt || a.receivedAt)));
    const sliced = sorted.slice(0, limit);
    res.json({ count: events.length, returned: sliced.length, events: sliced });
  } catch (error) {
    console.error('Failed to read analytics events:', error);
    res.status(500).json({ error: 'Failed to read analytics events.' });
  }
});

app.get('/api/analytics/overview', async (req, res) => {
  const days = Math.min(365, Math.max(1, toSafeInt(req.query.days, 30)));

  try {
    const [analyticsEvents, signupEvents] = await Promise.all([
      readAnalyticsEvents(),
      readSignupEvents(),
    ]);

    const cutoff = new Date();
    cutoff.setUTCDate(cutoff.getUTCDate() - (days - 1));
    cutoff.setUTCHours(0, 0, 0, 0);

    const eventsInRange = analyticsEvents.filter((event) => {
      const eventDate = new Date(event.occurredAt || event.receivedAt);
      return !Number.isNaN(eventDate.getTime()) && eventDate >= cutoff;
    });

    const eventCounts = {};
    const platformCounts = {};
    const uniqueUsers = new Set();
    const dailyEvents = {};

    for (const event of eventsInRange) {
      const eventName = normalizeString(event.eventName) || 'unknown';
      eventCounts[eventName] = (eventCounts[eventName] || 0) + 1;

      const platform = normalizeString(event.platform) || 'unknown';
      platformCounts[platform] = (platformCounts[platform] || 0) + 1;

      const userId = normalizeString(event.userId);
      if (userId) {
        uniqueUsers.add(userId);
      }

      const dateKey = toDateKey(event.occurredAt || event.receivedAt);
      if (dateKey) {
        dailyEvents[dateKey] = (dailyEvents[dateKey] || 0) + 1;
      }
    }

    const dailySignups = {};
    for (const signupEvent of signupEvents) {
      const signupDate = new Date(signupEvent.createdAt || signupEvent.receivedAt);
      if (Number.isNaN(signupDate.getTime()) || signupDate < cutoff) {
        continue;
      }
      const dateKey = toDateKey(signupEvent.createdAt || signupEvent.receivedAt);
      if (dateKey) {
        dailySignups[dateKey] = (dailySignups[dateKey] || 0) + 1;
      }
    }

    res.json({
      windowDays: days,
      eventCount: eventsInRange.length,
      uniqueUsers: uniqueUsers.size,
      eventCounts,
      platformCounts,
      dailyEvents,
      signupCount: Object.values(dailySignups).reduce((sum, value) => sum + value, 0),
      dailySignups,
    });
  } catch (error) {
    console.error('Failed to compute analytics overview:', error);
    res.status(500).json({ error: 'Failed to compute analytics overview.' });
  }
});

ensureDataFiles()
  .then(() => {
    app.listen(PORT, () => {
      console.log(`Analytics API listening on http://localhost:${PORT}`);
    });
  })
  .catch((error) => {
    console.error('Failed to initialize signup tracking API:', error);
    process.exit(1);
  });
