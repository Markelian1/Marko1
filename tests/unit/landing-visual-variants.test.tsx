// @polsia:user-owned
import { domAnimation, LazyMotion } from 'motion/react';
import { act, type ReactNode } from 'react';
import { createRoot } from 'react-dom/client';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it, vi } from 'vitest';
import { VisualVariant } from '@/components/custom/landing/visual-variants';
import type { FeaturesSection, GallerySection, HeroSection } from '@/lib/business/landing/types';

vi.mock('@/components/custom/landing/landing-page.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/visual-variants.module.css', () => ({ default: {} }));

const hero: HeroSection = {
  id: 'welcome',
  enabled: true,
  type: 'hero',
  variant: 'immersive',
  eyebrow: 'Made by hand',
  title: 'Objects with a story',
  description: 'Explore the current collection.',
  primaryAction: { label: 'View collection', href: '#collection' },
  secondaryAction: { label: 'Visit the studio', href: '/visit' },
  note: 'Open every Saturday',
  media: {
    kind: 'image',
    src: '/landing/primary.jpg',
    alt: 'Ceramic vessels on a shelf',
    caption: 'The studio collection',
  },
  collage: [
    { src: '/landing/detail.jpg', alt: 'Glaze detail', caption: 'Each finish is unique' },
    { src: '/landing/making.jpg', alt: 'Working at the wheel' },
  ],
};

const features: FeaturesSection = {
  id: 'benefits',
  enabled: true,
  type: 'features',
  variant: 'tabs',
  heading: 'Made for everyday life',
  description: 'Considered from start to finish.',
  items: [
    {
      title: 'Thoughtful materials',
      description: 'Locally sourced clay.',
      icon: 'leaf',
      media: { src: '/landing/clay.jpg', alt: 'Natural clay' },
    },
    {
      title: 'A lasting finish',
      description: 'A glaze made for daily use.',
      icon: 'shield',
      media: { src: '/landing/glaze.jpg', alt: 'Glazed ceramic', caption: 'Tested in the studio' },
    },
    {
      title: 'Your own shape',
      description: 'Choose a form that fits.',
      icon: 'layers',
      media: { src: '/landing/shapes.jpg', alt: 'Three ceramic shapes' },
    },
  ],
};

const gallery: GallerySection = {
  id: 'collection',
  enabled: true,
  type: 'gallery',
  variant: 'catalog',
  heading: 'Current collection',
  items: [
    {
      title: 'Breakfast bowl',
      subtitle: 'Stoneware in blue',
      image: '/landing/bowl.jpg',
      alt: 'Blue stoneware bowl',
      price: '€28',
      tag: 'Small batch',
      category: 'Tableware',
      action: { label: 'View bowl', href: '/collection/bowl' },
    },
    {
      title: 'Pouring jug',
      subtitle: 'A quiet morning ritual',
      image: '/landing/jug.jpg',
      alt: 'Ceramic pouring jug',
      category: 'Tableware',
    },
  ],
};

function renderStatic(section: HeroSection | FeaturesSection | GallerySection) {
  const container = document.createElement('div');
  container.innerHTML = renderToStaticMarkup(
    <LazyMotion features={domAnimation}>
      <VisualVariant section={section} />
    </LazyMotion>,
  );
  return container;
}

function requiredAt<T>(items: readonly T[], index: number): T {
  const item = items[index];
  if (item === undefined) throw new Error(`Expected an item at index ${index}.`);
  return item;
}

async function withMounted(
  content: ReactNode,
  check: (container: HTMLDivElement) => Promise<void>,
) {
  vi.stubGlobal('IS_REACT_ACT_ENVIRONMENT', true);
  const container = document.createElement('div');
  document.body.append(container);
  const root = createRoot(container);
  try {
    await act(async () => root.render(<LazyMotion features={domAnimation}>{content}</LazyMotion>));
    await check(container);
  } finally {
    await act(async () => root.unmount());
    container.remove();
    vi.unstubAllGlobals();
  }
}

