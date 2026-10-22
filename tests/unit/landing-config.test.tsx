// @polsia:user-owned
import { act } from 'react';
import { createRoot } from 'react-dom/client';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it, vi } from 'vitest';
import HomePage from '@/app/(setup)/page';
import { LandingPage } from '@/components/custom/landing/landing-page';
import { landingConfig } from '@/lib/business/landing/config';
import { landingConfigSchema } from '@/lib/business/landing/schema';

// Next's PostCSS plugin format is not consumed by Vitest. Check CSS in the browser.
vi.mock('@/components/custom/landing/campaign-sections.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/editorial-showcase.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/personal-sections.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/commerce-sections.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/landing-page.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/visual-variants.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/trust-sections.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/practical-sections.module.css', () => ({ default: {} }));

function renderLanding(config = landingConfig) {
  const container = document.createElement('div');
  container.innerHTML = renderToStaticMarkup(<LandingPage config={config} />);
  return container;
}

describe('landing configuration contract', () => {
  it('accepts the default composition and preserves its content', () => {
    expect(landingConfigSchema.parse(landingConfig)).toEqual(landingConfig);
  });

  it.each(['javascript:alert(1)', '//untrusted.example', '/\\untrusted.example'])(
    'rejects unsafe action destination %s',
    (href) => {
      const config = structuredClone(landingConfig);
      config.primaryAction.href = href;
      expect(landingConfigSchema.safeParse(config).success).toBe(false);
    },
  );

  it('rejects unknown variants and duplicate section anchors', () => {
    const config = structuredClone(landingConfig);
    expect(
      landingConfigSchema.safeParse({
        ...config,
        sections: config.sections.map((s, i) => (i === 0 ? { ...s, variant: 'invented' } : s)),
      }).success,
    ).toBe(false);
    const [first, second] = config.sections;
    if (!first || !second) throw new Error('The landing needs at least two sections.');
    second.id = first.id;
    expect(landingConfigSchema.safeParse(config).success).toBe(false);
  });
});

describe('configured home page', () => {
  it('renders the landing immediately without composition controls', () => {
    const container = document.createElement('div');
    container.innerHTML = renderToStaticMarkup(<HomePage />);
    expect(container.querySelectorAll(`main [data-landing="${landingConfig.id}"]`)).toHaveLength(1);
    // Exactly one h1 with real text. What it says is the business's copy, never pinned here.
    expect(container.querySelectorAll('h1')).toHaveLength(1);
    expect(container.querySelector('h1')?.textContent?.trim()).not.toBe('');
    expect(container.querySelector('aside, select, textarea, [role="dialog"]')).toBeNull();
    // Animation must not hide the landing while JavaScript loads or is disabled.
    const sections = container.querySelectorAll('section');
    expect(sections.length).toBeGreaterThan(0);
    for (const section of sections) {
      expect(section.style.opacity).not.toBe('0');
      expect(section.style.visibility).not.toBe('hidden');
      expect(section.hidden).toBe(false);
    }
  });

  it('gives every default anchor a rendered destination', () => {
    const container = renderLanding();
    for (const link of container.querySelectorAll('a[href^="#"]')) {
      expect(container.querySelector(link.getAttribute('href') ?? '')).not.toBeNull();
    }
  });

  it('applies composition order, variants and visibility without changing the renderer', () => {
    const config = structuredClone(landingConfig);
    config.sections.reverse();
    const hero = config.sections.find((section) => section.type === 'hero');
    if (!hero) throw new Error('The landing needs a hero.');
    hero.variant = 'centered';
    hero.title = 'Your business, your way';
    // Hide a section the navigation links to, so the filtered nav can be checked.
    const hidden = config.sections.find(
      (section) =>
        section.enabled &&
        section.type !== 'hero' &&
        config.navigation.some((item) => item.sectionId === section.id),
    );
    if (!hidden) throw new Error('The landing needs a navigable section besides the hero.');
    hidden.enabled = false;
    const container = renderLanding(config);
    // Rendered order and visibility follow the configuration — whatever its ids are.
    expect([...container.querySelectorAll('section')].map((section) => section.id)).toEqual(
      config.sections.filter((section) => section.enabled).map((section) => section.id),
    );
    expect(container.querySelector(`#${hero.id}`)?.getAttribute('data-section-variant')).toBe(
      'centered',
    );
    expect(container.querySelector('h1')?.textContent).toBe(hero.title);
    expect(container.querySelector(`nav a[href="#${hidden.id}"]`)).toBeNull();
  });

  it('follows the configured action without a demo dialog and closes the mobile menu', async () => {
    vi.stubGlobal('IS_REACT_ACT_ENVIRONMENT', true);
    // jsdom has no viewport. Motion's real scroll behavior is checked in the browser.
    vi.stubGlobal(
      'IntersectionObserver',
      class {
        observe = vi.fn();
        unobserve = vi.fn();
        disconnect = vi.fn();
      },
    );
    const config = structuredClone(landingConfig);
    const target = config.sections.find((section) => section.enabled && section.type !== 'hero');
    if (!target) throw new Error('The landing needs a section besides the hero.');
    config.primaryAction = { label: 'See answers', href: `#${target.id}` };
    const container = document.createElement('div');
    document.body.append(container);
    const root = createRoot(container);
    try {
      await act(async () => root.render(<LandingPage config={config} />));
      const toggle = container.querySelector<HTMLButtonElement>('button[aria-controls]');
      await act(async () => toggle?.click());
      // The action is the menu's last link; a nav link to the same anchor may precede it.
      const link = container.querySelector<HTMLAnchorElement>(
        `nav[aria-label="Mobile navigation"] a[href="#${target.id}"]:last-child`,
      );
      expect(link?.textContent).toBe('See answers');
      const event = new MouseEvent('click', { bubbles: true, cancelable: true, button: 0 });
      await act(async () => link?.dispatchEvent(event));
      expect(event.defaultPrevented).toBe(false);
      expect(toggle?.getAttribute('aria-expanded')).toBe('false');
      expect(container.querySelector('[role="dialog"]')).toBeNull();
    } finally {
      await act(async () => root.unmount());
      container.remove();
      vi.unstubAllGlobals();
    }
  });
});
