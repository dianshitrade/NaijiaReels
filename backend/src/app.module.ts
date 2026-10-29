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
import { AuthController } from './auth/auth.controller';
import { AuthService } from './auth/auth.service';
import { JwtGuard } from './auth/jwt.guard';
import { TokenService } from './auth/token.service';
import { ContentController } from './content/content.controller';
import { ContentService } from './content/content.service';
import { PlayController } from './play/play.controller';
import { PlayService } from './play/play.service';
import { WalletController } from './wallet/wallet.controller';
import { WalletService } from './wallet/wallet.service';

@Module({
  imports: [
    ConfigModule,
    PrismaModule,
    ThrottlerModule.forRootAsync({
      inject: [ENV],
      useFactory: (env: Env) => [{ ttl: env.RATE_LIMIT_TTL * 1000, limit: env.RATE_LIMIT_MAX }],
    }),
  ],
  controllers: [HealthController, AuthController, ContentController, PlayController, WalletController],
  providers: [
    TokenService,
    JwtGuard,
    AuthService,
    WalletService,
    ContentService,
    PlayService,
    { provide: APP_GUARD, useClass: DeviceThrottlerGuard },
    { provide: APP_INTERCEPTOR, useClass: ResponseInterceptor },
    { provide: APP_FILTER, useClass: AppExceptionFilter },
  ],
})
export class AppModule {}
