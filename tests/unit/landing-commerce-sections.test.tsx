// @polsia:user-owned
import { domAnimation, LazyMotion } from 'motion/react';
import { act } from 'react';
import { createRoot } from 'react-dom/client';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it, vi } from 'vitest';
import { CommerceSectionContent } from '@/components/custom/landing/commerce-sections';
import type { CommerceSection } from '@/lib/business/landing/types';

vi.mock('@/components/custom/landing/landing-page.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/commerce-sections.module.css', () => ({ default: {} }));

const collection: CommerceSection = {
  id: 'collection',
  enabled: true,
  type: 'commerce',
  variant: 'grid',
  heading: 'The living collection',
  description: 'Explore the available finishes.',
  notice: 'Concept collection. Products are not available to purchase.',
  filter: { label: 'Browse by category', allLabel: 'All pieces' },
  detailsLabel: 'View details',
  items: [
    {
      id: 'linen-sofa',
      title: 'Linen sofa',
      image: { src: '/assets/collection/linen-sofa.jpg', alt: 'Natural linen two-seat sofa' },
      price: '€1,400',
      category: 'Sofas',
      description: 'A compact sofa with removable covers.',
      details: [
        { label: 'Material', value: 'Linen and oak' },
        { label: 'Colour', value: 'Natural' },
      ],
      action: { label: 'Ask about this sofa', href: 'mailto:studio@example.com' },
    },
    {
      id: 'oak-chair',
      title: 'Oak chair',
      image: { src: '/assets/collection/oak-chair.jpg', alt: 'Oak lounge chair' },
      category: 'Chairs',
      details: [{ label: 'Material', value: 'Solid oak' }],
    },
    {
      id: 'footstool',
      title: 'Footstool',
      image: { src: '/assets/collection/footstool.jpg', alt: 'Upholstered footstool' },
    },
  ],
};

function content(section: CommerceSection) {
  return (
    <LazyMotion features={domAnimation}>
      <CommerceSectionContent section={section} />
    </LazyMotion>
  );
}

function renderStatic(section = collection) {
  const container = document.createElement('div');
  container.innerHTML = renderToStaticMarkup(content(section));
  return container;
}

describe('commerce landing sections', () => {
  it.each(['grid', 'featured'] as const)(
    'renders the supplied merchandise and useful native details before JavaScript in %s',
    (variant) => {
      const container = renderStatic({ ...collection, variant });
      expect(container.querySelector('h2')?.textContent).toBe(collection.heading);
      expect(container.querySelectorAll('article')).toHaveLength(3);
      expect(container.textContent).toContain(collection.notice);
      expect(container.textContent).toContain('€1,400');
      expect(container.textContent).not.toMatch(/in stock|add to cart|checkout/i);
      const image = container.querySelector('img');
      expect(image?.getAttribute('src')).toBe('/assets/collection/linen-sofa.jpg');
      expect(image?.alt).toBe('Natural linen two-seat sofa');
      const details = container.querySelector('details');
      expect(details?.querySelector('summary')?.textContent).toContain('View details');
      expect(details?.textContent).toContain('A compact sofa with removable covers.');
      expect(details?.querySelector('dt')?.textContent).toBe('Material');
      expect(details?.querySelector('dd')?.textContent).toBe('Linen and oak');
      expect(container.querySelector('fieldset')).toBeNull();
      expect(container.querySelector('a')?.getAttribute('href')).toBe('mailto:studio@example.com');
      expect(container.querySelectorAll('a')).toHaveLength(1);
      expect(container.querySelectorAll('details')).toHaveLength(2);
      expect(container.querySelectorAll('[hidden]')).toHaveLength(0);
    },
  );

  it('filters categories after hydration, restores all items and handles changed content', async () => {
    vi.stubGlobal('IS_REACT_ACT_ENVIRONMENT', true);
    const container = document.createElement('div');
    document.body.append(container);
    const root = createRoot(container);
    try {
      await act(async () => root.render(content(collection)));
      const group = container.querySelector('fieldset');
      expect(group?.querySelector('legend')?.textContent).toBe('Browse by category');
      const buttons = [...container.querySelectorAll<HTMLButtonElement>('button')];
      expect(buttons.map((button) => button.textContent)).toEqual([
        'All pieces',
        'Sofas',
        'Chairs',
      ]);
      await act(async () => buttons.find((button) => button.textContent === 'Chairs')?.click());
      expect(container.querySelectorAll('article')).toHaveLength(1);
      expect(container.querySelector('h3')?.textContent).toBe('Oak chair');
      expect(
        buttons.find((button) => button.textContent === 'Chairs')?.getAttribute('aria-pressed'),
      ).toBe('true');
      await act(async () => buttons[0]?.click());
      expect(container.querySelectorAll('article')).toHaveLength(3);
      await act(async () => buttons.find((button) => button.textContent === 'Chairs')?.click());
      await act(async () =>
        root.render(
          content({
            ...collection,
            items: collection.items.filter((item) => item.category !== 'Chairs'),
          }),
        ),
      );
      expect(container.querySelectorAll('article')).toHaveLength(2);
      expect(container.querySelector('fieldset')).toBeNull();
    } finally {
      await act(async () => root.unmount());
      container.remove();
      vi.unstubAllGlobals();
    }
  });

  it('does not create filter controls or empty disclosures without supplied content', () => {
    const container = renderStatic({
      ...collection,
      filter: undefined,
      items: collection.items.map(({ id, title, image }) => ({ id, title, image })),
    });
    expect(container.querySelector('button, details, a')).toBeNull();
    expect(container.querySelectorAll('img')).toHaveLength(3);
  });
});
