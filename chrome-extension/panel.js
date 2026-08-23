import { CONFIG } from './config.js';
import { LANGS, tr } from './i18n.js';
import { loadState, mutateState, todayKey } from './storage.js';
import { randomId, encodeInvite, decodeInvite } from './crypto.js';
import { sendEnvelope } from './transport.js';
import { activateLicense, validateLicense } from './billing.js';
import { createPeerConnection, addIceOrQueue, flushIce } from './rtc.js';
import { putFile, getFile, deleteRoomFiles, createIncomingFile, commitIncomingFile, abortIncomingFile } from './file_store.js';

const app = document.querySelector('#app');
const EMOJIS = ['😀','😁','😂','😊','😍','🥰','😎','🤔','😢','😭','😡','👍','👎','👏','🙏','💪','🎉','❤️','🔥','✨','✅','👋','🤝','🚗','📎','📸','🎥','🎵','💬','🔒'];
const langNames = { en:'English', ru:'Русский', de:'Deutsch', fr:'Français', es:'Español' };
const esc = value => String(value ?? '').replace(/[&<>"']/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));
const formatBytes = bytes => {
  const value = Number(bytes || 0);
  if (value < 1024) return `${value} B`;
  if (value < 1024 * 1024) return `${(value / 1024).toFixed(1)} KB`;
  if (value < 1024 * 1024 * 1024) return `${(value / (1024 * 1024)).toFixed(1)} MB`;
  return `${(value / (1024 * 1024 * 1024)).toFixed(1)} GB`;
};

let state;
let tab = 'chats';
let activeRoom = '';
let modal = null;
let network = 'reconnecting';
let call = null;
let transfer = null;
let emojiOpen = false;
let lastTransferRender = 0;

const t = key => tr(state?.profile?.lang || 'en', key);
const privacyOn = () => state?.ui?.privacyLens === true;
const lightThemeOn = () => state?.ui?.theme === 'light';
const safeName = value => privacyOn() ? '••••••••' : (value || 'Contact');
const signalId = signal => signal.signalId || signal.id || `${signal.sessionId || ''}:${signal.action || signal.type}:${signal.sentAt || ''}`;

function applyTheme() {
  document.documentElement.dataset.theme = lightThemeOn() ? 'light' : 'dark';
}

function logoSvg() {
  return '<img src="icons/mask.svg" alt="" />';
}

function icon(name) {
  const paths = {
    chats:'<path d="M4 5.5h16v10H9l-5 4v-14Z"/><path d="M8 9.5h8M8 12.5h5"/>',
    contacts:'<circle cx="8.5" cy="8" r="3"/><circle cx="16.5" cy="9" r="2.3"/><path d="M3.5 19c.6-3.1 2.3-4.7 5-4.7s4.4 1.6 5 4.7M15 14.7c2.9.1 4.5 1.5 5 4.3"/>',
    phone:'<path d="M7.3 3.5 10 7.8 7.9 10c1.4 2.8 3.4 4.8 6.2 6.2l2.1-2.1 4.3 2.7-.7 3.2c-.2.8-.9 1.4-1.8 1.4C9.6 21.4 2.6 14.4 2.6 6c0-.9.6-1.6 1.4-1.8l3.3-.7Z"/>',
    video:'<rect x="3" y="6" width="13" height="12" rx="3"/><path d="m16 10 5-3v10l-5-3"/>',
    attach:'<path d="m8.5 12.5 6.7-6.7a3 3 0 0 1 4.2 4.2l-8.8 8.8a5 5 0 0 1-7.1-7.1l8.2-8.2"/><path d="m7 15 7.7-7.7"/>',
    send:'<path d="m3 11 18-8-7.7 18-2.2-7.9L3 11Z"/><path d="M11.1 13.1 21 3"/>',
    more:'<circle cx="5" cy="12" r="1"/><circle cx="12" cy="12" r="1"/><circle cx="19" cy="12" r="1"/>',
    back:'<path d="m15 18-6-6 6-6"/>',
    download:'<path d="M12 3v12M7 10l5 5 5-5"/><path d="M5 21h14"/>',
    file:'<path d="M6 2h8l4 4v16H6V2Z"/><path d="M14 2v5h5"/>'
  };
  return `<svg viewBox="0 0 24 24" aria-hidden="true">${paths[name] || ''}</svg>`;
}

function avatarHtml(name, avatar, extra = '') {
  if (avatar) return `<div class="avatar ${extra}"><img src="${esc(avatar)}" alt="" /></div>`;
  const letter = (name || '?').trim().slice(0, 1).toUpperCase() || '?';
  return `<div class="avatar ${extra}">${esc(letter)}</div>`;
}

async function init() {
  state = await loadState();
  if (state.ui?.languagePolicyVersion !== 'english-default-v1') {
    state = await mutateState(s => {
      s.ui ||= {};
      s.profile.lang = 'en';
      s.ui.languagePolicyVersion = 'english-default-v1';
    });
  }
  if (!state.profile.lang || !LANGS.includes(state.profile.lang)) {
    state = await mutateState(s => { s.profile.lang = 'en'; });
  }
  activeRoom = state.ui?.activeRoomId || '';
  applyTheme();
  document.querySelector('#avatarPicker')?.addEventListener('change', onAvatarSelected);
  document.querySelector('#chatFilePicker')?.addEventListener('change', onChatFileSelected);
  chrome.runtime.sendMessage({ type:'network-status' }, response => {
    if (response?.status) {
      network = response.status;
      render();
    }
  });
  chrome.runtime.onMessage.addListener(message => {
    if (message?.type === 'network') {
      network = message.status;
      renderTopOnly();
    }
    if (message?.type === 'state-updated') refreshState(true);
  });
  chrome.storage.onChanged.addListener(changes => {
    if (changes.vtState) refreshState(true);
  });
  setInterval(() => {
    refreshState(false);
    processSignals();
  }, 900);
  await validateLicense().catch(() => false);
  await refreshState(false);
  render();
}

async function refreshState(shouldRender = true) {
  state = await loadState();
  if (state.ui?.activeRoomId && state.ui.activeRoomId !== activeRoom) {
    activeRoom = state.ui.activeRoomId;
    tab = 'chats';
  }
  if (shouldRender) render();
  await processSignals();
}

function renderTopOnly() {
  const dot = document.querySelector('.dot');
  const label = document.querySelector('.netLabel');
  if (dot) dot.classList.toggle('on', network === 'online');
  if (label) label.textContent = network === 'online' ? t('online') : t('reconnecting');
}

function render() {
  applyTheme();
  app.innerHTML = `
    <div class="app">
      <header class="top">
        <div class="brand">
          <div class="logo">${logoSvg()}</div>
          <div class="brandCopy"><div class="brandName">VeilTalk</div><div class="brandTag">${t('brandTag')}</div></div>
        </div>
        <div class="grow"></div>
        <div class="headTools">
          <button class="privacyBtn ${lightThemeOn() ? 'on' : ''}" data-action="toggleTheme" title="${esc(t('appearance'))}">${lightThemeOn() ? '☀' : '☾'}</button>
          <button class="privacyBtn ${privacyOn() ? 'on' : ''}" data-action="togglePrivacy" title="${esc(t('privacyMask'))}">${privacyOn() ? '◉' : '◎'}</button>
          <div class="net"><span class="dot ${network === 'online' ? 'on' : ''}"></span><span class="netLabel">${network === 'online' ? t('online') : t('reconnecting')}</span></div>
        </div>
      </header>
      <main class="screen">${activeRoom ? renderChat() : tab === 'contacts' ? renderContacts() : tab === 'settings' ? renderSettings() : renderChats()}</main>
      ${activeRoom ? '' : renderNav()}
      ${modal ? renderModal(modal) : ''}
      ${call ? renderCall() : ''}
    </div>`;
  bind();
  if (activeRoom) scrollChatBottom();
}

function renderNav() {
  return `<nav class="tabs">
    <button class="tab ${tab === 'chats' ? 'active' : ''}" data-tab="chats"><span class="tabIcon">${icon('chats')}</span>${t('chats')}</button>
    <button class="tab ${tab === 'contacts' ? 'active' : ''}" data-tab="contacts"><span class="tabIcon">${icon('contacts')}</span>${t('contacts')}</button>
    <button class="tab ${tab === 'settings' ? 'active' : ''}" data-tab="settings"><span class="tabIcon"><img class="tabAvatar" src="${esc(state.profile.avatar || 'icons/mask.svg')}" alt=""/></span>${t('profile')}</button>
  </nav>`;
}

function sortedContacts() {
  return Object.values(state.contacts || {}).sort((a, b) => (b.lastSeen || b.createdAt || 0) - (a.lastSeen || a.createdAt || 0));
}

function renderChats() {
  const contacts = sortedContacts().filter(contact => (state.messages[contact.roomId] || []).length || contact.status === 'connected');
  return `<section class="hero glass">
      <h1>${t('heroTitle')}</h1>
      <p>${t('heroText')}</p>
      <div class="actions">
        <button class="btn primary" data-action="createInvite"><span class="btnIcon">＋</span>${t('newChat')}</button>
        <button class="btn" data-action="pasteInvite"><span class="btnIcon">⌘</span>${t('pasteInvite')}</button>
      </div>
    </section>
    <div class="sectionHead"><h2>${t('chats')}</h2><span class="count">${contacts.length}</span></div>
    ${contacts.length ? contacts.map(contactCard).join('') : `<div class="empty"><div class="emptyIcon">${icon('chats')}</div><b>${t('noChats')}</b><div>${t('emptyHelp')}</div></div>`}`;
}

function renderContacts() {
  const contacts = sortedContacts();
  return `<section class="hero glass"><h1>${t('contacts')}</h1><p>${t('contactsHelp')}</p></section>
    <input class="search" id="contactSearch" placeholder="${esc(t('search'))}" />
    <div class="actions"><button class="btn primary" data-action="createInvite">＋ ${t('newChat')}</button><button class="btn" data-action="pasteInvite">⌘ ${t('pasteInvite')}</button></div>
    <div class="sectionHead"><h2>${t('contacts')}</h2><span class="count">${contacts.length}</span></div>
    <div id="contactList">${contacts.length ? contacts.map(contactCard).join('') : `<div class="empty"><div class="emptyIcon">${icon('contacts')}</div><b>${t('noContacts')}</b></div>`}</div>`;
}

function contactCard(contact) {
  const messages = state.messages[contact.roomId] || [];
  const last = messages[messages.length - 1];
  let summary = t('connected');
  if (last?.kind === 'text') summary = last.text;
  if (last?.kind === 'file') summary = `📎 ${last.name}`;
  if (contact.status !== 'connected') summary = t('pending');
  return `<div class="contact" data-name="${esc((contact.name || '').toLowerCase())}">
    ${avatarHtml(contact.name, contact.avatar)}
    <div class="meta" data-open="${esc(contact.roomId)}"><div class="name">${esc(safeName(contact.name))}</div><div class="sub">${esc(privacyOn() ? '••••••••••' : summary)}</div></div>
    <div class="inline">
      <button class="iconbtn" title="${esc(t('call'))}" data-call="audio" data-room="${esc(contact.roomId)}">${icon('phone')}</button>
      <button class="iconbtn" title="${esc(t('video'))}" data-call="video" data-room="${esc(contact.roomId)}">${icon('video')}</button>
    </div>
  </div>`;
}

function renderChat() {
  const contact = state.contacts[activeRoom];
  if (!contact) {
    activeRoom = '';
    return renderChats();
  }
  const messages = state.messages[activeRoom] || [];
  return `<div class="chat">
    <header class="chathead">
      <button class="iconbtn" data-action="back">${icon('back')}</button>
      ${avatarHtml(contact.name, contact.avatar)}
      <div class="meta grow"><div class="name">${esc(safeName(contact.name))}</div><div class="sub">${contact.status === 'connected' ? t('connected') : t('pending')}</div></div>
      <button class="iconbtn" title="${esc(t('call'))}" data-call="audio" data-room="${esc(contact.roomId)}">${icon('phone')}</button>
      <button class="iconbtn" title="${esc(t('video'))}" data-call="video" data-room="${esc(contact.roomId)}">${icon('video')}</button>
      <button class="iconbtn" title="${esc(t('chatActions'))}" data-action="chatMenu">${icon('more')}</button>
    </header>
    <div class="chatmsgs" id="chatmsgs">${messages.map(messageBubble).join('') || `<div class="empty">${t('message')}…</div>`}</div>
    <div class="composerWrap">
      ${emojiOpen ? `<div class="emojiPicker">${EMOJIS.map(emoji => `<button data-emoji="${emoji}">${emoji}</button>`).join('')}</div>` : ''}
      <div class="composer">
        <button class="round" data-action="pickChatFile" title="${esc(t('attach'))}">${icon('attach')}</button>
        <button class="round emojiButton" data-action="toggleEmoji" title="${esc(t('emoji'))}">☺</button>
        <textarea id="composerText" rows="1" placeholder="${esc(t('message'))}"></textarea>
        <button class="round send" data-action="sendMessage" title="${esc(t('send'))}">${icon('send')}</button>
      </div>
    </div>
  </div>`;
}

function messageBubble(message) {
  const time = new Date(message.ts || Date.now()).toLocaleTimeString([], { hour:'2-digit', minute:'2-digit' });
  if (message.kind === 'file') {
    const status = message.status ? t(`file_${message.status}`) : '';
    const progress = Number(message.progress || 0);
    return `<div class="bubble fileBubble ${message.from === 'me' ? 'me' : ''}">
      <button class="fileDownload" data-download="${esc(message.id)}">
        <span class="fileIcon">${icon(message.status === 'received' || message.status === 'sent' ? 'download' : 'file')}</span>
        <span class="fileCopy"><b>${esc(message.name || t('file'))}</b><small>${formatBytes(message.size)}${status ? ` · ${esc(status)}` : ''}</small></span>
      </button>
      ${progress > 0 && progress < 100 ? `<div class="fileProgress"><span style="width:${progress}%"></span></div>` : ''}
      <span class="time">${time}</span>
    </div>`;
  }
  return `<div class="bubble ${message.from === 'me' ? 'me' : ''}">${esc(message.text || '')}<span class="time">${time}</span></div>`;
}

function quotaUsed() {
  return Number(state.quota?.[todayKey()] || 0);
}

function quotaRemaining() {
  return Math.max(0, CONFIG.freeCallSecondsPerDay - quotaUsed());
}

function renderSettings() {
  const pro = state.pro?.active === true;
  const remaining = Math.ceil(quotaRemaining() / 60);
  const percent = Math.min(100, (quotaUsed() / CONFIG.freeCallSecondsPerDay) * 100);
  return `<section class="profileHero glass">
      <div class="profileAvatarWrap">${avatarHtml(state.profile.name, state.profile.avatar || 'icons/mask.svg', 'profileAvatar maskAvatar')}<button class="avatarEdit" data-action="pickAvatar" title="${esc(t('changeAvatar'))}">✎</button></div>
      <h1>${esc(state.profile.name)}</h1><div class="profileId">ID ${esc(state.profile.id)}</div>
      <div class="profileStatus"><span class="dot ${network === 'online' ? 'on' : ''}"></span>${network === 'online' ? t('online') : t('reconnecting')}</div>
    </section>
    <div class="sectionTitle">${t('profile')}</div>
    <div class="card glass stack">
      <label>${t('displayName')}<input class="field" id="profileName" value="${esc(state.profile.name)}"></label>
      <label>${t('language')}<select class="field" id="language">${LANGS.map(lang => `<option value="${lang}" ${lang === state.profile.lang ? 'selected' : ''}>${langNames[lang]}</option>`).join('')}</select></label>
      <div class="actions compact"><button class="btn" data-action="pickAvatar">${t('changeAvatar')}</button><button class="btn primary" data-action="saveProfile">${t('save')}</button></div>
    </div>
    <div class="sectionTitle">${t('appearance')}</div>
    <div class="card glass switchRow"><div class="switchCopy"><b>${lightThemeOn() ? t('lightTheme') : t('darkTheme')}</b><span>${t('themeHelp')}</span></div><button class="toggle ${lightThemeOn() ? 'on' : ''}" data-action="toggleTheme"></button></div>
    <div class="sectionTitle">${t('privacy')}</div>
    <div class="card glass switchRow"><div class="switchCopy"><b>${t('privacyMask')}</b><span>${t('privacyMaskHelp')}</span></div><button class="toggle ${privacyOn() ? 'on' : ''}" data-action="togglePrivacy"></button></div>
    <div class="sectionTitle">${t('plan')}</div>
    <div class="card glass"><div class="row"><h3 class="grow">${pro ? t('pro') : t('free')}</h3><span class="badge">${pro ? t('licenseValid') : t('free')}</span></div><p>${pro ? t('proPlan') : t('freePlan')}</p>${pro ? '' : `<div class="quota"><div style="width:${percent}%"></div></div><p>${t('remaining')}: <b>${remaining} ${t('minutes')}</b></p>`}</div>
    ${pro ? `<button class="btn" style="width:100%" data-action="manageSubscription">${t('manageSubscription')}</button>` : `<button class="btn primary" style="width:100%" data-action="upgrade">${t('upgrade')}</button>`}
    <div class="sectionTitle">${t('network')}</div>
    <div class="card glass"><h3>${t('directP2P')}</h3><p>${t('relayNote')}</p><p class="networkGood">${t('turnReady')}</p></div>
    <div class="sectionTitle">${t('about')}</div>
    <div class="card glass"><p>${t('localData')}</p><p>${t('version')}: ${CONFIG.version}</p></div>`;
}

function renderModal(value) {
  if (value.type === 'invite') {
    const copied = value.copied ? `<div class="successNote">✓ ${t('copied')}</div>` : '';
    return `<div class="modalback"><div class="modal glass">
      <h2>${t('createInvite')}</h2><p>${t('inviteHelp')}</p><div class="code">${esc(value.code)}</div>${copied}
      <div class="shareGrid">
        <button class="btn primary" data-action="copyInvite">${t('copy')}</button>
        <button class="btn" data-action="shareSystem">${t('share')}</button>
        <button class="shareTarget" data-action="shareTelegram">Telegram</button>
        <button class="shareTarget" data-action="shareWhatsapp">WhatsApp</button>
        <button class="shareTarget" data-action="shareEmail">Email</button>
      </div>
      <button class="btn ghost full" data-action="closeModal">${t('close')}</button>
    </div></div>`;
  }
  if (value.type === 'paste') return `<div class="modalback"><div class="modal glass"><h2>${t('pasteInvite')}</h2><p>${t('pasteHelp')}</p><textarea class="field" rows="7" id="inviteInput"></textarea><div class="actions"><button class="btn primary" data-action="acceptInvite">${t('save')}</button><button class="btn" data-action="closeModal">${t('cancel')}</button></div></div></div>`;
  if (value.type === 'chatMenu') return `<div class="modalback"><div class="modal glass"><h2>${t('chatActions')}</h2><div class="stack"><button class="btn" data-action="confirmClear">${t('clearHistory')}</button><button class="btn danger" data-action="confirmDelete">${t('deleteChat')}</button><button class="btn ghost" data-action="closeModal">${t('cancel')}</button></div></div></div>`;
  if (value.type === 'confirmClear') return confirmModal(t('clearHistory'), t('clearHistoryConfirm'), 'clearHistory');
  if (value.type === 'confirmDelete') return confirmModal(t('deleteChat'), t('deleteChatConfirm'), 'deleteChat');
  if (value.type === 'license') return `<div class="modalback"><div class="modal glass"><h2>${t('subscription')}</h2><input class="field" id="licenseInput" placeholder="${esc(t('licenseKey'))}"/><div class="actions"><button class="btn primary" data-action="activateLicense">${t('activate')}</button><button class="btn" data-action="closeModal">${t('cancel')}</button></div><p>${CONFIG.billing.enabled ? 'Monetize.software' : t('billingSoon')}</p></div></div>`;
  if (value.type === 'incoming') {
    const contact = state.contacts[value.roomId] || {};
    return `<div class="modalback"><div class="modal glass incomingModal">${avatarHtml(contact.name, contact.avatar, 'modalAvatar')}<h2>${t('incomingCall')}</h2><p>${esc(safeName(contact.name || value.name))} · ${value.video ? t('video') : t('call')}</p><div class="actions"><button class="btn good" data-action="answerCall">${t('answer')}</button><button class="btn danger" data-action="declineCall">${t('decline')}</button></div></div></div>`;
  }
  if (value.type === 'alert') return `<div class="modalback"><div class="modal glass"><h2>VeilTalk</h2><p>${esc(value.text)}</p><button class="btn primary full" data-action="closeModal">OK</button></div></div>`;
  return '';
}

function confirmModal(title, copy, action) {
  return `<div class="modalback"><div class="modal glass"><h2>${title}</h2><p>${copy}</p><div class="actions"><button class="btn danger" data-action="${action}">${t('delete')}</button><button class="btn" data-action="closeModal">${t('cancel')}</button></div></div></div>`;
}

function renderCall() {
  const contact = state.contacts[call.roomId] || {};
  const stateLabel = call.connectionState === 'connected' ? t('connected') : (call.incoming ? t('incomingCall') : t('calling'));
  return `<div class="callover">
    <div class="videos">
      <video class="remoteVideo" id="remoteVideo" autoplay playsinline></video>
      ${call.video ? `<video class="localVideo" id="localVideo" autoplay muted playsinline></video>` : `<div class="audioIdentity">${avatarHtml(contact.name, contact.avatar, 'callAvatar')}<h2>${esc(safeName(contact.name))}</h2><p>${stateLabel}</p></div>`}
    </div>
    <div class="callbar">
      <button class="callbtn ${call.micEnabled === false ? 'off' : ''}" data-action="toggleMic" title="${esc(t('mic'))}">🎙</button>
      ${call.video ? `<button class="callbtn ${call.camEnabled === false ? 'off' : ''}" data-action="toggleCam" title="${esc(t('camera'))}">📹</button><button class="callbtn" data-action="shareScreen" title="${esc(t('shareScreen'))}">▣</button>` : ''}
      <button class="callbtn end" data-action="hangup" title="${esc(t('hangup'))}">☎</button>
    </div>
  </div>`;
}

function bind() {
  document.querySelectorAll('[data-tab]').forEach(button => {
    button.onclick = () => {
      tab = button.dataset.tab;
      activeRoom = '';
      emojiOpen = false;
      render();
    };
  });
  document.querySelectorAll('[data-open]').forEach(element => { element.onclick = () => openRoom(element.dataset.open); });
  document.querySelectorAll('[data-call]').forEach(button => { button.onclick = () => startCall(button.dataset.room, button.dataset.call === 'video'); });
  document.querySelectorAll('[data-action]').forEach(button => { button.onclick = () => handleAction(button.dataset.action); });
  document.querySelectorAll('[data-download]').forEach(button => { button.onclick = () => downloadStoredFile(button.dataset.download); });
  document.querySelectorAll('[data-emoji]').forEach(button => { button.onclick = () => insertEmoji(button.dataset.emoji); });
  const search = document.querySelector('#contactSearch');
  if (search) search.oninput = () => {
    const query = search.value.toLowerCase();
    document.querySelectorAll('#contactList .contact').forEach(contact => { contact.style.display = contact.dataset.name.includes(query) ? 'flex' : 'none'; });
  };
  const composer = document.querySelector('#composerText');
  if (composer) {
    composer.onkeydown = event => {
      if (event.key === 'Enter' && !event.shiftKey) {
        event.preventDefault();
        sendMessage();
      }
    };
    composer.oninput = () => {
      composer.style.height = 'auto';
      composer.style.height = `${Math.min(composer.scrollHeight, 132)}px`;
    };
  }
  if (call) attachCallStreams();
}

async function handleAction(action) {
  if (action === 'createInvite') return createInvite();
  if (action === 'pasteInvite') { modal = { type:'paste' }; return render(); }
  if (action === 'closeModal') { modal = null; return render(); }
  if (action === 'copyInvite') return copyInvite();
  if (action === 'shareSystem') return shareInvite('system');
  if (action === 'shareTelegram') return shareInvite('telegram');
  if (action === 'shareWhatsapp') return shareInvite('whatsapp');
  if (action === 'shareEmail') return shareInvite('email');
  if (action === 'acceptInvite') return acceptInvite();
  if (action === 'back') {
    activeRoom = '';
    emojiOpen = false;
    await mutateState(s => { s.ui.activeRoomId = ''; });
    return render();
  }
  if (action === 'chatMenu') { modal = { type:'chatMenu' }; return render(); }
  if (action === 'confirmClear') { modal = { type:'confirmClear' }; return render(); }
  if (action === 'confirmDelete') { modal = { type:'confirmDelete' }; return render(); }
  if (action === 'clearHistory') return clearHistory();
  if (action === 'deleteChat') return deleteChat();
  if (action === 'sendMessage') return sendMessage();
  if (action === 'toggleEmoji') { emojiOpen = !emojiOpen; return render(); }
  if (action === 'pickChatFile') {
    const picker = document.querySelector('#chatFilePicker');
    if (picker) { picker.value = ''; picker.click(); }
    return;
  }
  if (action === 'saveProfile') return saveProfile();
  if (action === 'pickAvatar') {
    const picker = document.querySelector('#avatarPicker');
    if (picker) { picker.value = ''; picker.click(); }
    return;
  }
  if (action === 'togglePrivacy') return togglePrivacy();
  if (action === 'toggleTheme') return toggleTheme();
  if (action === 'upgrade') return upgrade();
  if (action === 'manageSubscription') return manageSubscription();
  if (action === 'license') { modal = { type:'license' }; return render(); }
  if (action === 'activateLicense') return doActivateLicense();
  if (action === 'answerCall') return answerIncoming();
  if (action === 'declineCall') return declineIncoming();
  if (action === 'hangup') return hangup();
  if (action === 'toggleMic') return toggleMic();
  if (action === 'toggleCam') return toggleCam();
  if (action === 'shareScreen') return shareScreen();
}

async function togglePrivacy() {
  state = await mutateState(s => { s.ui.privacyLens = !s.ui.privacyLens; });
  render();
}

async function toggleTheme() {
  state = await mutateState(s => { s.ui.theme = s.ui.theme === 'light' ? 'dark' : 'light'; });
  render();
}

async function onAvatarSelected(event) {
  const file = event.target.files?.[0];
  if (!file) return;
  if (!file.type.startsWith('image/')) return showAlert(t('avatarImageOnly'));
  if (file.size > 5 * 1024 * 1024) return showAlert(t('avatarTooLarge'));
  try {
    const avatar = await resizeAvatar(file);
    state = await mutateState(s => { s.profile.avatar = avatar; });
    render();
  } catch (_) {
    showAlert(t('avatarImageOnly'));
  }
}

function resizeAvatar(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onerror = reject;
    reader.onload = () => {
      const image = new Image();
      image.onerror = reject;
      image.onload = () => {
        const side = Math.min(image.naturalWidth, image.naturalHeight);
        const sx = (image.naturalWidth - side) / 2;
        const sy = (image.naturalHeight - side) / 2;
        const canvas = document.createElement('canvas');
        canvas.width = 160;
        canvas.height = 160;
        const context = canvas.getContext('2d');
        context.drawImage(image, sx, sy, side, side, 0, 0, 160, 160);
        resolve(canvas.toDataURL('image/jpeg', 0.76));
      };
      image.src = reader.result;
    };
    reader.readAsDataURL(file);
  });
}

