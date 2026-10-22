// @polsia:user-owned
import { act } from 'react';
import { createRoot } from 'react-dom/client';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it, vi } from 'vitest';
import { NarrativeSteps } from '@/components/custom/landing/art-direction-sections';
import { LandingPage } from '@/components/custom/landing/landing-page';
import { landingConfig } from '@/lib/business/landing/config';
import { landingConfigSchema } from '@/lib/business/landing/schema';
import { landingSectionStyle } from '@/lib/business/landing/theme';
import type { Palette, SectionComposition } from '@/lib/business/landing/types';

vi.mock('@/components/custom/landing/campaign-sections.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/editorial-showcase.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/personal-sections.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/commerce-sections.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/landing-page.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/visual-variants.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/trust-sections.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/practical-sections.module.css', () => ({ default: {} }));

const photo = { src: '/actual-hotel.jpg', alt: 'The courtyard in morning light' };
const hero = {
  id: 'welcome',
  enabled: true,
  type: 'hero',
  variant: 'split',
  title: 'A different pace',
  description: 'Stay beside the courtyard.',
  primaryAction: { label: 'See the rooms', href: '#rooms' },
  media: { ...photo, kind: 'image', caption: 'South courtyard' },
};
const narrative = {
  id: 'rooms',
  enabled: true,
  type: 'steps',
  variant: 'narrative',
  heading: 'A day here',
  media: photo,
  items: [
    {
      title: 'Morning',
      description: 'Breakfast in the garden.',
      media: { src: '/garden.jpg', alt: 'The breakfast garden' },
    },
    { title: 'Evening', description: 'Return to the courtyard.' },
  ],
};
function config(sections: unknown[]) {
  return { ...landingConfig, sections };
}
function render(sections: unknown[]) {
  const element = document.createElement('div');
  element.innerHTML = renderToStaticMarkup(
    <LandingPage config={landingConfigSchema.parse(config(sections))} />,
  );
  return element;
}

