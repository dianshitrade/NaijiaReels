import { newestFirst } from './content.service';

describe('newestFirst', () => {
  it('orders by createdAt desc without mutating input', () => {
    const rows = [
      { id: 'a', createdAt: new Date('2026-10-01T00:00:00Z') },
      { id: 'c', createdAt: new Date('2026-10-03T00:00:00Z') },
      { id: 'b', createdAt: new Date('2026-10-02T00:00:00Z') },
    ];
    expect(newestFirst(rows).map((r) => r.id)).toEqual(['c', 'b', 'a']);
    expect(rows.map((r) => r.id)).toEqual(['a', 'c', 'b']);
  });
});
