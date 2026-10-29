import { Inject, Injectable, Logger, OnModuleDestroy } from '@nestjs/common';
import Redis from 'ioredis';
import { ENV } from '../config/config.module';
import type { Env } from '../config/env';

/** Minimal KV used by the app. Backed by Redis when REDIS_URL is set, otherwise an in-process Map. */
export interface KvStore {
  get(key: string): Promise<string | null>;
  set(key: string, value: string, ttlSec?: number): Promise<void>;
  del(key: string): Promise<void>;
  incr(key: string, ttlSec?: number): Promise<number>;
}

export class MemoryKvStore implements KvStore {
  private readonly data = new Map<string, { v: string; exp?: number }>();
  private live(key: string) {
    const e = this.data.get(key);
    if (e && e.exp !== undefined && e.exp <= Date.now()) {
      this.data.delete(key);
      return undefined;
    }
    return e;
  }
  async get(key: string) {
    return this.live(key)?.v ?? null;
  }
  async set(key: string, value: string, ttlSec?: number) {
    this.data.set(key, { v: value, exp: ttlSec ? Date.now() + ttlSec * 1000 : undefined });
  }
  async del(key: string) {
    this.data.delete(key);
  }
  async incr(key: string, ttlSec?: number) {
    const e = this.live(key);
    const n = (e ? Number(e.v) || 0 : 0) + 1;
    this.data.set(key, { v: String(n), exp: e?.exp ?? (ttlSec ? Date.now() + ttlSec * 1000 : undefined) });
    return n;
  }
}

class RedisKvStore implements KvStore {
  constructor(private readonly c: Redis) {}
  async get(key: string) {
    return this.c.get(key);
  }
  async set(key: string, value: string, ttlSec?: number) {
    if (ttlSec) await this.c.set(key, value, 'EX', ttlSec);
    else await this.c.set(key, value);
  }
  async del(key: string) {
    await this.c.del(key);
  }
  async incr(key: string, ttlSec?: number) {
    const n = await this.c.incr(key);
    if (n === 1 && ttlSec) await this.c.expire(key, ttlSec);
    return n;
  }
}

@Injectable()
export class RedisService implements OnModuleDestroy {
  /** Raw ioredis client; null when REDIS_URL is not configured. */
  readonly client: Redis | null;
  readonly kv: KvStore;
  constructor(@Inject(ENV) env: Env) {
    if (env.REDIS_URL) {
      this.client = new Redis(env.REDIS_URL, { lazyConnect: true, maxRetriesPerRequest: 1 });
      this.kv = new RedisKvStore(this.client);
    } else {
      this.client = null;
      this.kv = new MemoryKvStore();
      new Logger(RedisService.name).warn('REDIS_URL not set; using in-memory KV store');
    }
  }
  async onModuleDestroy(): Promise<void> {
    this.client?.disconnect();
  }
}
