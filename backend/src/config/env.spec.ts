import { validateEnv } from './env';

const base = {
  DATABASE_URL: 'postgresql://u:p@localhost:5432/db',
  REDIS_URL: 'redis://localhost:6379',
  JWT_SECRET: '0123456789abcdef',
  MEDIA_BASE_URL: 'http://localhost:8080/media',
  MEDIA_SIGN_SECRET: 'secret123',
};

describe('validateEnv', () => {
  it('parses valid env with defaults', () => {
    const env = validateEnv(base);
    expect(env.PORT).toBe(3000);
    expect(env.NODE_ENV).toBe('development');
  });
  it('rejects missing DATABASE_URL', () => {
    const { DATABASE_URL: _omit, ...rest } = base;
    void _omit;
    expect(() => validateEnv(rest)).toThrow(/DATABASE_URL/);
  });
  it('treats REDIS_URL as optional', () => {
    const { REDIS_URL: _r, ...rest } = base;
    void _r;
    expect(validateEnv(rest).REDIS_URL).toBeUndefined();
    expect(validateEnv({ ...rest, REDIS_URL: '' }).REDIS_URL).toBeUndefined();
  });
});
