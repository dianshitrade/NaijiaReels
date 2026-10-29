import { resolveCoverUrl } from './content.service';
import { MemoryKvStore } from '../prisma/redis.service';

describe('resolveCoverUrl', () => {
  const base = 'https://naijareels-media.onrender.com';
  it('maps legacy /media/<slug>/cover.jpg to absolute', () => {
    expect(resolveCoverUrl('/media/lagos-hustle/cover.jpg', base)).toBe(`${base}/lagos-hustle/cover.jpg`);
  });
  it('maps <slug>/cover.jpg and trims trailing slash', () => {
    expect(resolveCoverUrl('lagos-hustle/cover.jpg', `${base}/`)).toBe(`${base}/lagos-hustle/cover.jpg`);
  });
  it('keeps absolute URLs and null', () => {
    expect(resolveCoverUrl('https://cdn.x/a.jpg', base)).toBe('https://cdn.x/a.jpg');
    expect(resolveCoverUrl(null, base)).toBeNull();
  });
});

describe('MemoryKvStore', () => {
  it('get/set/incr/del', async () => {
    const kv = new MemoryKvStore();
    expect(await kv.get('a')).toBeNull();
    await kv.set('a', '1');
    expect(await kv.get('a')).toBe('1');
    expect(await kv.incr('n')).toBe(1);
    expect(await kv.incr('n')).toBe(2);
    await kv.del('a');
    expect(await kv.get('a')).toBeNull();
  });
});
