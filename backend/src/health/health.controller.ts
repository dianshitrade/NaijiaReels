import { Controller, Get } from '@nestjs/common';
import { SkipThrottle } from '@nestjs/throttler';

@Controller('health')
export class HealthController {
  @SkipThrottle()
  @Get()
  health(): { status: string; time: string } {
    return { status: 'ok', time: new Date().toISOString() };
  }
}
