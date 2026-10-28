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

export const ErrorCodes = {
  VALIDATION: 40001,
  UNAUTHORIZED: 40101,
  EPISODE_LOCKED: 40301,
  NOT_FOUND: 40401,
  TOO_MANY_REQUESTS: 42901,
  INTERNAL: 50001,
} as const;