async function openRoom(roomId) {
  activeRoom = roomId;
  emojiOpen = false;
  await mutateState(s => { s.ui.activeRoomId = roomId; });
  render();
}

function scrollChatBottom() {
  requestAnimationFrame(() => {
    const element = document.querySelector('#chatmsgs');
    if (element) element.scrollTop = element.scrollHeight;
  });
}

function showAlert(text) {
  modal = { type:'alert', text };
  render();
}

function insertEmoji(emoji) {
  const composer = document.querySelector('#composerText');
  if (!composer) return;
  const start = composer.selectionStart ?? composer.value.length;
  const end = composer.selectionEnd ?? composer.value.length;
  composer.value = `${composer.value.slice(0, start)}${emoji}${composer.value.slice(end)}`;
  composer.focus();
  composer.selectionStart = composer.selectionEnd = start + emoji.length;
}

async function createInvite() {
  if (!state.pro.active && Object.keys(state.contacts).length >= CONFIG.freeContacts) return showAlert(t('contactLimit'));
  const roomId = randomId(12);
  const secret = randomId(32);
  await mutateState(s => {
    s.contacts[roomId] = { roomId, secret, name:t('pending'), remoteInboxId:'', remoteProfileId:'', status:'pending', createdAt:Date.now() };
    s.messages[roomId] = [];
  });
  state = await loadState();
  const code = encodeInvite({ v:2, roomId, secret, inboxId:state.profile.inboxId, profileId:state.profile.id, name:state.profile.name });
  modal = { type:'invite', code, copied:false };
  render();
}

