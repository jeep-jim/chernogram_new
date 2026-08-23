import { ensureState, mutateState } from './storage.js';
import { openInboxSocket, decodeOuterForContact, pollInbox } from './transport.js';

let stopSocket = null;
let networkState = 'reconnecting';

async function boot() {
  const state = await ensureState();
  await pollInbox(state.profile.inboxId, outer => handleOuter(outer)).catch(() => {});
  if (stopSocket) stopSocket();
  stopSocket = await openInboxSocket(
    state.profile.inboxId,
    outer => handleOuter(outer),
    status => {
      networkState = status;
      chrome.runtime.sendMessage({ type: 'network', status }).catch(() => {});
    }
  );
}

async function handleOuter(outer) {
  const state = await ensureState();
  const contact = state.contacts?.[outer?.roomId];
  if (!contact) return;
  let payload;
  try { payload = await decodeOuterForContact(contact, outer); } catch (_) { return; }
  if (!payload) return;

  if (payload.type === 'hello' && payload.inboxId) {
    await mutateState(s => {
      const c = s.contacts[payload.roomId];
      if (!c) return;
      c.remoteInboxId = payload.inboxId;
      c.remoteProfileId = payload.profileId || c.remoteProfileId;
      c.name = payload.name || c.name;
      c.avatar = payload.avatar || c.avatar || '';
      c.status = 'connected';
      c.lastSeen = Date.now();
    });
  } else if (payload.type === 'message') {
    await mutateState(s => {
      const list = s.messages[payload.roomId] ||= [];
      if (!list.some(m => m.id === payload.id)) {
        list.push({ id: payload.id, from: 'remote', text: payload.text || '', ts: payload.sentAt || Date.now(), kind: 'text' });
        if (list.length > 500) list.splice(0, list.length - 500);
      }
      const c = s.contacts[payload.roomId];
      if (c) { c.lastSeen = Date.now(); c.lastMessage = payload.text || ''; }
    });
    await chrome.notifications.create(`msg:${payload.roomId}:${payload.id}`, {
      type: 'basic', iconUrl: 'icons/icon128.png', title: contact.name || 'VeilTalk', message: payload.text || 'New message', priority: 1
    });
  } else if (payload.type === 'rtc' || ['offer','answer','ice','hangup','call-invite'].includes(payload.type)) {
    await mutateState(s => {
      const list = s.signals[payload.roomId] ||= [];
      if (!list.some(x => (x.signalId || x.id) === (payload.signalId || payload.id))) list.push(payload);
      if (list.length > 100) list.splice(0, list.length - 100);
    });
    if (payload.type === 'call-invite' || (payload.type === 'rtc' && payload.purpose === 'call' && payload.action === 'invite')) {
      await chrome.notifications.create(`call:${payload.roomId}`, {
        type: 'basic', iconUrl: 'icons/icon128.png', title: payload.video ? 'VeilTalk video call' : 'VeilTalk voice call',
        message: `${contact.name || 'Contact'} is calling`, priority: 2, requireInteraction: true
      });
    }
    if (payload.type === 'rtc' && payload.purpose === 'file' && payload.action === 'offer' && payload.file) {
      await chrome.notifications.create(`file:${payload.roomId}:${payload.file.id || 'incoming'}`, {
        type: 'basic', iconUrl: 'icons/icon128.png', title: contact.name || 'VeilTalk',
        message: `Incoming file: ${payload.file.name || 'file'}`, priority: 1
      });
    }
  }
  chrome.runtime.sendMessage({ type: 'state-updated', roomId: payload.roomId, payloadType: payload.type }).catch(() => {});
}

chrome.runtime.onInstalled.addListener(async () => {
  await ensureState();
  await chrome.sidePanel.setPanelBehavior({ openPanelOnActionClick: true }).catch(() => {});
  boot();
});
chrome.runtime.onStartup.addListener(boot);
chrome.alarms.create('veiltalk-inbox-poll', { periodInMinutes: 0.5 });
chrome.alarms.onAlarm.addListener(async alarm => {
  if (alarm.name !== 'veiltalk-inbox-poll') return;
  const s = await ensureState();
  await pollInbox(s.profile.inboxId, outer => handleOuter(outer)).catch(() => {});
});
chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  if (msg?.type === 'reboot-network') { boot().then(() => sendResponse({ ok: true })); return true; }
  if (msg?.type === 'network-status') { sendResponse({ status: networkState }); }
  if (msg?.type === 'clear-room-signals' && msg.roomId) {
    mutateState(s => { s.signals[msg.roomId] = []; }).then(() => sendResponse({ ok: true }));
    return true;
  }
});
chrome.notifications.onClicked.addListener(async id => {
  if (!id.startsWith('msg:') && !id.startsWith('call:') && !id.startsWith('file:')) return;
  const parts = id.split(':');
  const roomId = parts[1] || '';
  await mutateState(s => { s.ui.activeRoomId = roomId; });
  const win = await chrome.windows.getLastFocused();
  if (win?.id) await chrome.sidePanel.open({ windowId: win.id }).catch(() => {});
});
boot();
