export function testEnv(): void {
  process.env = {
    DATABASE_URL: 'postgresql://naija:naija@localhost:5432/naija?schema=public',
    REDIS_URL: 'redis://localhost:6379',
    JWT_SECRET: '0123456789abcdef-test',
    MEDIA_BASE_URL: 'http://localhost:8080/media',
    MEDIA_SIGN_SECRET: 'secret123',
    ...process.env,
  };
}
