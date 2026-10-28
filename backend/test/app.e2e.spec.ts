import { Controller, Get, HttpStatus, INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { AppException } from '../src/common/app.exception';

@Controller('boom')
class BoomController {
  @Get()
  boom(): never {
    throw new AppException(HttpStatus.FORBIDDEN, 40301, 'Episode locked', { priceCoins: 30 });
  }
}

describe('App (e2e)', () => {
  let app: INestApplication;

  beforeAll(async () => {
    Object.assign(process.env, {
      DATABASE_URL: 'postgresql://u:p@localhost:5432/db',
      REDIS_URL: 'redis://localhost:6379',
      JWT_SECRET: '0123456789abcdef',
      MEDIA_BASE_URL: 'http://localhost:8080/media',
      MEDIA_SIGN_SECRET: 'secret123',
    });
    const mod = await Test.createTestingModule({ imports: [AppModule], controllers: [BoomController] }).compile();
    app = mod.createNestApplication();
    app.setGlobalPrefix('api/v1');
    await app.init();
  });

  afterAll(async () => {
    await app.close();
  });

  it('GET /api/v1/health -> 200 envelope', async () => {
    const res = await request(app.getHttpServer()).get('/api/v1/health').expect(200);
    expect(res.body.code).toBe(0);
    expect(res.body.data.status).toBe('ok');
  });

  it('AppException -> real HTTP status + business code', async () => {
    const res = await request(app.getHttpServer()).get('/api/v1/boom').expect(403);
    expect(res.body).toEqual({ code: 40301, message: 'Episode locked', data: { priceCoins: 30 } });
  });

  it('unknown route -> 404 envelope', async () => {
    const res = await request(app.getHttpServer()).get('/api/v1/nope').expect(404);
    expect(res.body.code).toBe(40401);
  });
});