describe('landing visual variants', () => {
  it('renders an immersive hero photo, supplied copy and actual action destinations', () => {
    const container = renderStatic(hero);
    expect(container.querySelector('h1')?.textContent).toBe('Objects with a story');
    expect(container.querySelector('img')?.alt).toBe('Ceramic vessels on a shelf');
    expect(container.textContent).toContain('Open every Saturday');
    expect(container.textContent).toContain('The studio collection');
    expect([...container.querySelectorAll('a')].map((link) => link.getAttribute('href'))).toEqual([
      '#collection',
      '/visit',
    ]);
  });

  it.each([1, 2])(
    'renders a collage with the primary photo and %i additional supplied photos',
    (count) => {
      const container = renderStatic({
        ...hero,
        variant: 'collage',
        collage: hero.collage?.slice(0, count),
      });
      expect([...container.querySelectorAll('img')].map((image) => image.alt)).toEqual(
        ['Ceramic vessels on a shelf', 'Glaze detail', 'Working at the wheel'].slice(0, count + 1),
      );
      expect(container.textContent).toContain('Each finish is unique');
      expect(container.querySelector('a')?.getAttribute('href')).toBe('#collection');
    },
  );

  it('keeps bento benefits with and without optional media readable', () => {
    const container = renderStatic({
      ...features,
      variant: 'bento',
      items: [
        requiredAt(features.items, 0),
        { title: 'Simple care', description: 'Easy to clean.', icon: 'sparkles' },
      ],
    });
    expect([...container.querySelectorAll('h3')].map((heading) => heading.textContent)).toEqual([
      'Thoughtful materials',
      'Simple care',
    ]);
    expect(container.querySelectorAll('img')).toHaveLength(1);
    expect(container.textContent).toContain('Locally sourced clay.');
    expect(container.textContent).toContain('Easy to clean.');
  });

  it('keeps every feature and image visible in the server-rendered tabs fallback', () => {
    const container = renderStatic(features);
    expect([...container.querySelectorAll('h3')].map((heading) => heading.textContent)).toEqual([
      'Thoughtful materials',
      'A lasting finish',
      'Your own shape',
    ]);
    const images = [...container.querySelectorAll('img')];
    expect(images.map((image) => image.alt)).toEqual([
      'Natural clay',
      'Glazed ceramic',
      'Three ceramic shapes',
    ]);
    expect(images.every((image) => !image.closest('[hidden]'))).toBe(true);
  });

  it('supports arrow, Home and End navigation with matching focus and a single selected panel', async () => {
    await withMounted(<VisualVariant section={features} />, async (container) => {
      const tabs = [...container.querySelectorAll<HTMLButtonElement>('[role="tab"]')];
      expect(tabs).toHaveLength(3);
      const assertSelected = (index: number) => {
        expect(tabs.map((tab) => tab.getAttribute('aria-selected'))).toEqual(
          tabs.map((_, at) => String(at === index)),
        );
        expect(tabs.map((tab) => tab.tabIndex)).toEqual(
          tabs.map((_, at) => (at === index ? 0 : -1)),
        );
        const panels = [...container.querySelectorAll<HTMLElement>('[role="tabpanel"]')];
        expect(panels.filter((panel) => !panel.hidden)).toHaveLength(1);
        expect(requiredAt(panels, index).id).toBe(
          requiredAt(tabs, index).getAttribute('aria-controls'),
        );
        expect(requiredAt(panels, index).getAttribute('aria-labelledby')).toBe(
          requiredAt(tabs, index).id,
        );
      };
      assertSelected(0);
      requiredAt(tabs, 0).focus();
      for (const [key, index] of [
        ['ArrowRight', 1],
        ['End', 2],
        ['ArrowRight', 0],
        ['ArrowLeft', 2],
        ['Home', 0],
      ] as const) {
        await act(async () =>
          document.activeElement?.dispatchEvent(
            new KeyboardEvent('keydown', { key, bubbles: true }),
          ),
        );
        assertSelected(index);
        expect(document.activeElement).toBe(tabs[index]);
      }
      await act(async () => requiredAt(tabs, 1).click());
      assertSelected(1);
      expect(container.querySelector('[role="tabpanel"]:not([hidden])')?.textContent).toContain(
        'A glaze made for daily use.',
      );
    });
  });

  it('keeps multiple tab sections independent and uses unique tab/panel relationships', async () => {
    await withMounted(
      <>
        <VisualVariant section={features} />
        <VisualVariant section={{ ...features, id: 'more-benefits' }} />
      </>,
      async (container) => {
        const tablists = [...container.querySelectorAll('[role="tablist"]')];
        const firstTabs = [
          ...requiredAt(tablists, 0).querySelectorAll<HTMLButtonElement>('[role="tab"]'),
        ];
        const secondTabs = [
          ...requiredAt(tablists, 1).querySelectorAll<HTMLButtonElement>('[role="tab"]'),
        ];
        await act(async () => requiredAt(firstTabs, 2).click());
        expect(requiredAt(firstTabs, 2).getAttribute('aria-selected')).toBe('true');
        expect(requiredAt(secondTabs, 0).getAttribute('aria-selected')).toBe('true');
        const ids = [...container.querySelectorAll('[id]')].map((element) => element.id);
        expect(new Set(ids).size).toBe(ids.length);
      },
    );
  });

  it('renders catalog photos, optional price and real links without fabricating absent content', () => {
    const container = renderStatic(gallery);
    expect([...container.querySelectorAll('h3')].map((heading) => heading.textContent)).toEqual([
      'Breakfast bowl',
      'Pouring jug',
    ]);
    expect([...container.querySelectorAll('img')].map((image) => image.alt)).toEqual([
      'Blue stoneware bowl',
      'Ceramic pouring jug',
    ]);
    expect(container.textContent).toContain('€28');
    expect(container.textContent).toContain('Stoneware in blue');
    expect(container.textContent).toContain('Small batch');
    expect(container.querySelectorAll('a')).toHaveLength(1);
    expect(container.querySelector('a')?.getAttribute('href')).toBe('/collection/bowl');
  });

  it('groups menu rows by supplied category and permits rows without photos or prices', () => {
    const container = renderStatic({
      ...gallery,
      variant: 'menu',
      items: [
        {
          title: 'Tea',
          category: 'Drinks',
          price: '€4',
          action: { label: 'Tea details', href: '/tea' },
        },
        {
          title: 'Pear tart',
          category: 'Seasonal',
          subtitle: 'Served warm',
          image: '/landing/tart.jpg',
          alt: 'Pear tart',
        },
        { title: 'Coffee', category: 'Drinks', price: '€3' },
        { title: 'Daily special', subtitle: 'Ask us what is fresh' },
      ],
    });
    expect([...container.querySelectorAll('h3')].map((heading) => heading.textContent)).toEqual([
      'Drinks',
      'Seasonal',
    ]);
    const lists = [...container.querySelectorAll('ul')];
    expect([...requiredAt(lists, 0).querySelectorAll('li')].map((row) => row.textContent)).toEqual([
      'Tea€4Tea details',
      'Coffee€3',
    ]);
    expect(container.querySelectorAll('img')).toHaveLength(1);
    expect(container.querySelector('img')?.alt).toBe('Pear tart');
    expect(container.textContent).toContain('Daily special');
    expect(container.querySelector('a')?.getAttribute('href')).toBe('/tea');
  });
});