async function copyInvite() {
  await navigator.clipboard.writeText(modal.code);
  modal = { ...modal, copied:true };
  render();
}

function inviteShareText() {
  return `${t('shareInviteText')}\n\n${modal.code}`;
}

async function shareInvite(target) {
  const text = inviteShareText();
  if (target === 'system' && navigator.share) {
    try {
      await navigator.share({ title:'VeilTalk', text });
      return;
    } catch (_) {}
  }
  if (target === 'system') return copyInvite();
  let url = '';
  if (target === 'telegram') url = `https://t.me/share/url?url=&text=${encodeURIComponent(text)}`;
  if (target === 'whatsapp') url = `https://wa.me/?text=${encodeURIComponent(text)}`;
  if (target === 'email') url = `mailto:?subject=${encodeURIComponent('VeilTalk invitation')}&body=${encodeURIComponent(text)}`;
  if (url) chrome.tabs.create({ url });
}

async function acceptInvite() {
  const raw = document.querySelector('#inviteInput')?.value || '';
  let invite;
  try { invite = decodeInvite(raw); } catch (_) { return showAlert(t('invalidInvite')); }
  if (!invite.roomId || !invite.secret || !invite.inboxId) return showAlert(t('invalidInvite'));
  await mutateState(s => {
    s.contacts[invite.roomId] = {
      roomId:invite.roomId,
      secret:invite.secret,
      name:invite.name || 'Contact',
      remoteInboxId:invite.inboxId,
      remoteProfileId:invite.profileId || '',
      status:'connected',
      createdAt:Date.now(),
      lastSeen:Date.now()
    };
    s.messages[invite.roomId] ||= [];
  });
  state = await loadState();
  await sendEnvelope(invite.inboxId, invite.roomId, invite.secret, {
    type:'hello',
    roomId:invite.roomId,
    inboxId:state.profile.inboxId,
    profileId:state.profile.id,
    name:state.profile.name
  });
  modal = null;
  activeRoom = invite.roomId;
  await mutateState(s => { s.ui.activeRoomId = invite.roomId; });
  render();
}

