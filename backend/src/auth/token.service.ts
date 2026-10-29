import { HttpStatus, Inject, Injectable } from '@nestjs/common';
import jwt from 'jsonwebtoken';
import { AppException, ErrorCodes } from '../common/app.exception';
import { ENV } from '../config/config.module';
import type { Env } from '../config/env';

export interface TokenPayload {
  sub: string;
  did?: string;
  typ: 'access' | 'refresh';
}

@Injectable()
export class TokenService {
  constructor(@Inject(ENV) private readonly env: Env) {}

  issue(userId: string, deviceId?: string): { accessToken: string; refreshToken: string; expiresIn: number } {
    const base = { sub: userId, did: deviceId };
    const accessToken = jwt.sign({ ...base, typ: 'access' }, this.env.JWT_SECRET, { expiresIn: this.env.JWT_ACCESS_TTL });
    const refreshToken = jwt.sign({ ...base, typ: 'refresh' }, this.env.JWT_SECRET, { expiresIn: this.env.JWT_REFRESH_TTL });
    return { accessToken, refreshToken, expiresIn: this.env.JWT_ACCESS_TTL };
  }

  verify(token: string, typ: TokenPayload['typ']): TokenPayload {
    try {
      const p = jwt.verify(token, this.env.JWT_SECRET) as TokenPayload;
      if (p.typ !== typ || typeof p.sub !== 'string') throw new Error('bad typ');
      return p;
    } catch {
      throw typ === 'refresh'
        ? new AppException(HttpStatus.UNAUTHORIZED, ErrorCodes.REFRESH_INVALID, 'Refresh token invalid')
        : new AppException(HttpStatus.UNAUTHORIZED, ErrorCodes.UNAUTHORIZED, 'Unauthorized');
    }
  }
}
