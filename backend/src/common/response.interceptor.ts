import { CallHandler, ExecutionContext, Injectable, NestInterceptor } from '@nestjs/common';
import { Observable, map } from 'rxjs';
import { ApiResponse, ok } from './response';

@Injectable()
export class ResponseInterceptor<T> implements NestInterceptor<T, ApiResponse<T>> {
  intercept(_ctx: ExecutionContext, next: CallHandler<T>): Observable<ApiResponse<T>> {
    return next.handle().pipe(map((data) => ok(data === undefined ? (null as T) : data)));
  }
}
