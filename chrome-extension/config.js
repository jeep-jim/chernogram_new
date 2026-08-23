export const CONFIG = {
  appName: 'VeilTalk',
  version: '0.2.0',
  relayHttp: 'https://ntfy.sh',
  relayWs: 'wss://ntfy.sh',
  freeCallSecondsPerDay: 10 * 60,
  freeContacts: 20,
  freeFileBytes: 25 * 1024 * 1024,
  proFileBytes: 1024 * 1024 * 1024,
  billing: {
    enabled: false,
    provider: 'monetize',
    paywallId: '',
    apiOrigin: '',
    checkoutUrl: '',
    customerPortalUrl: '',
    monthlyPriceUsd: 9.99
  },
  iceServers: [
    { urls: 'stun:stun.cloudflare.com:3478' },
    { urls: 'stun:stun.l.google.com:19302' }
  ],
  openRelay: {
    enabled: true,
    host: 'staticauth.openrelay.metered.ca',
    sharedSecret: 'openrelayprojectsecret',
    credentialHours: 12
  }
};
