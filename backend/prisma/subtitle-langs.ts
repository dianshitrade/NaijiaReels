/**
 * Subtitle tracks offered per episode: [BCP-47 lang, display label].
 * Labels are shown in the app UI and must stay Latin-script (no CJK), e.g. zh-Hans is labelled "Chinese".
 * Keep in sync with LANGS in scripts/subs/pipeline.py.
 */
export const SUB_LANGS: ReadonlyArray<readonly [string, string]> = [
  ['en', 'English'],
  ['pcm', 'Naija Pidgin'],
  ['yo', 'Yorùbá'],
  ['ig', 'Igbo'],
  ['ha', 'Hausa'],
  ['fr', 'Français'],
  ['zh-Hans', 'Chinese'],
];
