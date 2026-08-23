import { CONFIG } from './config.js';
import { mutateState } from './storage.js';

export async function activateLicense() {
  // Monetize.software owns checkout and entitlement validation. Never trust a
  // locally entered key: live activation is enabled only with its packaged SDK.
  throw new Error('BILLING_DISABLED');
}

export async function validateLicense() {
  if (CONFIG.billing.enabled) throw new Error('MONETIZE_SDK_REQUIRED');
  await mutateState(s => {
    s.pro.active = false;
    s.pro.checkedAt = Date.now();
  });
  return false;
}
