// @polsia:user-owned
import { act } from 'react';
import { createRoot } from 'react-dom/client';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it, vi } from 'vitest';
import { LandingPage } from '@/components/custom/landing/landing-page';
import { landingConfig } from '@/lib/business/landing/config';
import { landingConfigSchema } from '@/lib/business/landing/schema';

vi.mock('@/components/custom/landing/landing-page.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/visual-variants.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/trust-sections.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/practical-sections.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/campaign-sections.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/editorial-showcase.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/personal-sections.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/commerce-sections.module.css', () => ({ default: {} }));

// Accessible name of a link: its aria-label, else its text plus image alt text,
// ignoring aria-hidden decoration such as the monogram.
function accessibleName(link: Element | null): string {
  if (!link) return '';
  const label = link.getAttribute('aria-label');
  if (label) return label.trim();
  const clone = link.cloneNode(true) as Element;
  for (const hidden of clone.querySelectorAll('[aria-hidden="true"]')) hidden.remove();
  const alt = [...clone.querySelectorAll('img')].map((img) => img.getAttribute('alt') ?? '');
  return [clone.textContent ?? '', ...alt].join(' ').trim();
}

describe('landing navbar configuration', () => {
  it('keeps older compositions usable without adding a navbar field', () => {
    const legacy = structuredClone(landingConfig);
    Reflect.deleteProperty(legacy, 'navbar');
    expect(landingConfigSchema.parse(legacy)).toEqual(legacy);
    const container = document.createElement('div');
    container.innerHTML = renderToStaticMarkup(<LandingPage config={legacy} />);
    expect(container.querySelector('header')?.dataset.navbarVariant).toBe('classic');
    // The brand is a home link with an accessible name. The visible wordmark is a
    // starter choice, so a logo-only brand (alt text or aria-label) passes too.
    const brandLink = container.querySelector<HTMLAnchorElement>('header a');
    const href = brandLink?.getAttribute('href') ?? '';
    expect(href === '/' || container.querySelector(href)).toBeTruthy();
    expect(accessibleName(brandLink)).not.toBe('');
  });

  it.each(['classic', 'centered', 'floating', 'minimal'] as const)(
    'composes the %s navbar with valid destinations and the configured action',
    (variant) => {
      const config = landingConfigSchema.parse({
        ...landingConfig,
        navbar: { variant },
        primaryAction: { label: 'Nous écrire', href: 'mailto:hello@example.com' },
      });
      const container = document.createElement('div');
      container.innerHTML = renderToStaticMarkup(<LandingPage config={config} />);
      expect(container.querySelector('header')?.dataset.navbarVariant).toBe(variant);
      for (const link of container.querySelectorAll('header a[href^="#"]')) {
        expect(container.querySelector(link.getAttribute('href') ?? '')).not.toBeNull();
      }
      expect(
        container.querySelector('header a[href="mailto:hello@example.com"]')?.textContent,
      ).toBe('Nous écrire');
    },
  );

  it('rejects unsupported navbar layouts and empty accessibility labels', () => {
    for (const navbar of [
      { variant: 'invented' },
      { variant: 'classic', labels: { openMenu: '' } },
    ]) {
      expect(landingConfigSchema.safeParse({ ...landingConfig, navbar }).success).toBe(false);
    }
  });

  it('uses configured language for navigation and menu controls', () => {
    const config = landingConfigSchema.parse({
      ...landingConfig,
      navbar: {
        variant: 'minimal',
        labels: {
          navigation: 'Navigation principale',
          openMenu: 'Ouvrir le menu',
          closeMenu: 'Fermer le menu',
        },
      },
    });
    const container = document.createElement('div');
    container.innerHTML = renderToStaticMarkup(<LandingPage config={config} />);
    expect(container.querySelector('button[aria-label="Ouvrir le menu"]')).not.toBeNull();
    expect(container.querySelector('nav[aria-label="Navigation principale"]')).not.toBeNull();
  });
});

describe('navbar disclosure interactions', () => {
  it('closes on Escape, returns focus to the toggle and dismisses on outside click', async () => {
    vi.stubGlobal('IS_REACT_ACT_ENVIRONMENT', true);
    vi.stubGlobal(
      'IntersectionObserver',
      class {
        observe = vi.fn();
        unobserve = vi.fn();
        disconnect = vi.fn();
      },
    );
    const container = document.createElement('div');
    document.body.append(container);
    const root = createRoot(container);
    try {
      await act(async () => root.render(<LandingPage config={landingConfig} />));
      const toggle = container.querySelector<HTMLButtonElement>('header button[aria-controls]');
      if (!toggle) throw new Error('Missing navbar toggle');
      await act(async () => toggle.click());
      const panel = document.getElementById(toggle.getAttribute('aria-controls') ?? '');
      expect(toggle.getAttribute('aria-expanded')).toBe('true');
      const link = panel?.querySelector('a');
      if (!link) throw new Error('Missing menu link');
      link.focus();
      await act(async () =>
        link.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })),
      );
      expect(toggle.getAttribute('aria-expanded')).toBe('false');
      expect(document.activeElement).toBe(toggle);
      await act(async () => toggle.click());
      await act(async () =>
        document.body.dispatchEvent(new MouseEvent('pointerdown', { bubbles: true })),
      );
      expect(toggle.getAttribute('aria-expanded')).toBe('false');
    } finally {
      await act(async () => root.unmount());
      container.remove();
      vi.unstubAllGlobals();
    }
  });
});
