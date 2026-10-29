/**
 * D2 e2e: needs a migrated + seeded Postgres at DATABASE_URL (CI: postgres service, `prisma migrate deploy && npm run seed`).
 */
import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { testEnv } from './helpers';

testEnv();
// eslint-disable-next-line @typescript-eslint/no-var-requires
const { AppModule } = require('../src/app.module');
// eslint-disable-next-line @typescript-eslint/no-var-requires
const { PrismaService } = require('../src/prisma/prisma.service');

describe('D2 auth/content/play/wallet (e2e)', () => {
  let app: INestApplication;
  let http: ReturnType<INestApplication['getHttpServer']>;
  const deviceId = `e2e-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
  let access = '';
  let refresh = '';

  beforeAll(async () => {
    const mod = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = mod.createNestApplication();
    app.setGlobalPrefix('api/v1');
    await app.init();
    http = app.getHttpServer();
  });
  afterAll(async () => {
    await app.close();
  });

  const auth = () => ({ Authorization: `Bearer ${access}` });

  it('POST /auth/guest validates body', async () => {
    const r = await request(http).post('/api/v1/auth/guest').send({}).expect(400);
    expect(r.body.code).toBe(40001);
  });

  it('POST /auth/guest issues tokens and is stable per device', async () => {
    const r = await request(http).post('/api/v1/auth/guest').send({ deviceId, platform: 'android' }).expect(200);
    expect(r.body.code).toBe(0);
    access = r.body.data.accessToken;
    refresh = r.body.data.refreshToken;
    const again = await request(http).post('/api/v1/auth/guest').send({ deviceId }).expect(200);
    expect(again.body.data.user.id).toBe(r.body.data.user.id);
  });

  it('POST /auth/refresh rotates tokens; rejects access token as refresh', async () => {
    const r = await request(http).post('/api/v1/auth/refresh').send({ refreshToken: refresh }).expect(200);
    expect(r.body.data.accessToken).toEqual(expect.any(String));
    const bad = await request(http).post('/api/v1/auth/refresh').send({ refreshToken: access }).expect(401);
    expect(bad.body.code).toBe(40102);
  });

  it('GET /wallet requires auth and returns signup bonus', async () => {
    expect((await request(http).get('/api/v1/wallet').expect(401)).body.code).toBe(40101);
    const r = await request(http).get('/api/v1/wallet').set(auth()).expect(200);
    expect(r.body.data.balanceCoins).toBe(100);
  });

  it('GET /home and /dramas list seeded dramas', async () => {
    const home = await request(http).get('/api/v1/home').expect(200);
    expect(home.body.data.sections[0].items.map((d: { title: string }) => d.title)).toContain('Mama-in-Law Wahala');
    const list = await request(http).get('/api/v1/dramas?page=1&size=2').expect(200);
    expect(list.body.data).toMatchObject({ page: 1, size: 2, hasMore: true });
    expect(list.body.data.items).toHaveLength(2);
    const fam = await request(http).get('/api/v1/dramas?tag=family').expect(200);
    expect(fam.body.data.items.map((d: { id: string }) => d.id)).toEqual(['dr_mama']);
  });

  it('GET /dramas/{id} has episodes with locked/free/priceCoins; 404 for unknown', async () => {
    const r = await request(http).get('/api/v1/dramas/dr_mama').set(auth()).expect(200);
    expect(r.body.data.episodes).toHaveLength(6);
    expect(r.body.data.episodes[0]).toMatchObject({ episodeNo: 1, free: true, locked: false, priceCoins: 0 });
    expect(r.body.data.episodes[2]).toMatchObject({ episodeNo: 3, free: false, locked: true, priceCoins: 30 });
    expect((await request(http).get('/api/v1/dramas/nope').expect(404)).body.code).toBe(40401);
  });

  it('play free episode returns signed hlsUrl', async () => {
    const r = await request(http).get('/api/v1/episodes/dr_mama_ep1/play').set(auth()).expect(200);
    expect(r.body.data.hlsUrl).toMatch(/\/media\/mama-in-law-wahala\/ep1\/master\.m3u8\?exp=\d+&sig=/);
  });

  it('play locked episode -> 403/40301 with unlock options', async () => {
    const r = await request(http).get('/api/v1/episodes/dr_mama_ep3/play').set(auth()).expect(403);
    expect(r.body).toEqual({ code: 40301, message: 'Episode locked', data: { priceCoins: 30, vipAvailable: false, adAvailable: false } });
  });

  it('unlock with coins debits wallet, writes ledger, is idempotent, then plays', async () => {
    const r = await request(http).post('/api/v1/episodes/dr_mama_ep3/unlock').set(auth()).send({ method: 'coin' }).expect(200);
    expect(r.body.data).toEqual({ episodeId: 'dr_mama_ep3', method: 'coin', balanceCoins: 70 });
    const again = await request(http).post('/api/v1/episodes/dr_mama_ep3/unlock').set(auth()).send({ method: 'coin' }).expect(200);
    expect(again.body.data.balanceCoins).toBe(70);
    await request(http).get('/api/v1/episodes/dr_mama_ep3/play').set(auth()).expect(200);
    const detail = await request(http).get('/api/v1/dramas/dr_mama').set(auth()).expect(200);
    expect(detail.body.data.episodes[2].locked).toBe(false);

    const prisma = app.get(PrismaService);
    const tokenUser = JSON.parse(Buffer.from(access.split('.')[1], 'base64url').toString()).sub as string;
    const ledger = await prisma.coinLedger.findMany({ where: { userId: tokenUser }, orderBy: { createdAt: 'asc' } });
    expect(ledger.map((l: { deltaCoins: number; balanceAfterCoins: number }) => [l.deltaCoins, l.balanceAfterCoins])).toEqual([
      [100, 100],
      [-30, 70],
    ]);
  });

  it('unlock fails with 402/40201 when coins run out', async () => {
    for (const n of [4, 5]) {
      await request(http).post(`/api/v1/episodes/dr_mama_ep${n}/unlock`).set(auth()).send({ method: 'coin' }).expect(200);
    }
    const r = await request(http).post('/api/v1/episodes/dr_mama_ep6/unlock').set(auth()).send({ method: 'coin' }).expect(402);
    expect(r.body.code).toBe(40201);
    const w = await request(http).get('/api/v1/wallet').set(auth()).expect(200);
    expect(w.body.data.balanceCoins).toBe(10);
    await request(http).get('/api/v1/episodes/dr_mama_ep6/play').set(auth()).expect(403);
  });

  it('unlock validation: ad requires adRewardToken', async () => {
    const r = await request(http).post('/api/v1/episodes/dr_mama_ep6/unlock').set(auth()).send({ method: 'ad' }).expect(400);
    expect(r.body.code).toBe(40002);
  });
});
