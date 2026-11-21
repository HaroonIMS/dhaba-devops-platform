import { describe, expect, it } from 'vitest';
import { cartToItems, cartTotal, formatPrice, groupByStatus } from './lib.js';

const menu = [
  { id: 1, name: 'Biryani', price: 450 },
  { id: 2, name: 'Garlic Naan', price: 100 },
];

describe('cart helpers', () => {
  it('drops dishes with quantity 0', () => {
    expect(cartToItems({ Biryani: 2, 'Garlic Naan': 0 })).toEqual([
      { name: 'Biryani', qty: 2 },
    ]);
  });

  it('adds up the total', () => {
    expect(cartTotal({ Biryani: 2, 'Garlic Naan': 1 }, menu)).toBe(1000);
  });

  it('formats prices in Pakistani rupees', () => {
    expect(formatPrice(1250)).toBe('Rs. 1,250');
    expect(formatPrice(450)).toBe('Rs. 450');
  });
});

describe('groupByStatus', () => {
  it('puts each order in its column', () => {
    const groups = groupByStatus([
      { id: 1, status: 'new' },
      { id: 2, status: 'cooking' },
      { id: 3, status: 'ready' },
      { id: 4, status: 'ready' },
    ]);
    expect(groups.new).toHaveLength(1);
    expect(groups.cooking).toHaveLength(1);
    expect(groups.ready.map((o) => o.id)).toEqual([3, 4]);
  });
});