async function sendMessage() {
  const input = document.querySelector('#composerText');
  const text = input?.value.trim();
  if (!text) return;
  const contact = state.contacts[activeRoom];
  if (!contact?.remoteInboxId) return showAlert(t('notReady'));
  const id = randomId(12);
  const timestamp = Date.now();
  input.value = '';
  emojiOpen = false;
  await mutateState(s => {
    const list = s.messages[activeRoom] ||= [];
    list.push({ id, from:'me', text, ts:timestamp, kind:'text' });
    const current = s.contacts[activeRoom];
    if (current) {
      current.lastMessage = text;
      current.lastSeen = timestamp;
    }
  });
  state = await loadState();
  render();
  try {
    await sendEnvelope(contact.remoteInboxId, contact.roomId, contact.secret, {
      type:'message', roomId:contact.roomId, id, text, sentAt:timestamp, name:state.profile.name
    });
  } catch (_) {
    showAlert(t('reconnecting'));
  }
}

async function clearHistory() {
  const roomId = activeRoom;
  await deleteRoomFiles(roomId).catch(() => {});
  state = await mutateState(s => {
    s.messages[roomId] = [];
    s.signals[roomId] = [];
    if (s.contacts[roomId]) s.contacts[roomId].lastMessage = '';
  });
  modal = null;
  render();
}

