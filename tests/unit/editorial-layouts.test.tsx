// @polsia:user-owned
import { domAnimation, LazyMotion } from 'motion/react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it, vi } from 'vitest';
import { EditorialShowcase } from '@/components/custom/landing/editorial-showcase';
import type { GallerySection } from '@/lib/business/landing/types';

vi.mock('@/components/custom/landing/landing-page.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/editorial-showcase.module.css', () => ({ default: {} }));

function render(section: GallerySection) {
  const container = document.createElement('div');
  container.innerHTML = renderToStaticMarkup(
    <LazyMotion features={domAnimation}>
      <EditorialShowcase section={section} />
    </LazyMotion>,
  );
  return container;
}

describe('editorial showcase content', () => {
  it.each(['mosaic', 'story'] as const)(
    'keeps every item in reading order and exposes supplied copy and actions in %s',
    (variant) => {
      for (const count of [1, 2, 3, 5, 12]) {
        const items = Array.from({ length: count }, (_, index) => ({
          title: `Project ${index + 1}`,
          subtitle: `The story of project ${index + 1}`,
          image: `/projects/${index + 1}.jpg`,
          alt: `Photograph of project ${index + 1}`,
          category: 'Selected work',
          tag: 'Edition 2026',
          price: '€240',
          action: { label: `Explore project ${index + 1}`, href: `/projects/${index + 1}` },
        }));
        const container = render({
          id: 'work',
          type: 'gallery',
          enabled: true,
          variant,
          heading: 'Selected stories',
          description: 'The people, places and details behind the work.',
          items,
        });
        expect(container.querySelector('h2')?.textContent).toBe('Selected stories');
        expect(container.textContent).toContain('The people, places and details behind the work.');
        expect([...container.querySelectorAll('h3')].map((node) => node.textContent)).toEqual(
          items.map((item) => item.title),
        );
        const articles = [...container.querySelectorAll('article')];
        expect(articles).toHaveLength(count);
        for (const [index, article] of articles.entries()) {
          expect(article.querySelector('img')?.getAttribute('src')).toBe(
            `/projects/${index + 1}.jpg`,
          );
          expect(article.querySelector('img')?.getAttribute('alt')).toBe(
            `Photograph of project ${index + 1}`,
          );
          expect(article.textContent).toContain(`The story of project ${index + 1}`);
          expect(article.textContent).toContain('Selected work');
          expect(article.textContent).toContain('Edition 2026');
          expect(article.textContent).toContain('€240');
          expect(article.querySelector('a')?.getAttribute('href')).toBe(`/projects/${index + 1}`);
          expect(article.querySelector('a')?.closest('figure')).toBeNull();
        }
        expect(container.querySelector('[hidden]')).toBeNull();
      }
    },
  );

  it.each(['mosaic', 'story'] as const)('shows text without an invented photo in %s', (variant) => {
    const container = render({
      id: 'work',
      type: 'gallery',
      enabled: true,
      variant,
      heading: 'Selected stories',
      items: [{ title: 'Work in progress', subtitle: 'A genuine description without imagery.' }],
    });
    expect(container.querySelector('h3')?.textContent).toBe('Work in progress');
    expect(container.querySelector('img, figure, a')).toBeNull();
  });
});
