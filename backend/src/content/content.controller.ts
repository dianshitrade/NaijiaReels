import { Controller, Get, Param, Query, UseGuards } from '@nestjs/common';
import { z } from 'zod';
import { AuthUser, CurrentUser, JwtGuard, OptionalAuth } from '../auth/jwt.guard';
import { pageQuery, parse } from '../common/validate';
import { ContentService } from './content.service';

const listQuery = pageQuery.extend({ tag: z.string().max(64).optional() });

@Controller()
@UseGuards(JwtGuard)
@OptionalAuth()
export class ContentController {
  constructor(private readonly content: ContentService) {}

  @Get('home')
  home() {
    return this.content.home();
  }

  @Get('dramas')
  list(@Query() q: unknown) {
    const { tag, page, size } = parse(listQuery, q);
    return this.content.list(tag, page, size);
  }

  @Get('dramas/:id')
  detail(@Param('id') id: string, @CurrentUser() user?: AuthUser) {
    return this.content.detail(id, user?.userId);
  }
}