async function deleteChat() {
  const roomId = activeRoom;
  if (call?.roomId === roomId) await hangup();
  if (transfer?.roomId === roomId) closeTransfer(false);
  await deleteRoomFiles(roomId).catch(() => {});
  state = await mutateState(s => {
    delete s.contacts[roomId];
    delete s.messages[roomId];
    delete s.signals[roomId];
    s.ui.activeRoomId = '';
  });
  activeRoom = '';
  modal = null;
  render();
}

async function saveProfile() {
  const name = document.querySelector('#profileName')?.value.trim() || 'VeilTalk User';
  const lang = document.querySelector('#language')?.value || 'en';
  state = await mutateState(s => {
    s.profile.name = name;
    s.profile.lang = lang;
  });
  render();
}

async function upgrade() {
  if (!CONFIG.billing.enabled || !CONFIG.billing.checkoutUrl) return showAlert(t('billingSetupRequired'));
  chrome.tabs.create({ url:CONFIG.billing.checkoutUrl });
}

async function manageSubscription() {
  if (!CONFIG.billing.enabled || !CONFIG.billing.customerPortalUrl) return showAlert(t('billingSetupRequired'));
  chrome.tabs.create({ url:CONFIG.billing.customerPortalUrl });
}

async function doActivateLicense() {
  const key = document.querySelector('#licenseInput')?.value.trim();
  if (!key) return;
  try {
    await activateLicense(key);
    state = await loadState();
    modal = { type:'alert', text:t('licenseValid') };
    render();
  } catch (error) {
    showAlert(error.message === 'BILLING_DISABLED' ? t('billingSetupRequired') : t('licenseInvalid'));
  }
}

