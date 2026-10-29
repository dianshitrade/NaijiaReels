import { resolveCoverUrl } from '../content/content.service';

export interface SubtitleTrack {
  lang: string;
  label: string;
  url: string;
}

/** Map the stored `episodes.subtitles` JSON ([{lang,label,path}]) to absolute URLs; [] when absent/invalid. */
export function toSubtitles(raw: unknown, mediaBaseUrl: string): SubtitleTrack[] {
  if (!Array.isArray(raw)) return [];
  return raw.flatMap((t: unknown) => {
    const s = t as { lang?: unknown; label?: unknown; path?: unknown };
    if (typeof s?.lang !== 'string' || typeof s.label !== 'string' || typeof s.path !== 'string') return [];
    const url = resolveCoverUrl(s.path, mediaBaseUrl);
    return url ? [{ lang: s.lang, label: s.label, url }] : [];
  });
}
