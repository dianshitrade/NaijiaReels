import { readFileSync } from 'fs';
import { join } from 'path';
import { SUB_LANGS } from '../../prisma/subtitle-langs';

const LATIN_LABEL = /^[\p{Script=Latin} ]+$/u;
const CJK = /[\u3000-\u9fff\uff00-\uffef]/;

describe('subtitle labels', () => {
  it('has 7 tracks incl. zh-Hans labelled "Chinese"', () => {
    expect(SUB_LANGS.map(([l]) => l)).toEqual(['en', 'pcm', 'yo', 'ig', 'ha', 'fr', 'zh-Hans']);
    expect(Object.fromEntries(SUB_LANGS)['zh-Hans']).toBe('Chinese');
  });

  it('labels are Latin script only (no CJK in UI labels)', () => {
    for (const [, label] of SUB_LANGS) {
      expect(label).toMatch(LATIN_LABEL);
      expect(label).not.toMatch(CJK);
    }
  });

  it.each(['ep1', 'ep2'])('master.m3u8 %s NAME attributes are Latin and match seed labels', (ep) => {
    const master = readFileSync(join(__dirname, '../../media/mama-in-law-wahala', ep, 'master.m3u8'), 'utf8');
    const tracks = [...master.matchAll(/TYPE=SUBTITLES,[^\n]*NAME="([^"]+)",LANGUAGE="([^"]+)"/g)].map((m) => [m[2], m[1]]);
    expect(tracks).toEqual(SUB_LANGS.map(([l, n]) => [l, n]));
    for (const [, name] of tracks) expect(name).not.toMatch(CJK);
  });
});
