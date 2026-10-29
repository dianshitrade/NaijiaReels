import { CanActivate, ExecutionContext, HttpStatus, Injectable, SetMetadata, createParamDecorator } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import type { Request } from 'express';
import { AppException, ErrorCodes } from '../common/app.exception';
import { TokenService } from './token.service';

export interface AuthUser {
  userId: string;
  deviceId?: string;
}
type AuthedRequest = Request & { user?: AuthUser };

export const OPTIONAL_AUTH = 'optionalAuth';
/** Route works anonymously, but attaches req.user when a valid Bearer token is present. */
export const OptionalAuth = (): MethodDecorator & ClassDecorator => SetMetadata(OPTIONAL_AUTH, true);

export const CurrentUser = createParamDecorator((_d: unknown, ctx: ExecutionContext): AuthUser | undefined => {
  return ctx.switchToHttp().getRequest<AuthedRequest>().user;
});

@Injectable()
export class JwtGuard implements CanActivate {
  constructor(
    private readonly tokens: TokenService,
    private readonly reflector: Reflector,
  ) {}

  canActivate(ctx: ExecutionContext): boolean {
    const req = ctx.switchToHttp().getRequest<AuthedRequest>();
    const optional = this.reflector.getAllAndOverride<boolean>(OPTIONAL_AUTH, [ctx.getHandler(), ctx.getClass()]);
    const header = req.headers.authorization;
    const token = header?.startsWith('Bearer ') ? header.slice(7) : undefined;
    if (!token) {
      if (optional) return true;
      throw new AppException(HttpStatus.UNAUTHORIZED, ErrorCodes.UNAUTHORIZED, 'Unauthorized');
    }
    try {
      const p = this.tokens.verify(token, 'access');
      req.user = { userId: p.sub, deviceId: p.did };
    } catch (e) {
      if (!optional) throw e;
    }
    return true;
  }
}
