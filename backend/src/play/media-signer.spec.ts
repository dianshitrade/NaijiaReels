import { signMediaUrl, verifyMediaSig } from './media-signer';

describe('media signer', () => {
  it('signs and verifies', () => {
    const now = 1_800_000_000_000;
    const { hlsUrl, expiresAt } = signMediaUrl('http://h/media/', 'a/ep1/master.m3u8', 's3cret', 60, now);
    const u = new URL(hlsUrl);
    expect(u.pathname).toBe('/media/a/ep1/master.m3u8');
    expect(expiresAt).toBe(new Date(now + 60_000).toISOString());
    const exp = Number(u.searchParams.get('exp'));
    const sig = u.searchParams.get('sig') ?? '';
    expect(verifyMediaSig(u.pathname, exp, sig, 's3cret', now)).toBe(true);
    expect(verifyMediaSig(u.pathname, exp, sig, 'other', now)).toBe(false);
    expect(verifyMediaSig(u.pathname, exp, sig, 's3cret', now + 120_000)).toBe(false);
  });
});
