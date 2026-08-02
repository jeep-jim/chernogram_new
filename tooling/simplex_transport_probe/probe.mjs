import fs from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';
import { randomUUID } from 'node:crypto';

import { api } from 'simplex-chat';
import { T } from '@simplex-chat/types';

const { ChatApi } = api;
const workDir = path.resolve(process.cwd(), '.probe-data');
const reportPath = path.resolve(process.cwd(), 'simplex-probe-report.json');
const eventsPath = path.resolve(process.cwd(), 'simplex-probe-events.jsonl');
const startedAt = new Date();

const ONLINE_MESSAGES = Number(process.env.CG_PROBE_ONLINE_MESSAGES ?? 20);
const OFFLINE_MESSAGES = Number(process.env.CG_PROBE_OFFLINE_MESSAGES ?? 10);
const CONNECT_TIMEOUT_MS = Number(process.env.CG_PROBE_CONNECT_TIMEOUT_MS ?? 120_000);
const MESSAGE_TIMEOUT_MS = Number(process.env.CG_PROBE_MESSAGE_TIMEOUT_MS ?? 90_000);
const OFFLINE_TIMEOUT_MS = Number(process.env.CG_PROBE_OFFLINE_TIMEOUT_MS ?? 180_000);

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function percentile(values, p) {
  if (values.length === 0) return null;
  const ordered = [...values].sort((a, b) => a - b);
  const index = Math.min(ordered.length - 1, Math.ceil((p / 100) * ordered.length) - 1);
  return ordered[Math.max(0, index)];
}

function eventType(event) {
  return typeof event?.type === 'string' ? event.type : 'unknown';
}

class EventCollector {
  constructor(label) {
    this.label = label;
    this.events = [];
    this.seenTokens = new Map();
    this.waiters = new Map();
  }

  attach(chat) {
    chat.onAny((event) => {
      const raw = JSON.stringify(event);
      const at = Date.now();
      const type = eventType(event);
      this.events.push({ at, type });

      for (const [token, waiter] of this.waiters.entries()) {
        if (!raw.includes(token)) continue;
        const hits = (this.seenTokens.get(token) ?? 0) + 1;
        this.seenTokens.set(token, hits);
        if (!waiter.done) {
          waiter.done = true;
          clearTimeout(waiter.timer);
          waiter.resolve({ at, type, hits });
        }
      }
    });
  }

  waitForToken(token, timeoutMs) {
    if (this.seenTokens.has(token)) {
      return Promise.resolve({ at: Date.now(), type: 'already-seen', hits: this.seenTokens.get(token) });
    }
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        const waiter = this.waiters.get(token);
        if (waiter) waiter.done = true;
        reject(new Error(`${this.label}: token was not delivered within ${timeoutMs} ms: ${token}`));
      }, timeoutMs);
      this.waiters.set(token, { resolve, reject, timer, done: false });
    });
  }

  summary() {
    const counts = {};
    for (const event of this.events) counts[event.type] = (counts[event.type] ?? 0) + 1;
    return { label: this.label, eventCounts: counts, totalEvents: this.events.length };
  }
}

async function appendEvent(record) {
  await fs.appendFile(eventsPath, `${JSON.stringify(record)}\n`, 'utf8');
}

async function waitForContacts(alice, bob) {
  const deadline = Date.now() + CONNECT_TIMEOUT_MS;
  let last = { alice: 0, bob: 0 };
  while (Date.now() < deadline) {
    const [aliceContacts, bobContacts] = await Promise.all([
      alice.apiListContacts((await alice.apiGetActiveUser()).userId),
      bob.apiListContacts((await bob.apiGetActiveUser()).userId),
    ]);
    last = { alice: aliceContacts.length, bob: bobContacts.length };
    if (aliceContacts.length > 0 && bobContacts.length > 0) {
      return { aliceContact: aliceContacts[0], bobContact: bobContacts[0] };
    }
    await sleep(500);
  }
  throw new Error(`SimpleX contact was not established: ${JSON.stringify(last)}`);
}

async function initClient(name, dbPrefix) {
  const chat = await ChatApi.init({ type: 'sqlite', filePrefix: dbPrefix });
  let user = await chat.apiGetActiveUser();
  if (!user) {
    user = await chat.apiCreateActiveUser({ displayName: name, fullName: '' });
  }
  return { chat, user };
}

async function safelyStopAndClose(chat) {
  if (!chat) return;
  try {
    if (chat.started) await chat.stopChat();
  } catch (error) {
    console.warn('stopChat failed during cleanup:', error?.message ?? error);
  }
  try {
    if (chat.initialized) await chat.close();
  } catch (error) {
    console.warn('close failed during cleanup:', error?.message ?? error);
  }
}

const report = {
  schema: 1,
  transport: 'SimpleX Chat native core via official Node.js binding',
  startedAt: startedAt.toISOString(),
  configuration: {
    onlineMessages: ONLINE_MESSAGES,
    offlineMessages: OFFLINE_MESSAGES,
    connectTimeoutMs: CONNECT_TIMEOUT_MS,
    messageTimeoutMs: MESSAGE_TIMEOUT_MS,
    offlineTimeoutMs: OFFLINE_TIMEOUT_MS,
  },
  result: 'running',
};

let alice;
let bob;

