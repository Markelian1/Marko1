// @polsia:user-owned
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it, vi } from 'vitest';
import { LandingPage } from '@/components/custom/landing/landing-page';
import { landingConfig } from '@/lib/business/landing/config';
import { landingConfigSchema } from '@/lib/business/landing/schema';
import type { LandingConfig } from '@/lib/business/landing/types';

vi.mock('@/components/custom/landing/campaign-sections.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/editorial-showcase.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/personal-sections.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/commerce-sections.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/landing-page.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/visual-variants.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/trust-sections.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/practical-sections.module.css', () => ({ default: {} }));

function renderPage(config: LandingConfig) {
  const container = document.createElement('div');
  container.innerHTML = renderToStaticMarkup(<LandingPage config={config} />);
  return container.querySelector<HTMLElement>('[data-landing]');
}

describe('landing typography', () => {
  it.each(['sans', 'editorial', 'rounded'] as const)(
    'keeps the %s preset as a data hook without inline font variables',
    (typography) => {
      const config = { ...landingConfig, theme: { ...landingConfig.theme, typography } };
      expect(landingConfigSchema.parse(config)).toEqual(config);
      const page = renderPage(config);
      expect(page?.dataset.typography).toBe(typography);
      expect(page?.style.getPropertyValue('--land-display')).toBe('');
      expect(page?.style.getPropertyValue('--land-body')).toBe('');
    },
  );

  it('renders custom font families through --land-display and --land-body', () => {
    const typography = {
      display: '"Cormorant Garamond", Georgia, serif',
      body: '"Work Sans", ui-sans-serif, sans-serif',
    };
    const config = { ...landingConfig, theme: { ...landingConfig.theme, typography } };
    expect(landingConfigSchema.parse(JSON.parse(JSON.stringify(config)))).toEqual(config);
    const page = renderPage(config);
    expect(page?.dataset.typography).toBe('custom');
    expect(page?.style.getPropertyValue('--land-display')).toBe(typography.display);
    expect(page?.style.getPropertyValue('--land-body')).toBe(typography.body);
  });

  it.each([
    '',
    'Georgia; display: none',
    'url(https://example.com/font.woff2)',
    'var(--secret)',
    '"Fraunces" }',
    '<b>Fraunces</b>',
  ])('rejects the font family %s', (display) => {
    expect(
      landingConfigSchema.safeParse({
        ...landingConfig,
        theme: { ...landingConfig.theme, typography: { display, body: 'Georgia, serif' } },
      }).success,
    ).toBe(false);
  });

  it('rejects partial, misspelled or unknown typography values', () => {
    for (const typography of [
      { display: 'Georgia, serif' },
      { display: 'Georgia, serif', body: 'serif', extra: 'x' },
      { dispaly: 'Georgia, serif', body: 'serif' },
      'fancy',
    ]) {
      expect(
        landingConfigSchema.safeParse({
          ...landingConfig,
          theme: { ...landingConfig.theme, typography },
        }).success,
      ).toBe(false);
    }
  });
});
