// @polsia:user-owned
import { domAnimation, LazyMotion } from 'motion/react';
import { act } from 'react';
import { createRoot } from 'react-dom/client';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it, vi } from 'vitest';
import { CommerceSectionContent } from '@/components/custom/landing/commerce-sections';
import type { CommerceSection } from '@/lib/business/landing/types';

vi.mock('@/components/custom/landing/commerce-sections.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/landing-page.module.css', () => ({ default: {} }));

const collection: CommerceSection = {
  id: 'collection',
  enabled: true,
  type: 'commerce',
  variant: 'rail',
  heading: 'Travel collection',
  scrollLabel: 'Faites défiler la collection',
  filter: { label: 'Category', allLabel: 'Everything' },
  items: Array.from({ length: 12 }, (_, index) => ({
    id: `piece-${index}`,
    title: `Piece ${index + 1}`,
    price: '€120',
    category: index % 2 ? 'Accessories' : 'Bags',
    image: { src: '/test-assets/product.jpg', alt: `Product photograph ${index + 1}` },
    description: 'Supplied product description.',
    details: [{ label: 'Material', value: 'Grained leather' }],
    action: { label: `Read about piece ${index + 1}`, href: '#landing-footer' },
  })),
};

function content(section: CommerceSection) {
  return (
    <LazyMotion features={domAnimation}>
      <CommerceSectionContent section={section} />
    </LazyMotion>
  );
}

function staticContent(section: CommerceSection) {
  const container = document.createElement('div');
  container.innerHTML = renderToStaticMarkup(content(section));
  return container;
}

describe('additional commerce layouts', () => {
  it.each(['compact', 'rail', 'lookbook'] as const)(
    'preserves every product, native detail and action before JavaScript in %s',
    (variant) => {
      const container = staticContent({ ...collection, variant });
      expect(container.querySelectorAll('article')).toHaveLength(12);
      expect(container.querySelectorAll('details')).toHaveLength(12);
      expect(container.querySelectorAll('a[href="#landing-footer"]')).toHaveLength(12);
      expect(container.querySelectorAll('img')).toHaveLength(12);
      expect(container.querySelector('fieldset')).toBeNull();
      expect(container.querySelector('[hidden]')).toBeNull();
      expect(container.querySelector('article')?.textContent).toContain('Grained leather');
    },
  );

  it('provides a labelled keyboard focus target and localized scroll guidance', () => {
    const container = staticContent(collection);
    const rail = container.querySelector<HTMLElement>('section[aria-label="Travel collection"]');
    expect(rail).not.toBeNull();
    expect(rail?.tabIndex).toBe(0);
    const hintId = rail?.getAttribute('aria-describedby');
    expect(
      [...container.querySelectorAll('[id]')].find((node) => node.id === hintId)?.textContent,
    ).toContain('Faites défiler la collection');
    expect(rail?.querySelectorAll('article')).toHaveLength(12);
    expect(container.querySelector('button')).toBeNull();
  });

  it('does not promise scrolling for a single product', () => {
    const container = staticContent({ ...collection, items: collection.items.slice(0, 1) });
    expect(container.querySelectorAll('article')).toHaveLength(1);
    expect(container.textContent).not.toContain('Faites défiler la collection');
  });

  it('shows lookbook descriptions beside the product and keeps only specifications in disclosures', () => {
    const container = staticContent({ ...collection, variant: 'lookbook' });
    const product = container.querySelector('article');
    expect(product?.querySelector('details')?.textContent).not.toContain(
      'Supplied product description.',
    );
    expect(product?.textContent).toContain('Supplied product description.');
    expect(product?.querySelector('details')?.textContent).toContain('Grained leather');
    const descriptionOnly = staticContent({
      ...collection,
      variant: 'lookbook',
      items: collection.items.map((item) => ({ ...item, details: undefined })),
    });
    expect(descriptionOnly.querySelector('details')).toBeNull();
    expect(descriptionOnly.textContent).toContain('Supplied product description.');
  });

  it('keeps keyboard focus on the active category when the rail contents change', async () => {
    vi.stubGlobal('IS_REACT_ACT_ENVIRONMENT', true);
    const container = document.createElement('div');
    document.body.append(container);
    const root = createRoot(container);
    try {
      await act(async () => root.render(content(collection)));
      const accessoryButton = [...container.querySelectorAll<HTMLButtonElement>('button')].find(
        (button) => button.textContent === 'Accessories',
      );
      accessoryButton?.focus();
      await act(async () => accessoryButton?.click());
      expect(document.activeElement).toBe(accessoryButton);
      expect(accessoryButton?.getAttribute('aria-pressed')).toBe('true');
      expect(container.querySelectorAll('article')).toHaveLength(6);
      const allButton = [...container.querySelectorAll<HTMLButtonElement>('button')].find(
        (button) => button.textContent === 'Everything',
      );
      allButton?.focus();
      await act(async () => allButton?.click());
      expect(document.activeElement).toBe(allButton);
      expect(container.querySelectorAll('article')).toHaveLength(12);
    } finally {
      await act(async () => root.unmount());
      container.remove();
      vi.unstubAllGlobals();
    }
  });
});
