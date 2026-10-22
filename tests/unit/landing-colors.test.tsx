// @polsia:user-owned
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it, vi } from 'vitest';
import { LandingPage } from '@/components/custom/landing/landing-page';
import { landingConfig } from '@/lib/business/landing/config';
import { landingConfigSchema } from '@/lib/business/landing/schema';
import { landingPalettes } from '@/lib/business/landing/theme';

vi.mock('@/components/custom/landing/campaign-sections.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/editorial-showcase.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/personal-sections.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/commerce-sections.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/landing-page.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/visual-variants.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/trust-sections.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/practical-sections.module.css', () => ({ default: {} }));

describe('landing custom colors', () => {
  it('accepts partial colors and preserves them through a JSON round trip', () => {
    const config = {
      ...landingConfig,
      theme: { ...landingConfig.theme, colors: { primary: '#f90', background: '#181818' } },
    };
    expect(landingConfigSchema.parse(JSON.parse(JSON.stringify(config)))).toEqual(config);
  });

  it.each([
    'red',
    '#ffff',
    '#ffffffffff',
    'var(--secret)',
    'url(https://example.com)',
    '#fff;display:none',
  ])('rejects unsupported color %s', (primary) => {
    expect(
      landingConfigSchema.safeParse({
        ...landingConfig,
        theme: { ...landingConfig.theme, colors: { primary } },
      }).success,
    ).toBe(false);
  });

  it('rejects misspelled color fields', () => {
    expect(
      landingConfigSchema.safeParse({
        ...landingConfig,
        theme: { ...landingConfig.theme, colors: { primarry: '#ff9900' } },
      }).success,
    ).toBe(false);
  });

  it('renders custom colors in the initial HTML with a readable foreground on bright buttons', () => {
    const config = {
      ...landingConfig,
      theme: {
        ...landingConfig.theme,
        colors: { primary: '#ffee00', accent: '#222222', background: '#111111', text: '#eeeeee' },
      },
    };
    const container = document.createElement('div');
    container.innerHTML = renderToStaticMarkup(<LandingPage config={config} />);
    const page = container.querySelector<HTMLElement>('[data-landing]');
    expect(page?.style.getPropertyValue('--land-accent')).toBe('#ffee00');
    expect(page?.style.getPropertyValue('--land-tint')).toBe('#222222');
    expect(page?.style.getPropertyValue('--land-bg')).toBe('#111111');
    expect(page?.style.getPropertyValue('--land-ink')).toBe('#eeeeee');
    expect(page?.style.getPropertyValue('--land-on-accent')).toBe('#111111');
  });

  it('inherits unspecified colors from the chosen preset and restores it when overrides are removed', () => {
    // Read the preset from theme.ts so editing a palette is a design change, not a test failure.
    const preset = landingPalettes.forest;
    const container = document.createElement('div');
    for (const colors of [{ primary: '#123456' }, undefined]) {
      container.innerHTML = renderToStaticMarkup(
        <LandingPage
          config={{
            ...landingConfig,
            theme: { palette: 'forest', typography: 'sans', radius: 'soft', colors },
          }}
        />,
      );
      const page = container.querySelector<HTMLElement>('[data-landing]');
      expect(page?.style.getPropertyValue('--land-accent')).toBe(colors?.primary ?? preset.primary);
      expect(page?.style.getPropertyValue('--land-bg')).toBe(preset.background);
      expect(page?.style.getPropertyValue('--land-tint')).toBe(preset.accent);
      expect(page?.style.getPropertyValue('--land-ink')).toBe(preset.text);
    }
  });

  it('accepts all four colors without a palette and renders them as the whole theme', () => {
    const colors = {
      primary: '#0a0a0a',
      accent: '#f4f4f4',
      background: '#ffffff',
      text: '#111111',
    };
    const config = {
      ...landingConfig,
      theme: { typography: 'sans' as const, radius: 'soft' as const, colors },
    };
    expect(landingConfigSchema.parse(JSON.parse(JSON.stringify(config)))).toEqual(config);
    const container = document.createElement('div');
    container.innerHTML = renderToStaticMarkup(<LandingPage config={config} />);
    const page = container.querySelector<HTMLElement>('[data-landing]');
    expect(page?.hasAttribute('data-palette')).toBe(false);
    expect(page?.style.getPropertyValue('--land-accent')).toBe(colors.primary);
    expect(page?.style.getPropertyValue('--land-tint')).toBe(colors.accent);
    expect(page?.style.getPropertyValue('--land-bg')).toBe(colors.background);
    expect(page?.style.getPropertyValue('--land-ink')).toBe(colors.text);
    // Muted text and borders derive from the supplied surface, not a preset.
    expect(page?.style.getPropertyValue('--land-muted')).toContain('color-mix(');
  });

  it('requires a palette unless all four colors are set', () => {
    for (const colors of [
      undefined,
      { primary: '#0a0a0a' },
      { primary: '#0a0a0a', accent: '#f4f4f4', background: '#ffffff' },
    ]) {
      expect(
        landingConfigSchema.safeParse({
          ...landingConfig,
          theme: { typography: 'sans', radius: 'soft', colors },
        }).success,
      ).toBe(false);
    }
  });
});
