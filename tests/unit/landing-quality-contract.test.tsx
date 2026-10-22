// @polsia:user-owned
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it, vi } from 'vitest';
import { LandingPage } from '@/components/custom/landing/landing-page';
import { landingConfig } from '@/lib/business/landing/config';
import { landingConfigSchema } from '@/lib/business/landing/schema';
import type { HeroSection } from '@/lib/business/landing/types';

vi.mock('@/components/custom/landing/campaign-sections.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/editorial-showcase.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/personal-sections.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/commerce-sections.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/landing-page.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/visual-variants.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/trust-sections.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/practical-sections.module.css', () => ({ default: {} }));

const hero: HeroSection = {
  id: 'intro',
  enabled: true,
  type: 'hero',
  variant: 'centered',
  title: 'A real product',
  description: 'Only what the product does.',
  primaryAction: { label: 'Contact', href: '#landing-footer' },
  media: { kind: 'dashboard', alt: 'Product workspace' },
};
const photo = { src: '/supplied-product.jpg', alt: 'The supplied product' };
const commerce = {
  id: 'shop',
  enabled: true,
  type: 'commerce',
  variant: 'grid',
  heading: 'Collection',
  items: [
    {
      id: 'linen-shirt',
      title: 'Linen shirt',
      image: photo,
      price: '€90',
      details: [{ label: 'Material', value: 'Linen' }],
      action: { label: 'View product', href: '/store/linen-shirt' },
    },
  ],
};
const accepts = (section: unknown) =>
  landingConfigSchema.safeParse({ ...landingConfig, sections: [section] }).success;

describe('truthful product imagery', () => {
  it('rejects a dashboard without a supplied capture, and accepts a capture', () => {
    expect(accepts(hero)).toBe(false);
    expect(accepts({ ...hero, media: { ...hero.media, src: '/actual-product.png' } })).toBe(true);
  });

  it('never renders the invented workspace even for an old unvalidated configuration', () => {
    const markup = renderToStaticMarkup(
      <LandingPage config={{ ...landingConfig, sections: [hero] }} />,
    );
    expect(markup).not.toContain('Website launch');
    expect(markup).not.toContain('Jamie Lee');
    expect(markup).not.toContain('All changes saved');
    expect(markup).not.toContain('Search anything');
  });

  it('renders a supplied dashboard capture instead of a mock product', () => {
    const container = document.createElement('div');
    container.innerHTML = renderToStaticMarkup(
      <LandingPage
        config={{
          ...landingConfig,
          sections: [
            {
              ...hero,
              media: {
                ...hero.media,
                kind: 'dashboard',
                alt: 'Actual workspace',
                src: '/actual-product.png',
              },
            },
          ],
        }}
      />,
    );
    expect(container.querySelector('img')?.getAttribute('src')).toBe('/actual-product.png');
    expect(container.querySelector('img')?.getAttribute('alt')).toBe('Actual workspace');
  });

  it('supports an honest text-only hero while preserving image-led requirements', () => {
    expect(accepts({ ...hero, media: undefined })).toBe(true);
    for (const variant of ['split', 'cover', 'immersive', 'collage']) {
      expect(accepts({ ...hero, variant, media: undefined })).toBe(false);
    }
  });
});

describe('personal and commerce composition requirements', () => {
  it('composes personal and commerce sections through the shared landing renderer', () => {
    const config = landingConfigSchema.parse({
      ...landingConfig,
      sections: [
        { ...hero, variant: 'profile', title: 'Alex Chen', media: undefined },
        {
          id: 'work',
          enabled: true,
          type: 'gallery',
          variant: 'portfolio',
          heading: 'Selected work',
          items: [{ title: 'Community archive', subtitle: 'Research and design' }],
        },
        commerce,
      ],
    });
    const container = document.createElement('div');
    container.innerHTML = renderToStaticMarkup(<LandingPage config={config} />);
    expect(container.querySelector('#intro h1')?.textContent).toBe('Alex Chen');
    expect(container.querySelector('#intro img')).toBeNull();
    expect(container.querySelector('#work h3')?.textContent).toBe('Community archive');
    expect(container.querySelector('#work img')).toBeNull();
    expect(container.querySelector('#shop summary')?.textContent).toContain('Linen shirt');
    expect(container.querySelector('#shop dd')?.textContent).toBe('Linen');
    expect(container.querySelector('#shop a')?.getAttribute('href')).toBe('/store/linen-shirt');
  });

  it('allows a personal introduction without a portrait and rejects fake dashboard portraits', () => {
    expect(accepts({ ...hero, variant: 'profile', media: undefined })).toBe(true);
    expect(accepts({ ...hero, variant: 'profile', media: { kind: 'image', ...photo } })).toBe(true);
    expect(accepts({ ...hero, variant: 'profile', media: { kind: 'dashboard', ...photo } })).toBe(
      false,
    );
  });

  it('allows text-only portfolio projects but validates supplied image alt text', () => {
    const portfolio = {
      id: 'work',
      enabled: true,
      type: 'gallery',
      variant: 'portfolio',
      heading: 'Selected work',
      items: [{ title: 'A real project', subtitle: 'What I contributed' }],
    };
    expect(accepts(portfolio)).toBe(true);
    expect(accepts({ ...portfolio, items: [{ title: 'Project', image: photo.src }] })).toBe(false);
    expect(accepts({ ...portfolio, items: [{ title: 'Project', alt: photo.alt }] })).toBe(false);
    expect(
      accepts({ ...portfolio, items: [{ title: 'Project', image: photo.src, alt: photo.alt }] }),
    ).toBe(true);
  });

  it.each(['grid', 'featured'])('accepts a supplied %s commerce collection', (variant) => {
    expect(accepts({ ...commerce, variant })).toBe(true);
  });

  it('requires real product imagery, unique product ids and safe action destinations', () => {
    const item = commerce.items[0];
    expect(accepts({ ...commerce, items: [{ ...item, image: undefined }] })).toBe(false);
    expect(accepts({ ...commerce, items: [item, item] })).toBe(false);
    expect(
      accepts({
        ...commerce,
        items: [{ ...item, action: { label: 'Buy', href: 'javascript:alert(1)' } }],
      }),
    ).toBe(false);
  });
});

