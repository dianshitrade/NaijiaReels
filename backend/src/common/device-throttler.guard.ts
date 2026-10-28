import { Injectable } from '@nestjs/common';
import { ThrottlerGuard } from '@nestjs/throttler';

/** Rate limit keyed by device id (x-device-id header) + client IP. */
@Injectable()
export class DeviceThrottlerGuard extends ThrottlerGuard {
  protected async getTracker(req: Record<string, unknown>): Promise<string> {
    const headers = (req.headers ?? {}) as Record<string, string | undefined>;
    const device = headers['x-device-id'] ?? 'anon';
    const ip = (req.ip as string | undefined) ?? 'unknown';
    return `${device}:${ip}`;
  }
}