async function canCall() {
  return state.pro.active || quotaRemaining() > 0;
}

async function addQuota(seconds) {
  if (state.pro.active || seconds <= 0) return;
  state = await mutateState(s => {
    const key = todayKey();
    s.quota[key] = Number(s.quota[key] || 0) + seconds;
  });
}

async function sendRtc(contact, purpose, action, sessionIdValue, extra = {}) {
  return sendEnvelope(contact.remoteInboxId, contact.roomId, contact.secret, {
    type:'rtc',
    roomId:contact.roomId,
    signalId:randomId(12),
    sessionId:sessionIdValue,
    purpose,
    action,
    sentAt:Date.now(),
    ...extra
  });
}

async function startCall(roomId, video) {
  const contact = state.contacts[roomId];
  if (!contact?.remoteInboxId) return showAlert(t('notReady'));
  if (!(await canCall())) return showAlert(t('callLimit'));
  if (call) return;
  try {
    const local = await navigator.mediaDevices.getUserMedia({
      audio:{ echoCancellation:true, noiseSuppression:true, autoGainControl:true },
      video:video ? { width:{ ideal:1280 }, height:{ ideal:720 }, frameRate:{ ideal:30, max:30 } } : false
    });
    const pc = await createPeerConnection();
    call = {
      roomId,
      sessionId:randomId(12),
      video,
      pc,
      local,
      remote:new MediaStream(),
      startedAt:Date.now(),
      connectedAt:0,
      handled:new Set(),
      pendingIce:[],
      incoming:false,
      micEnabled:true,
      camEnabled:video,
      connectionState:'connecting'
    };
    setupCallPeer(contact);
    local.getTracks().forEach(track => pc.addTrack(track, local));
    await sendRtc(contact, 'call', 'invite', call.sessionId, { video, name:state.profile.name });
    const offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    await sendRtc(contact, 'call', 'offer', call.sessionId, { sdp:pc.localDescription, video });
    render();
  } catch (error) {
    call = null;
    showAlert(error?.message || t('callFailed'));
  }
}

function setupCallPeer(contact) {
  const session = call;
  const pc = session.pc;
  pc.ontrack = event => {
    const stream = event.streams[0];
    if (stream) session.remote = stream;
    else if (!session.remote.getTracks().includes(event.track)) session.remote.addTrack(event.track);
    attachCallStreams();
  };
  pc.onicecandidate = event => {
    if (event.candidate) sendRtc(contact, 'call', 'ice', session.sessionId, { candidate:event.candidate.toJSON() }).catch(() => {});
  };
  pc.onconnectionstatechange = () => {
    if (call !== session) return;
    session.connectionState = pc.connectionState;
    if (pc.connectionState === 'connected') {
      session.connectedAt ||= Date.now();
      clearTimeout(session.disconnectTimer);
      session.quotaTimer ||= setInterval(() => enforceCallQuota(session), 5000);
      render();
    }
    if (pc.connectionState === 'disconnected') {
      clearTimeout(session.disconnectTimer);
      session.disconnectTimer = setTimeout(() => {
        if (call === session && session.pc.connectionState === 'disconnected') failActiveCall(session);
      }, 10000);
    }
    if (pc.connectionState === 'failed') {
      failActiveCall(session);
    }
  };
}

async function enforceCallQuota(session) {
  if (call !== session || state.pro.active || !session.connectedAt) return;
  const currentSeconds = Math.floor((Date.now() - session.connectedAt) / 1000);
  if (quotaRemaining() <= currentSeconds) {
    await hangup(true);
    showAlert(t('callLimit'));
  }
}

async function failActiveCall(session) {
  if (call !== session) return;
  await hangup(false);
  showAlert(t('callFailed'));
}

async function processSignals() {
  if (!state) return;
  state = await loadState();
  await processCallSignals();
  await processFileSignals();
}

async function processCallSignals() {
  if (!call && modal?.type !== 'incoming') {
    for (const [roomId, list] of Object.entries(state.signals || {})) {
      const invite = [...list].reverse().find(signal => signal.type === 'rtc' && signal.purpose === 'call' && signal.action === 'invite' && !signal.uiSeen);
      if (!invite) continue;
      await mutateState(s => {
        const stored = (s.signals[roomId] || []).find(item => signalId(item) === signalId(invite));
        if (stored) stored.uiSeen = true;
      });
      const contact = state.contacts[roomId];
      modal = { type:'incoming', roomId, sessionId:invite.sessionId, video:!!invite.video, name:contact?.name };
      render();
      break;
    }
  }
  if (!call) return;
  const list = state.signals[call.roomId] || [];
  for (const signal of list) {
    if (signal.type !== 'rtc' || signal.purpose !== 'call' || signal.sessionId !== call.sessionId) continue;
    const id = signalId(signal);
    if (call.handled.has(id)) continue;
    try {
      if (signal.action === 'answer') {
        await call.pc.setRemoteDescription(signal.sdp);
        await flushIce(call);
      } else if (signal.action === 'ice') {
        await addIceOrQueue(call, signal.candidate);
      } else if (signal.action === 'hangup') {
        call.handled.add(id);
        return hangup(false);
      }
      call.handled.add(id);
    } catch (_) {}
  }
}

async function answerIncoming() {
  const roomId = modal?.roomId;
  const sessionIdValue = modal?.sessionId;
  const contact = state.contacts[roomId];
  if (!contact) return;
  if (!(await canCall())) {
    modal = null;
    return showAlert(t('callLimit'));
  }
  state = await loadState();
  const offer = [...(state.signals[roomId] || [])].reverse().find(signal => signal.type === 'rtc' && signal.purpose === 'call' && signal.action === 'offer' && signal.sessionId === sessionIdValue);
  if (!offer) return showAlert(t('reconnecting'));
  try {
    const local = await navigator.mediaDevices.getUserMedia({
      audio:{ echoCancellation:true, noiseSuppression:true, autoGainControl:true },
      video:offer.video ? { width:{ ideal:1280 }, height:{ ideal:720 }, frameRate:{ ideal:30, max:30 } } : false
    });
    const pc = await createPeerConnection();
    call = {
      roomId,
      sessionId:sessionIdValue,
      video:!!offer.video,
      pc,
      local,
      remote:new MediaStream(),
      startedAt:Date.now(),
      connectedAt:0,
      handled:new Set([signalId(offer)]),
      pendingIce:[],
      incoming:true,
      micEnabled:true,
      camEnabled:!!offer.video,
      connectionState:'connecting'
    };
    modal = null;
    setupCallPeer(contact);
    local.getTracks().forEach(track => pc.addTrack(track, local));
    await pc.setRemoteDescription(offer.sdp);
    await flushIce(call);
    const answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    await sendRtc(contact, 'call', 'answer', call.sessionId, { sdp:pc.localDescription });
    render();
    await processSignals();
  } catch (error) {
    call = null;
    showAlert(error?.message || t('callFailed'));
  }
}

