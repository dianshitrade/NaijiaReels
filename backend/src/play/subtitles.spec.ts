import { toSubtitles } from './subtitles';

describe('toSubtitles', () => {
  const base = 'https://media.example.com/';

  it('returns [] when absent or not an array', () => {
    expect(toSubtitles(null, base)).toEqual([]);
    expect(toSubtitles(undefined, base)).toEqual([]);
    expect(toSubtitles({ lang: 'en' }, base)).toEqual([]);
  });

  it('maps stored paths to absolute urls and keeps order', () => {
    const raw = [
      { lang: 'en', label: 'English', path: 'mama/ep1/subs/en.vtt' },
      { lang: 'pcm', label: 'Naija Pidgin', path: '/media/mama/ep1/subs/pcm.vtt' },
    ];
    expect(toSubtitles(raw, base)).toEqual([
      { lang: 'en', label: 'English', url: 'https://media.example.com/mama/ep1/subs/en.vtt' },
      { lang: 'pcm', label: 'Naija Pidgin', url: 'https://media.example.com/mama/ep1/subs/pcm.vtt' },
    ]);
  });

  it('skips malformed entries', () => {
    expect(toSubtitles([{ lang: 'fr' }, { lang: 'yo', label: 'Yorùbá', path: 'x/yo.vtt' }], base)).toEqual([
      { lang: 'yo', label: 'Yorùbá', url: 'https://media.example.com/x/yo.vtt' },
    ]);
  });
});
