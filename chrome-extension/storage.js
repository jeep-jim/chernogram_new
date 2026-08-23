import { randomId } from './crypto.js';

export async function ensureState() {
  const { vtState } = await chrome.storage.local.get('vtState');
  if (vtState) {
    const next = structuredClone(vtState);
    next.profile ||= {};
    next.contacts ||= {};
    next.messages ||= {};
    next.signals ||= {};
    delete next.quota;
    delete next.pro;
    next.ui ||= {};
    next.ui.theme ||= 'dark';
    next.ui.activeRoomId ||= '';
    next.ui.privacyLens = next.ui.privacyLens === true;
    next.schemaVersion = 3;
    if (JSON.stringify(next) !== JSON.stringify(vtState)) await chrome.storage.local.set({ vtState: next });
    return next;
  }
  const state = {
    profile: { id: randomId(12), inboxId: randomId(18), name: 'VeilTalk User', lang: 'en', avatar: '', createdAt: Date.now() },
    contacts: {},
    messages: {},
    signals: {},
    ui: { activeRoomId: '', privacyLens: false, theme: 'dark', languagePolicyVersion: 'english-default-v1' },
    schemaVersion: 3
  };
  await chrome.storage.local.set({ vtState: state });
  return state;
}

export async function loadState() {
  return ensureState();
}

export async function saveState(state) {
  await chrome.storage.local.set({ vtState: state });
  return state;
}

export async function mutateState(mutator) {
  const state = await ensureState();
  const next = structuredClone(state);
  await mutator(next);
  await saveState(next);
  return next;
}