async function declineIncoming() {
  const roomId = modal?.roomId;
  const sessionIdValue = modal?.sessionId;
  const contact = state.contacts[roomId];
  modal = null;
  if (contact?.remoteInboxId) await sendRtc(contact, 'call', 'hangup', sessionIdValue).catch(() => {});
  render();
}

async function hangup(notify = true) {
  if (!call) return;
  const old = call;
  call = null;
  clearInterval(old.quotaTimer);
  clearTimeout(old.disconnectTimer);
  const seconds = old.connectedAt ? Math.max(0, Math.round((Date.now() - old.connectedAt) / 1000)) : 0;
  await addQuota(seconds);
  old.local?.getTracks().forEach(track => track.stop());
  old.remote?.getTracks().forEach(track => track.stop());
  try { old.pc?.close(); } catch (_) {}
  const contact = state.contacts[old.roomId];
  if (notify && contact?.remoteInboxId) sendRtc(contact, 'call', 'hangup', old.sessionId).catch(() => {});
  state = await loadState();
  render();
}

function attachCallStreams() {
  const localVideo = document.querySelector('#localVideo');
  const remoteVideo = document.querySelector('#remoteVideo');
  if (localVideo && call?.local) localVideo.srcObject = call.local;
  if (remoteVideo && call?.remote) remoteVideo.srcObject = call.remote;
}

function toggleMic() {
  const track = call?.local?.getAudioTracks()[0];
  if (!track) return;
  track.enabled = !track.enabled;
  call.micEnabled = track.enabled;
  render();
}

function toggleCam() {
  const track = call?.local?.getVideoTracks()[0];
  if (!track) return;
  track.enabled = !track.enabled;
  call.camEnabled = track.enabled;
  render();
}

async function shareScreen() {
  if (!call?.video) return;
  if (!state.pro.active) return showAlert(t('proPlan'));
  try {
    const display = await navigator.mediaDevices.getDisplayMedia({ video:true, audio:false });
    const track = display.getVideoTracks()[0];
    const sender = call.pc.getSenders().find(item => item.track?.kind === 'video');
    if (!sender) return;
    const camera = call.local.getVideoTracks()[0];
    await sender.replaceTrack(track);
    call.screenTrack = track;
    track.onended = async () => {
      if (camera?.readyState === 'live') await sender.replaceTrack(camera);
      call.screenTrack = null;
      attachCallStreams();
    };
  } catch (_) {}
}

async function onChatFileSelected(event) {
  const file = event.target.files?.[0];
  if (!file) return;
  await sendFile(file);
}

async function sendFile(file) {
  if (transfer) return showAlert(t('fileTransferBusy'));
  const contact = state.contacts[activeRoom];
  if (!contact?.remoteInboxId) return showAlert(t('notReady'));
  const limit = state.pro.active ? CONFIG.proFileBytes : CONFIG.freeFileBytes;
  if (file.size > limit) return showAlert(t('fileTooLarge'));
  const id = randomId(12);
  const sessionIdValue = randomId(12);
  const roomId = activeRoom;
  await putFile({ id, roomId, name:file.name, type:file.type || 'application/octet-stream', blob:file });
  state = await mutateState(s => {
    const list = s.messages[roomId] ||= [];
    list.push({ id, from:'me', ts:Date.now(), kind:'file', name:file.name, mime:file.type || 'application/octet-stream', size:file.size, status:'connecting', progress:0 });
  });
  render();
  try {
    const pc = await createPeerConnection();
    const channel = pc.createDataChannel('veiltalk-file', { ordered:true });
    transfer = {
      direction:'out',
      roomId,
      sessionId:sessionIdValue,
      fileId:id,
      file,
      pc,
      channel,
      handled:new Set(),
      pendingIce:[],
      complete:false
    };
    setupTransferPeer(contact);
    setupDataChannel(channel);
    const offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    await sendRtc(contact, 'file', 'offer', sessionIdValue, {
      sdp:pc.localDescription,
      file:{ id, name:file.name, type:file.type || 'application/octet-stream', size:file.size }
    });
  } catch (_) {
    await updateFileMessage(roomId, id, { status:'failed' });
    closeTransfer(false);
    showAlert(t('fileFailed'));
  }
}

function setupTransferPeer(contact) {
  const session = transfer;
  session.pc.onicecandidate = event => {
    if (event.candidate) sendRtc(contact, 'file', 'ice', session.sessionId, { candidate:event.candidate.toJSON() }).catch(() => {});
  };
  session.pc.onconnectionstatechange = () => {
    if (['failed','closed'].includes(session.pc.connectionState) && !session.complete) {
      updateFileMessage(session.roomId, session.fileId, { status:'failed' });
      closeTransfer(false);
    }
  };
  session.pc.ondatachannel = event => {
    session.channel = event.channel;
    setupDataChannel(event.channel);
  };
}

function setupDataChannel(channel) {
  channel.binaryType = 'arraybuffer';
  channel.bufferedAmountLowThreshold = 256 * 1024;
  channel.onopen = () => {
    if (transfer?.direction === 'out') transmitFile().catch(() => {
      updateFileMessage(transfer.roomId, transfer.fileId, { status:'failed' });
      closeTransfer(false);
    });
  };
  channel.onmessage = event => receiveFileMessage(event.data).catch(async () => {
    if (!transfer) return;
    await updateFileMessage(transfer.roomId, transfer.fileId, { status:'failed' });
    closeTransfer(false);
  });
}

async function transmitFile() {
  const session = transfer;
  if (!session || session.direction !== 'out') return;
  const channel = session.channel;
  const file = session.file;
  channel.send(JSON.stringify({ type:'meta', id:session.fileId, name:file.name, mime:file.type || 'application/octet-stream', size:file.size }));
  const chunkSize = 48 * 1024;
  let lastPercent = -1;
  for (let offset = 0; offset < file.size; offset += chunkSize) {
    while (channel.bufferedAmount > 1024 * 1024) await waitForBuffer(channel);
    const chunk = await file.slice(offset, Math.min(file.size, offset + chunkSize)).arrayBuffer();
    channel.send(chunk);
    const percent = Math.min(99, Math.floor(((offset + chunk.byteLength) / file.size) * 100));
    if (percent >= lastPercent + 4) {
      lastPercent = percent;
      await updateFileMessage(session.roomId, session.fileId, { status:'sending', progress:percent }, false);
      renderTransferProgress();
    }
  }
  channel.send(JSON.stringify({ type:'end', id:session.fileId }));
  await updateFileMessage(session.roomId, session.fileId, { status:'sent', progress:100 });
  session.complete = true;
  setTimeout(() => closeTransfer(true), 1200);
}

