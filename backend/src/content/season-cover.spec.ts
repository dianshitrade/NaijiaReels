import { dramaCoverUrl, toSeasons } from './content.service';

const base = 'https://naijareels-media.onrender.com';

describe('dramaCoverUrl', () => {
  it('uses season 1 cover when present', () => {
    expect(dramaCoverUrl({ coverUrl: 'lagos-hustle/cover.jpg', seasons: [{ seasonNo: 1, title: null, coverPath: 'lagos-hustle/s1/cover.jpg' }] }, base)).toBe(
      `${base}/lagos-hustle/s1/cover.jpg`,
    );
  });
  it('falls back to drama cover when season 1 has no cover, no seasons, or only other seasons', () => {
    const fb = `${base}/lagos-hustle/cover.jpg`;
    expect(dramaCoverUrl({ coverUrl: 'lagos-hustle/cover.jpg', seasons: [{ seasonNo: 1, title: 'S1', coverPath: null }] }, base)).toBe(fb);
    expect(dramaCoverUrl({ coverUrl: 'lagos-hustle/cover.jpg', seasons: [] }, base)).toBe(fb);
    expect(dramaCoverUrl({ coverUrl: 'lagos-hustle/cover.jpg' }, base)).toBe(fb);
    expect(dramaCoverUrl({ coverUrl: 'lagos-hustle/cover.jpg', seasons: [{ seasonNo: 2, title: null, coverPath: 'lagos-hustle/s2/cover.jpg' }] }, base)).toBe(fb);
  });
  it('returns null when nothing is set', () => {
    expect(dramaCoverUrl({ coverUrl: null, seasons: [] }, base)).toBeNull();
  });
});

describe('toSeasons', () => {
  it('sorts by seasonNo and resolves absolute URLs (null when missing)', () => {
    expect(
      toSeasons(
        [
          { seasonNo: 2, title: 'Season 2', coverPath: null },
          { seasonNo: 1, title: 'Season 1', coverPath: 'village-prince/s1/cover.jpg' },
        ],
        `${base}/`,
      ),
    ).toEqual([
      { seasonNo: 1, title: 'Season 1', coverUrl: `${base}/village-prince/s1/cover.jpg` },
      { seasonNo: 2, title: 'Season 2', coverUrl: null },
    ]);
    expect(toSeasons(undefined, base)).toEqual([]);
  });
});
