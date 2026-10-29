import { Body, Controller, HttpCode, HttpStatus, Ip, Post, UseGuards } from '@nestjs/common';
import { z } from 'zod';
import { AppException, ErrorCodes } from '../common/app.exception';
import { parse } from '../common/validate';
import { AuthService } from './auth.service';
import { JwtGuard } from './jwt.guard';

const guestBody = z.object({
  deviceId: z.string().min(4).max(128),
  platform: z.enum(['android', 'ios', 'web']).optional(),
  appVersion: z.string().max(32).optional(),
});
const refreshBody = z.object({ refreshToken: z.string().min(1) });

@Controller('auth')
export class AuthController {
  constructor(private readonly auth: AuthService) {}

  @Post('guest')
  @HttpCode(200)
  guest(@Body() body: unknown, @Ip() ip: string) {
    return this.auth.guest(parse(guestBody, body), ip);
  }

  @Post('refresh')
  @HttpCode(200)
  refresh(@Body() body: unknown) {
    return this.auth.refresh(parse(refreshBody, body).refreshToken);
  }

  @Post('bind')
  @HttpCode(200)
  @UseGuards(JwtGuard)
  bind(): never {
    throw new AppException(HttpStatus.NOT_IMPLEMENTED, ErrorCodes.NOT_IMPLEMENTED, 'Not implemented yet');
  }
}
