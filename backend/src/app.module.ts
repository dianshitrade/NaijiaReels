import { Module } from '@nestjs/common';
import { APP_FILTER, APP_GUARD, APP_INTERCEPTOR } from '@nestjs/core';
import { ThrottlerModule } from '@nestjs/throttler';
import { AppExceptionFilter } from './common/app-exception.filter';
import { DeviceThrottlerGuard } from './common/device-throttler.guard';
import { ResponseInterceptor } from './common/response.interceptor';
import { ConfigModule, ENV } from './config/config.module';
import type { Env } from './config/env';
import { HealthController } from './health/health.controller';
import { PrismaModule } from './prisma/prisma.module';

@Module({
  imports: [
    ConfigModule,
    PrismaModule,
    ThrottlerModule.forRootAsync({
      inject: [ENV],
      useFactory: (env: Env) => [{ ttl: env.RATE_LIMIT_TTL * 1000, limit: env.RATE_LIMIT_MAX }],
    }),
  ],
  controllers: [HealthController],
  providers: [
    { provide: APP_GUARD, useClass: DeviceThrottlerGuard },
    { provide: APP_INTERCEPTOR, useClass: ResponseInterceptor },
    { provide: APP_FILTER, useClass: AppExceptionFilter },
  ],
})
export class AppModule {}
