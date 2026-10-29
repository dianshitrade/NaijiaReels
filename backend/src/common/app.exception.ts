import { HttpStatus } from '@nestjs/common';

export class AppException extends Error {
  constructor(
    public readonly status: HttpStatus,
    public readonly code: number,
    message: string,
    public readonly data: unknown = null,
  ) {
    super(message);
  }
}

/** Keep in sync with contracts/errors.md */
export const ErrorCodes = {
  VALIDATION: 40001,
  AD_TOKEN_REQUIRED: 40002,
  UNAUTHORIZED: 40101,
  REFRESH_INVALID: 40102,
  INSUFFICIENT_COINS: 40201,
  EPISODE_LOCKED: 40301,
  NOT_FOUND: 40401,
  TOO_MANY_REQUESTS: 42901,
  INTERNAL: 50001,
  NOT_IMPLEMENTED: 50101,
} as const;
