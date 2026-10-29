import { ArgumentsHost, Catch, ExceptionFilter, HttpException, HttpStatus, Logger } from '@nestjs/common';
import { ThrottlerException } from '@nestjs/throttler';
import type { Response } from 'express';
import { AppException, ErrorCodes } from './app.exception';

@Catch()
export class AppExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger(AppExceptionFilter.name);

  catch(exception: unknown, host: ArgumentsHost): void {
    const res = host.switchToHttp().getResponse<Response>();
    let status = HttpStatus.INTERNAL_SERVER_ERROR;
    let code: number = ErrorCodes.INTERNAL;
    let message = 'Internal server error';
    let data: unknown = null;

    if (exception instanceof AppException) {
      ({ status, code, data } = exception);
      message = exception.message;
    } else if (exception instanceof ThrottlerException) {
      status = HttpStatus.TOO_MANY_REQUESTS;
      code = ErrorCodes.TOO_MANY_REQUESTS;
      message = 'Too many requests';
    } else if (exception instanceof HttpException) {
      status = exception.getStatus();
      code = status * 100 + 1;
      message = exception.message;
    } else {
      this.logger.error(exception);
    }
    res.status(status).json({ code, message, data });
  }
}
