import { createHmac } from 'crypto';

/** Signs `/media/<path>` with an expiry: sig = base64url(HMAC-SHA256(secret, `${exp}${uriPath}`)). */
export function signMediaUrl(baseUrl: string, hlsPath: string, secret: string, ttlSec: number, now = Date.now()) {
  const exp = Math.floor(now / 1000) + ttlSec;
  const url = new URL(`${baseUrl.replace(/\/$/, '')}/${hlsPath.replace(/^\//, '')}`);
  const sig = createHmac('sha256', secret).update(`${exp}${url.pathname}`).digest('base64url');
  url.searchParams.set('exp', String(exp));
  url.searchParams.set('sig', sig);
  return { hlsUrl: url.toString(), expiresAt: new Date(exp * 1000).toISOString() };
}

export function verifyMediaSig(pathname: string, exp: number, sig: string, secret: string, now = Date.now()): boolean {
  if (exp * 1000 < now) return false;
  return createHmac('sha256', secret).update(`${exp}${pathname}`).digest('base64url') === sig;
}