describe('optional art direction', () => {
  it('keeps small text readable on both the selected tone and its nested card surface', () => {
    // Evaluate the emitted colors independently of the renderer's color helpers.
    const rgb = (css: string): number[] => {
      if (css.startsWith('#')) {
        const hex =
          css.length === 4
            ? [...css.slice(1)].map((digit) => digit.repeat(2)).join('')
            : css.slice(1);
        return [0, 2, 4].map((offset) => Number.parseInt(hex.slice(offset, offset + 2), 16) / 255);
      }
      const mix = /^color-mix\(in srgb, (#[\da-f]+) (\d+)%, (#[\da-f]+)\)$/i.exec(css);
      if (!mix?.[1] || !mix[2] || !mix[3]) throw new Error(`Unsupported test color: ${css}`);
      const amount = Number(mix[2]) / 100;
      const first = rgb(mix[1]);
      return rgb(mix[3]).map(
        (channel, index) => channel * (1 - amount) + (first[index] ?? 0) * amount,
      );
    };
    const light = (css: string) =>
      rgb(css).reduce(
        (sum, channel, index) =>
          sum +
          (channel <= 0.04045 ? channel / 12.92 : ((channel + 0.055) / 1.055) ** 2.4) *
            ([0.2126, 0.7152, 0.0722][index] ?? 0),
        0,
      );
    const palettes: Palette[] = ['cobalt', 'forest', 'wine'];
    const tones: NonNullable<SectionComposition['tone']>[] = ['surface', 'accent', 'inverse'];
    for (const palette of palettes)
      for (const tone of tones) {
        for (const colors of [undefined, { primary: '#767676', accent: '#888', text: '#fff' }]) {
          const style = landingSectionStyle(
            { tone },
            { palette, typography: 'sans', radius: 'soft', colors },
          );
          if (!style) throw new Error('Expected scoped tone colors.');
          for (const text of ['--land-muted', '--land-ink'] as const)
            for (const surface of ['--land-bg', '--land-tint'] as const) {
              const foregroundColor = style[text];
              const backgroundColor = style[surface];
              if (!foregroundColor || !backgroundColor)
                throw new Error('Expected resolved colors.');
              const foreground = light(foregroundColor);
              const background = light(backgroundColor);
              const ratio =
                (Math.max(foreground, background) + 0.05) /
                (Math.min(foreground, background) + 0.05);
              expect(ratio, `${palette}/${tone} ${text} on ${surface}`).toBeGreaterThanOrEqual(4.5);
            }
        }
      }
  });
  it('follows the visible narrative chapter and restores its fallback without hiding chapter copy', async () => {
    let enter: ((target: Element) => void) | undefined;
    vi.stubGlobal('IS_REACT_ACT_ENVIRONMENT', true);
    vi.stubGlobal(
      'IntersectionObserver',
      class {
        constructor(callback: (entries: { target: Element; isIntersecting: boolean }[]) => void) {
          enter = (target) => callback([{ target, isIntersecting: true }]);
        }
        observe() {}
        disconnect() {}
      },
    );
    const section = landingConfigSchema.parse(config([narrative])).sections[0];
    if (!section || section.type !== 'steps') throw new Error('Expected narrative steps.');
    const container = document.createElement('div');
    document.body.append(container);
    const root = createRoot(container);
    try {
      await act(async () => root.render(<NarrativeSteps section={section} />));
      expect(container.querySelector('[data-enhanced="true"]')).not.toBeNull();
      expect(container.querySelector('figure img')?.getAttribute('src')).toBe('/garden.jpg');
      const second = container.querySelector('li:nth-child(2)');
      if (!second || !enter) throw new Error('Expected observable chapters.');
      await act(async () => enter?.(second));
      expect(container.querySelector('figure img')?.getAttribute('src')).toBe('/actual-hotel.jpg');
      expect(container.querySelectorAll('ol h3')).toHaveLength(2);
      expect(container.textContent).toContain('Breakfast in the garden.');
      expect(container.textContent).toContain('Return to the courtyard.');
    } finally {
      await act(async () => root.unmount());
      container.remove();
      vi.unstubAllGlobals();
    }
  });
  it('does not preload the desktop hero source when native picture selects a mobile asset', () => {
    const element = render([
      { ...hero, media: { ...hero.media, framing: { mobile: { src: '/courtyard-mobile.jpg' } } } },
    ]);
    expect(element.querySelector('link[rel="preload"][href="/actual-hotel.jpg"]')).toBeNull();
    expect(element.querySelector('#welcome img')?.getAttribute('loading')).toBe('eager');
  });
  it('leaves legacy compositions without new attributes, wrappers or section styles', () => {
    const element = render(landingConfig.sections);
    expect(
      element.querySelector('[data-composition-width], [data-composition-tone], picture'),
    ).toBeNull();
    for (const section of element.querySelectorAll('[data-section-id]'))
      expect(section.getAttribute('style')).toBeNull();
    expect(landingConfigSchema.parse(landingConfig)).toEqual(landingConfig);
  });
  it('accepts bounded composition and exposes it only on the selected section', () => {
    const element = render([
      {
        ...hero,
        composition: { width: 'full', spacing: 'generous', tone: 'inverse', display: 'monumental' },
      },
      narrative,
    ]);
    const section = element.querySelector('#welcome');
    expect(section?.getAttribute('data-composition-width')).toBe('full');
    expect(section?.getAttribute('data-composition-spacing')).toBe('generous');
    expect(section?.getAttribute('data-composition-display')).toBe('monumental');
    expect(section?.getAttribute('style')).toContain('--land-bg:');
    expect(element.querySelector('#rooms')?.hasAttribute('data-composition-width')).toBe(false);
  });
  it.each([
    { width: 'infinite' },
    { spacing: '42px' },
    { tone: 'red' },
    { display: 4 },
    { css: 'position:fixed' },
  ])('rejects unbounded composition %j', (composition) => {
    expect(
      landingConfigSchema.safeParse(config([{ ...hero, variant: 'split', composition }])).success,
    ).toBe(false);
  });
  it('renders the existing split hero with supplied photo/caption and real actions without JavaScript', () => {
    const element = render([hero, narrative]);
    expect(element.querySelectorAll('#welcome h1')).toHaveLength(1);
    expect(element.querySelector('#welcome h1')?.textContent).toBe('A different pace');
    expect(element.querySelector('#welcome img')?.getAttribute('src')).toBe(photo.src);
    expect(element.querySelector('#welcome figcaption')?.textContent).toBe('South courtyard');
    expect(element.querySelector('#welcome a')?.getAttribute('href')).toBe('#rooms');
  });
  it('keeps every narrative chapter and its image or fallback visible in the server markup', () => {
    const element = render([narrative]);
    expect([...element.querySelectorAll('#rooms ol h3')].map((node) => node.textContent)).toEqual([
      'Morning',
      'Evening',
    ]);
    expect(
      [...element.querySelectorAll('#rooms ol img')].map((node) => node.getAttribute('src')),
    ).toEqual(['/garden.jpg', '/actual-hotel.jpg']);
    expect(element.querySelector('#rooms [data-enhanced="true"]')).toBeNull();
    expect(element.querySelector('#rooms')?.textContent).toContain('Return to the courtyard.');
  });
  it('rejects narrative steps without supplied fallback media', () => {
    expect(
      landingConfigSchema.safeParse(config([{ ...narrative, media: undefined }])).success,
    ).toBe(false);
  });
  it('renders opted-in focal positions and a real mobile source using native picture markup', () => {
    const element = render([
      {
        ...hero,
        media: {
          ...hero.media,
          framing: {
            fit: 'cover',
            position: { x: 70, y: 30 },
            mobile: { src: '/courtyard-mobile.jpg', fit: 'contain', position: { x: 50, y: 40 } },
          },
        },
      },
    ]);
    expect(element.querySelector('#welcome picture source')?.getAttribute('srcset')).toBe(
      '/courtyard-mobile.jpg',
    );
    expect(element.querySelector('#welcome img')?.getAttribute('style')).toContain(
      '--land-media-position:70% 30%',
    );
    expect(element.querySelector('#welcome img')?.getAttribute('style')).toContain(
      '--land-media-mobile-fit:contain',
    );
    expect(element.querySelector('#welcome img')?.getAttribute('alt')).toBe(photo.alt);
  });
  it.each([
    { position: { x: 101, y: 0 } },
    { mobile: { src: 'javascript:bad' } },
    { mobile: { position: { x: 50, y: -1 } } },
    { fit: 'stretch' },
  ])('rejects unsafe or out-of-range framing %j', (framing) => {
    expect(
      landingConfigSchema.safeParse(config([{ ...hero, media: { ...hero.media, framing } }]))
        .success,
    ).toBe(false);
  });
  it('allows complete real product captures but rejects decorative cropping of them', () => {
    const capture = {
      ...hero,
      variant: 'centered',
      media: {
        kind: 'dashboard',
        ...photo,
        framing: { fit: 'contain', mobile: { src: '/actual-mobile-app.jpg', fit: 'contain' } },
      },
    };
    expect(landingConfigSchema.safeParse(config([capture])).success).toBe(true);
    for (const framing of [
      { fit: 'cover' },
      { position: { x: 0, y: 0 } },
      { mobile: { fit: 'cover' } },
      { mobile: { position: { x: 50, y: 50 } } },
    ]) {
      expect(
        landingConfigSchema.safeParse(
          config([{ ...capture, media: { ...capture.media, framing } }]),
        ).success,
      ).toBe(false);
    }
  });
});