try {
  await fs.rm(workDir, { recursive: true, force: true });
  await fs.mkdir(workDir, { recursive: true });
  await fs.writeFile(eventsPath, '', 'utf8');

  const aliceInit = await initClient('Chernogram Probe Alice', path.join(workDir, 'alice'));
  const bobInit = await initClient('Chernogram Probe Bob', path.join(workDir, 'bob'));
  alice = aliceInit.chat;
  bob = bobInit.chat;

  const aliceCollector = new EventCollector('alice');
  const bobCollector = new EventCollector('bob-online');
  aliceCollector.attach(alice);
  bobCollector.attach(bob);

  await Promise.all([alice.startChat(), bob.startChat()]);
  await appendEvent({ stage: 'clients-started', at: new Date().toISOString() });

  const connectStarted = Date.now();
  const invitation = await alice.apiCreateLink(aliceInit.user.userId);
  await bob.apiConnectActiveUser(invitation);
  const { aliceContact, bobContact } = await waitForContacts(alice, bob);
  const connectionMs = Date.now() - connectStarted;
  await appendEvent({ stage: 'contact-connected', connectionMs });

  const onlineLatenciesMs = [];
  const onlineTokens = [];
  for (let index = 0; index < ONLINE_MESSAGES; index += 1) {
    const token = `CG064-ONLINE-${String(index + 1).padStart(3, '0')}-${randomUUID()}`;
    onlineTokens.push(token);
    const wait = bobCollector.waitForToken(token, MESSAGE_TIMEOUT_MS);
    const sentAt = Date.now();
    await alice.apiSendTextMessage([T.ChatType.Direct, aliceContact.contactId], token);
    const received = await wait;
    const latencyMs = received.at - sentAt;
    onlineLatenciesMs.push(latencyMs);
    await appendEvent({ stage: 'online-message', index: index + 1, latencyMs, eventType: received.type });
  }

  await safelyStopAndClose(bob);
  bob = undefined;
  await appendEvent({ stage: 'bob-fully-closed', at: new Date().toISOString() });

  const offlineTokens = [];
  for (let index = 0; index < OFFLINE_MESSAGES; index += 1) {
    const token = `CG064-OFFLINE-${String(index + 1).padStart(3, '0')}-${randomUUID()}`;
    offlineTokens.push({ token, sentAt: Date.now() });
    await alice.apiSendTextMessage([T.ChatType.Direct, aliceContact.contactId], token);
    await appendEvent({ stage: 'offline-message-accepted-by-core', index: index + 1 });
  }

  await sleep(3_000);
  const restartStarted = Date.now();
  const bobRestart = await initClient('Chernogram Probe Bob', path.join(workDir, 'bob'));
  bob = bobRestart.chat;
  const bobRestartCollector = new EventCollector('bob-restarted');
  bobRestartCollector.attach(bob);
  const waits = offlineTokens.map(({ token }) => bobRestartCollector.waitForToken(token, OFFLINE_TIMEOUT_MS));
  await bob.startChat();
  const deliveries = await Promise.all(waits);
  const restartDeliveryMs = Date.now() - restartStarted;
  const offlineLatenciesMs = deliveries.map((delivery, index) => delivery.at - offlineTokens[index].sentAt);

  const allCollectors = [aliceCollector.summary(), bobCollector.summary(), bobRestartCollector.summary()];
  report.result = 'pass';
  report.finishedAt = new Date().toISOString();
  report.connection = {
    durationMs: connectionMs,
    aliceContactId: aliceContact.contactId,
    bobContactId: bobContact.contactId,
  };
  report.online = {
    sent: onlineTokens.length,
    received: onlineLatenciesMs.length,
    lost: onlineTokens.length - onlineLatenciesMs.length,
    minLatencyMs: Math.min(...onlineLatenciesMs),
    medianLatencyMs: percentile(onlineLatenciesMs, 50),
    p95LatencyMs: percentile(onlineLatenciesMs, 95),
    maxLatencyMs: Math.max(...onlineLatenciesMs),
    latenciesMs: onlineLatenciesMs,
  };
  report.offline = {
    sentWhileReceiverClosed: offlineTokens.length,
    deliveredAfterDatabaseReopen: deliveries.length,
    lost: offlineTokens.length - deliveries.length,
    restartToCompleteDeliveryMs: restartDeliveryMs,
    minEndToEndLatencyMs: Math.min(...offlineLatenciesMs),
    p95EndToEndLatencyMs: percentile(offlineLatenciesMs, 95),
    maxEndToEndLatencyMs: Math.max(...offlineLatenciesMs),
    endToEndLatenciesMs: offlineLatenciesMs,
  };
  report.collectors = allCollectors;

  if (report.online.lost !== 0 || report.offline.lost !== 0) {
    throw new Error('Probe completed with message loss');
  }

  console.log(JSON.stringify(report, null, 2));
} catch (error) {
  report.result = 'fail';
  report.finishedAt = new Date().toISOString();
  report.error = {
    name: error?.name ?? 'Error',
    message: error?.message ?? String(error),
    stack: error?.stack ?? null,
  };
  console.error(error);
  process.exitCode = 1;
} finally {
  await Promise.all([safelyStopAndClose(alice), safelyStopAndClose(bob)]);
  await fs.writeFile(reportPath, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
}
