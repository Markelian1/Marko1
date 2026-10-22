// @polsia:user-owned
import { describe, expect, it } from 'vitest';
import { landingConfig } from '@/lib/business/landing/config';
import { landingConfigSchema } from '@/lib/business/landing/schema';
import type { LandingSection } from '@/lib/business/landing/types';

const media = { src: '/landing/placeholder.svg', alt: 'A supplied image' };
const base = { id: 'example', enabled: true, heading: 'Supplied heading' };
const action = { label: 'Contact us', href: 'mailto:hello@example.com' };
const validSections: LandingSection[] = [
  {
    ...base,
    type: 'logos',
    variant: 'band',
    items: [{ name: 'Supplied partner', image: media.src }],
  },
  {
    ...base,
    type: 'stats',
    variant: 'visual',
    media,
    items: [{ value: '12', label: 'Supplied figure' }],
  },
  {
    ...base,
    type: 'team',
    variant: 'founder',
    people: [{ name: 'Supplied name', role: 'Founder', portrait: media }],
  },
  {
    ...base,
    type: 'contact',
    variant: 'map',
    email: 'hello@example.com',
    map: { ...media, href: 'https://maps.example.com/location' },
  },
  {
    ...base,
    type: 'comparison',
    variant: 'table',
    columns: [{ label: 'Option one' }, { label: 'Option two' }],
    rows: [{ label: 'Criterion', values: ['Included', 'Optional'] }],
  },
  {
    ...base,
    type: 'comparison',
    variant: 'before-after',
    before: { ...media, label: 'Before' },
    after: { ...media, label: 'After' },
  },
  {
    ...base,
    type: 'agenda',
    variant: 'schedule',
    items: [{ title: 'Welcome', time: '09:00', action }],
  },
  {
    ...base,
    type: 'gallery',
    variant: 'menu',
    items: [{ title: 'Supplied dish', price: '€12', category: 'Lunch' }],
  },
  {
    ...base,
    type: 'features',
    variant: 'tabs',
    items: [{ title: 'Benefit', description: 'Explanation', icon: 'layers', media }],
  },
  {
    ...base,
    type: 'testimonial',
    variant: 'wall',
    items: [{ quote: 'Supplied quote', author: 'Supplied customer' }],
  },
];
function accepts(section: unknown) {
  return landingConfigSchema.safeParse({ ...landingConfig, sections: [section] }).success;
}

describe('expanded landing content requirements', () => {
  it.each(validSections)('accepts supplied $type/$variant content', (section) => {
    expect(accepts(section)).toBe(true);
  });

  it('keeps text-only menus valid but requires images for catalog cards', () => {
    const menu = validSections.find((section) => section.type === 'gallery');
    expect(accepts(menu)).toBe(true);
    expect(accepts({ ...menu, variant: 'catalog' })).toBe(false);
    expect(accepts({ ...menu, items: [{ title: 'Item', image: media.src }] })).toBe(false);
  });

  it('requires the content used by visual and interactive layouts', () => {
    for (const [type, field] of [
      ['stats', 'media'],
      ['contact', 'map'],
      ['comparison', 'rows'],
    ] as const) {
      const section = validSections.find((item) => item.type === type);
      expect(accepts({ ...section, [field]: undefined })).toBe(false);
    }
    const tabs = validSections.find((section) => section.type === 'features');
    expect(
      accepts({
        ...tabs,
        items: [{ title: 'Benefit', description: 'Explanation', icon: 'layers' }],
      }),
    ).toBe(false);
    const beforeAfter = validSections.find((section) => section.variant === 'before-after');
    expect(accepts({ ...beforeAfter, after: undefined })).toBe(false);
  });

  it('requires a real photo and additional imagery for the new heroes', () => {
    const hero = landingConfig.sections.find((section) => section.type === 'hero');
    expect(accepts({ ...hero, variant: 'immersive' })).toBe(true);
    expect(
      accepts({ ...hero, variant: 'immersive', media: { kind: 'dashboard', alt: 'Dashboard' } }),
    ).toBe(false);
    expect(accepts({ ...hero, variant: 'collage' })).toBe(false);
    expect(accepts({ ...hero, variant: 'collage', collage: [media] })).toBe(true);
  });

  it('validates comparison cells and retains people when choosing the founder layout', () => {
    const table = validSections.find((section) => section.variant === 'table');
    expect(accepts({ ...table, rows: [{ label: 'Criterion', values: ['Missing cell'] }] })).toBe(
      false,
    );
    const founder = validSections.find((section) => section.type === 'team');
    expect(
      accepts({
        ...founder,
        people: [
          { name: 'One', role: 'Founder' },
          { name: 'Two', role: 'Founder' },
        ],
      }),
    ).toBe(true);
  });

  it('requires attributable quotes and useful contact content', () => {
    const mapOnly = {
      ...base,
      type: 'contact',
      variant: 'map',
      map: { ...media, href: 'https://maps.example.com/location' },
    };
    expect(accepts(mapOnly)).toBe(true);
    expect(accepts({ ...mapOnly, variant: 'details' })).toBe(false);
    expect(
      accepts({
        ...base,
        type: 'testimonial',
        variant: 'wall',
        items: [{ quote: 'Anonymous claim' }],
      }),
    ).toBe(false);
    expect(accepts({ ...base, type: 'testimonial', variant: 'spotlight' })).toBe(false);
    expect(accepts({ ...base, type: 'contact', variant: 'details' })).toBe(false);
    expect(
      accepts({ ...base, type: 'contact', variant: 'details', phone: '+33 (0)1 23 45 67 89' }),
    ).toBe(true);
    expect(accepts({ ...base, type: 'contact', variant: 'details', email: 'invalid' })).toBe(false);
  });

  it('rejects unsafe links and unknown keys on new content', () => {
    expect(
      accepts({
        ...base,
        type: 'logos',
        variant: 'grid',
        items: [{ name: 'Partner', href: 'javascript:alert(1)' }],
      }),
    ).toBe(false);
    expect(
      accepts({
        ...base,
        type: 'contact',
        variant: 'map',
        map: { ...media, href: '//untrusted.example' },
      }),
    ).toBe(false);
    expect(
      accepts({
        ...base,
        type: 'agenda',
        variant: 'curriculum',
        items: [{ title: 'Module', invented: 'ignored?' }],
      }),
    ).toBe(false);
  });
});
