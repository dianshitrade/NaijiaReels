import { HttpStatus } from '@nestjs/common';
import { z } from 'zod';
import { AppException, ErrorCodes } from './app.exception';

export function parse<T extends z.ZodTypeAny>(schema: T, input: unknown): z.infer<T> {
  const r = schema.safeParse(input);
  if (!r.success) {
    const msg = r.error.issues.map((i) => `${i.path.join('.') || 'body'}: ${i.message}`).join('; ');
    throw new AppException(HttpStatus.BAD_REQUEST, ErrorCodes.VALIDATION, msg);
  }
  return r.data;
}

export const pageQuery = z.object({
  page: z.coerce.number().int().min(1).default(1),
  size: z.coerce.number().int().min(1).max(100).default(20),
});