describe('expanded layout schema and renderer integration', () => {
  function renderSection(section: unknown) {
    const config = landingConfigSchema.parse({ ...landingConfig, sections: [section] });
    const container = document.createElement('div');
    container.innerHTML = renderToStaticMarkup(<LandingPage config={config} />);
    return container.querySelector('section[data-section-id]');
  }

  it('renders a validated campaign image before its headline with its caption and actions', () => {
    const section = renderSection({
      ...hero,
      variant: 'campaign',
      media: { kind: 'image', ...photo, caption: 'The supplied collection photograph' },
      note: 'Made for everyday use.',
      secondaryAction: { label: 'Read more', href: '/about' },
    });
    const image = section?.querySelector('img');
    const heading = section?.querySelector('h1');
    expect(image?.getAttribute('src')).toBe(photo.src);
    expect(image?.getAttribute('alt')).toBe(photo.alt);
    expect(image?.getAttribute('loading')).toBe('eager');
    expect(image && heading && image.compareDocumentPosition(heading)).toBe(
      Node.DOCUMENT_POSITION_FOLLOWING,
    );
    expect(section?.querySelector('figcaption')?.textContent).toBe(
      'The supplied collection photograph',
    );
    expect(section?.textContent).toContain('Made for everyday use.');
    expect(section?.querySelector('a[href="/about"]')?.textContent).toContain('Read more');
  });

  it('requires supplied campaign media and descriptive alt text, including real captures', () => {
    expect(accepts({ ...hero, variant: 'campaign', media: undefined })).toBe(false);
    expect(accepts({ ...hero, variant: 'campaign' })).toBe(false);
    expect(
      accepts({ ...hero, variant: 'campaign', media: { kind: 'image', src: photo.src } }),
    ).toBe(false);
    expect(accepts({ ...hero, variant: 'campaign', media: { kind: 'dashboard', ...photo } })).toBe(
      true,
    );
  });

  it.each(['compact', 'rail', 'lookbook'])(
    'validates and renders supplied %s merchandise with details and real actions',
    (variant) => {
      const section = renderSection({
        ...commerce,
        variant,
        scrollLabel: 'Explore more pieces',
        items: [commerce.items[0], { ...commerce.items[0], id: 'second-shirt' }],
      });
      expect(section?.querySelectorAll('article')).toHaveLength(2);
      expect(section?.querySelectorAll('details')).toHaveLength(2);
      expect(section?.querySelector('dd')?.textContent).toBe('Linen');
      expect(section?.querySelector('a')?.getAttribute('href')).toBe('/store/linen-shirt');
      expect(section?.querySelector('img')?.getAttribute('alt')).toBe(photo.alt);
      if (variant === 'rail') {
        const rail = section?.querySelector('section[aria-label="Collection"]');
        expect(rail?.getAttribute('tabindex')).toBe('0');
        expect(rail?.getAttribute('aria-describedby')).toBeTruthy();
        expect(section?.textContent).toContain('Explore more pieces');
      }
      expect(
        accepts({ ...commerce, variant, items: [{ ...commerce.items[0], image: undefined }] }),
      ).toBe(false);
    },
  );

  it.each(['mosaic', 'story'])(
    'validates and renders %s imagery with item metadata and working destinations',
    (variant) => {
      const gallery = {
        id: 'collection-story',
        enabled: true,
        type: 'gallery',
        variant,
        heading: 'A closer look',
        items: [
          {
            title: 'The linen study',
            subtitle: 'Material and construction.',
            image: photo.src,
            alt: photo.alt,
            category: 'Journal',
            tag: 'Summer',
            price: '€90',
            action: { label: 'Read the story', href: '/journal/linen' },
          },
        ],
      };
      const section = renderSection(gallery);
      expect(section?.querySelector('figure img')?.getAttribute('alt')).toBe(photo.alt);
      expect(section?.querySelector('h3')?.textContent).toBe('The linen study');
      for (const text of ['Material and construction.', 'Journal', 'Summer', '€90'])
        expect(section?.textContent).toContain(text);
      expect(section?.querySelector('a')?.getAttribute('href')).toBe('/journal/linen');
      expect(accepts({ ...gallery, items: [{ ...gallery.items[0], image: undefined }] })).toBe(
        false,
      );
      expect(accepts({ ...gallery, items: [{ ...gallery.items[0], alt: undefined }] })).toBe(false);
    },
  );

  it('validates a minimal invitation and renders both action destinations', () => {
    const cta = {
      id: 'invitation',
      enabled: true,
      type: 'cta',
      variant: 'minimal',
      heading: 'Find your next favourite.',
      description: 'Explore the collection in detail.',
      action: { label: 'View the collection', href: '/collection' },
      secondaryAction: { label: 'Contact the studio', href: 'mailto:studio@example.com' },
    };
    const section = renderSection(cta);
    expect(section?.querySelector('h2')?.textContent).toBe(cta.heading);
    expect(section?.querySelector('p')?.textContent).toBe(cta.description);
    expect(
      [...(section?.querySelectorAll('a') ?? [])].map((link) => link.getAttribute('href')),
    ).toEqual(['/collection', 'mailto:studio@example.com']);
    expect(accepts({ ...cta, action: { label: 'Continue', href: 'javascript:alert(1)' } })).toBe(
      false,
    );
  });
});