function waitForBuffer(channel) {
  return new Promise(resolve => {
    if (channel.bufferedAmount <= channel.bufferedAmountLowThreshold) return resolve();
    const done = () => {
      channel.removeEventListener('bufferedamountlow', done);
      resolve();
    };
    channel.addEventListener('bufferedamountlow', done, { once:true });
  });
}

async function receiveFileMessage(data) {
  const session = transfer;
  if (!session) return;
  if (typeof data === 'string') {
    let message;
    try { message = JSON.parse(data); } catch (_) { return; }
    if (message.type === 'ack' && session.direction === 'out') {
      session.complete = true;
      closeTransfer(true);
      return;
    }
    if (session.direction !== 'in') return;
    if (message.type === 'meta') {
      session.meta = { ...session.meta, ...message };
      return;
    }
    if (message.type === 'end') {
      await session.writeChain;
      const mime = session.meta.type || session.meta.mime || 'application/octet-stream';
      if (session.opfs) {
        await commitIncomingFile({ id:session.fileId, roomId:session.roomId, name:session.meta.name, type:mime, opfs:session.opfs, size:session.received });
        session.opfs = null;
      } else {
        const blob = new Blob(session.chunks, { type:mime });
        await putFile({ id:session.fileId, roomId:session.roomId, name:session.meta.name, type:mime, blob });
      }
      await updateFileMessage(session.roomId, session.fileId, { status:'received', progress:100, size:session.received });
      session.complete = true;
      session.channel.send(JSON.stringify({ type:'ack', id:session.fileId }));
      setTimeout(() => closeTransfer(true), 1200);
    }
    return;
  }
  if (session.direction !== 'in') return;
  const buffer = data instanceof ArrayBuffer ? data : await data.arrayBuffer();
  if (session.opfs) {
    session.writeChain = session.writeChain.then(() => session.opfs?.writer.write(buffer));
    await session.writeChain;
  } else {
    session.chunks.push(buffer);
  }
  session.received += buffer.byteLength;
  const percent = Math.min(99, Math.floor((session.received / Math.max(1, session.meta.size)) * 100));
  if (percent >= session.lastPercent + 4) {
    session.lastPercent = percent;
    await updateFileMessage(session.roomId, session.fileId, { status:'receiving', progress:percent }, false);
    renderTransferProgress();
  }
}

async function processFileSignals() {
  if (!transfer) {
    for (const [roomId, list] of Object.entries(state.signals || {})) {
      const offer = [...list].reverse().find(signal => signal.type === 'rtc' && signal.purpose === 'file' && signal.action === 'offer' && !signal.uiSeen);
      if (!offer) continue;
      await mutateState(s => {
        const stored = (s.signals[roomId] || []).find(item => signalId(item) === signalId(offer));
        if (stored) stored.uiSeen = true;
      });
      await acceptFileOffer(roomId, offer);
      break;
    }
  }
  if (!transfer) return;
  const list = state.signals[transfer.roomId] || [];
  for (const signal of list) {
    if (signal.type !== 'rtc' || signal.purpose !== 'file' || signal.sessionId !== transfer.sessionId) continue;
    const id = signalId(signal);
    if (transfer.handled.has(id)) continue;
    try {
      if (signal.action === 'answer' && transfer.direction === 'out') {
        await transfer.pc.setRemoteDescription(signal.sdp);
        await flushIce(transfer);
      } else if (signal.action === 'ice') {
        await addIceOrQueue(transfer, signal.candidate);
      } else if (signal.action === 'hangup' && !transfer.complete) {
        await updateFileMessage(transfer.roomId, transfer.fileId, { status:'failed' });
        closeTransfer(false);
      }
      transfer?.handled.add(id);
    } catch (_) {}
  }
}

async function acceptFileOffer(roomId, offer) {
  const contact = state.contacts[roomId];
  if (!contact?.remoteInboxId || !offer.file) return;
  const limit = state.pro.active ? CONFIG.proFileBytes : CONFIG.freeFileBytes;
  if (offer.file.size > limit) {
    await sendRtc(contact, 'file', 'hangup', offer.sessionId, { reason:'too-large' }).catch(() => {});
    return;
  }
  try {
    const pc = await createPeerConnection();
    const opfs = await createIncomingFile(offer.file.id).catch(() => null);
    transfer = {
      direction:'in',
      roomId,
      sessionId:offer.sessionId,
      fileId:offer.file.id,
      meta:offer.file,
      pc,
      channel:null,
      opfs,
      chunks:[],
      writeChain:Promise.resolve(),
      received:0,
      lastPercent:-1,
      handled:new Set([signalId(offer)]),
      pendingIce:[],
      complete:false
    };
    state = await mutateState(s => {
      const list = s.messages[roomId] ||= [];
      if (!list.some(message => message.id === offer.file.id)) {
        list.push({ id:offer.file.id, from:'remote', ts:Date.now(), kind:'file', name:offer.file.name, mime:offer.file.type, size:offer.file.size, status:'receiving', progress:0 });
      }
    });
    setupTransferPeer(contact);
    await pc.setRemoteDescription(offer.sdp);
    await flushIce(transfer);
    const answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    await sendRtc(contact, 'file', 'answer', offer.sessionId, { sdp:pc.localDescription });
    render();
  } catch (_) {
    closeTransfer(false);
  }
}

async function updateFileMessage(roomId, fileId, patch, shouldRender = true) {
  state = await mutateState(s => {
    const message = (s.messages[roomId] || []).find(item => item.id === fileId);
    if (message) Object.assign(message, patch);
  });
  if (shouldRender) render();
}

function renderTransferProgress() {
  const now = Date.now();
  if (now - lastTransferRender < 350) return;
  lastTransferRender = now;
  render();
}

function closeTransfer(notify) {
  if (!transfer) return;
  const old = transfer;
  transfer = null;
  if (notify) {
    const contact = state.contacts[old.roomId];
    if (contact?.remoteInboxId) sendRtc(contact, 'file', 'hangup', old.sessionId, { complete:true }).catch(() => {});
  }
  try { old.channel?.close(); } catch (_) {}
  try { old.pc?.close(); } catch (_) {}
  if (!old.complete && old.opfs) abortIncomingFile(old.opfs).catch(() => {});
}

async function downloadStoredFile(fileId) {
  const record = await getFile(fileId).catch(() => null);
  if (!record?.blob) return showAlert(t('fileUnavailable'));
  const url = URL.createObjectURL(record.blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = record.name || 'download';
  link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

init();
