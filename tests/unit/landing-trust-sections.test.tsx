// @polsia:user-owned
import { domAnimation, LazyMotion } from 'motion/react';
import { act, type ReactNode } from 'react';
import { createRoot } from 'react-dom/client';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it, vi } from 'vitest';
import { TrustSection } from '@/components/custom/landing/trust-sections';
import type {
  LogosSection,
  StatsSection,
  TeamSection,
  TestimonialSection,
} from '@/lib/business/landing/types';

vi.mock('@/components/custom/landing/trust-sections.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/landing-page.module.css', () => ({ default: {} }));

const logos: LogosSection = {
  id: 'partners',
  type: 'logos',
  enabled: true,
  variant: 'band',
  heading: 'Our project partners',
  items: [
    { name: 'Example Workshop', image: '/workshop.svg', href: '/partners/workshop' },
    { name: 'Example Press' },
  ],
};
const stats: StatsSection = {
  id: 'numbers',
  type: 'stats',
  enabled: true,
  variant: 'inline',
  heading: 'A year of making',
  items: [
    { value: '12', label: 'Workshops', description: 'Held during the supplied reporting period.' },
    { value: '8', label: 'Projects' },
  ],
};
const team: TeamSection = {
  id: 'people',
  type: 'team',
  enabled: true,
  variant: 'founder',
  heading: 'A note from the founder',
  people: [
    {
      name: 'Alex Example',
      role: 'Founder',
      bio: 'We built the workshop around shared learning.',
      portrait: { src: '/alex.jpg', alt: 'Alex in the workshop', caption: 'At the workbench' },
      action: { label: 'Read Alex’s story', href: '/people/alex' },
    },
  ],
};
const testimonial: TestimonialSection = {
  id: 'stories',
  type: 'testimonial',
  enabled: true,
  variant: 'carousel',
  heading: 'In their words',
  items: [
    {
      quote: 'The workshop made room for every question.',
      author: 'Riley Example',
      role: 'Workshop participant',
      portrait: { src: '/riley.jpg', alt: 'Riley at the workshop' },
    },
    { quote: 'We left with a plan we could use.', author: 'Morgan Example' },
    { quote: 'A thoughtful experience from start to finish.', author: 'Sam Example' },
  ],
};

function renderStatic(content: ReactNode) {
  const container = document.createElement('div');
  container.innerHTML = renderToStaticMarkup(
    <LazyMotion features={domAnimation} strict>
      {content}
    </LazyMotion>,
  );
  return container;
}

async function withMounted(content: ReactNode, test: (container: HTMLDivElement) => Promise<void>) {
  vi.stubGlobal('IS_REACT_ACT_ENVIRONMENT', true);
  const container = document.createElement('div');
  document.body.append(container);
  const root = createRoot(container);
  try {
    await act(async () => root.render(content));
    await test(container);
  } finally {
    await act(async () => root.unmount());
    container.remove();
    vi.unstubAllGlobals();
  }
}

function visibleQuote(container: Element) {
  return container.querySelector('figure:not([hidden]) blockquote')?.textContent;
}

describe('trust and people sections', () => {
  it.each(['band', 'grid'] as const)('renders supplied logos and real links in %s', (variant) => {
    const container = renderStatic(<TrustSection section={{ ...logos, variant }} />);
    expect(container.querySelector('h2')?.textContent).toBe('Our project partners');
    expect(container.querySelector('a')?.getAttribute('href')).toBe('/partners/workshop');
    expect(container.querySelector('a img')?.getAttribute('alt')).toBe('Example Workshop');
    expect(container.querySelector('a img')?.getAttribute('src')).toBe('/workshop.svg');
    expect(container.querySelectorAll('li')).toHaveLength(2);
    expect(container.textContent).toContain('Example Press');
    expect(container.querySelectorAll('a')).toHaveLength(1);
  });

  it.each(['inline', 'visual'] as const)('renders supplied statistics in %s', (variant) => {
    const container = renderStatic(
      <TrustSection
        section={{
          ...stats,
          variant,
          ...(variant === 'visual'
            ? { media: { src: '/workshop.jpg', alt: 'The workshop', caption: 'Our space' } }
            : {}),
        }}
      />,
    );
    expect([...container.querySelectorAll('dt')].map((node) => node.textContent)).toEqual([
      'Workshops',
      'Projects',
    ]);
    expect(container.textContent).toContain('12');
    expect(container.textContent).toContain('Held during the supplied reporting period.');
    expect(container.textContent).toContain('8');
    if (variant === 'visual') {
      expect(container.querySelector('img')?.getAttribute('alt')).toBe('The workshop');
      expect(container.querySelector('figcaption')?.textContent).toBe('Our space');
    } else {
      expect(container.querySelector('img')).toBeNull();
    }
  });

  it('renders a founder’s supplied letter, portrait and profile destination', () => {
    const container = renderStatic(<TrustSection section={team} />);
    expect(container.querySelector('h2')?.textContent).toBe('A note from the founder');
    expect(container.textContent).toContain('We built the workshop around shared learning.');
    expect(container.textContent).toContain('Alex Example');
    expect(container.textContent).toContain('Founder');
    expect(container.querySelector('img')?.getAttribute('alt')).toBe('Alex in the workshop');
    expect(container.querySelector('figcaption')?.textContent).toBe('At the workbench');
    expect(container.querySelector('a')?.getAttribute('href')).toBe('/people/alex');
    expect(container.querySelector('a')?.textContent).toBe('Read Alex’s story');
  });

  it('renders every team member while omitting missing portraits and actions', () => {
    const container = renderStatic(
      <TrustSection
        section={{
          ...team,
          variant: 'grid',
          people: [...team.people, { name: 'Jamie Example', role: 'Designer' }],
        }}
      />,
    );
    expect([...container.querySelectorAll('h3')].map((node) => node.textContent)).toEqual([
      'Alex Example',
      'Jamie Example',
    ]);
    expect(container.textContent).toContain('Designer');
    expect(container.querySelectorAll('img')).toHaveLength(1);
    expect(container.querySelectorAll('a')).toHaveLength(1);
  });

  it.each(['wall', 'carousel'] as const)(
    'keeps every supplied %s quote and attribution visible without JavaScript',
    (variant) => {
      const container = renderStatic(<TrustSection section={{ ...testimonial, variant }} />);
      expect([...container.querySelectorAll('blockquote')].map((node) => node.textContent)).toEqual(
        [
          'The workshop made room for every question.',
          'We left with a plan we could use.',
          'A thoughtful experience from start to finish.',
        ],
      );
      expect(container.textContent).toContain('Riley Example');
      expect(container.textContent).toContain('Morgan Example');
      expect(container.textContent).toContain('Workshop participant');
      expect(container.querySelector('img')?.getAttribute('alt')).toBe('Riley at the workshop');
      expect(container.querySelector('[hidden]')).toBeNull();
      expect(container.querySelector('button')).toBeNull();
    },
  );

  it('selects carousel quotes with buttons and arrow/Home/End keys without moving focus', async () => {
    await withMounted(<TrustSection section={testimonial} />, async (container) => {
      const region = container.querySelector<HTMLElement>('[aria-roledescription="carousel"]');
      const next = container.querySelector<HTMLButtonElement>(
        'button[aria-label="Next testimonial"]',
      );
      expect(region).not.toBeNull();
      expect(next).not.toBeNull();
      expect(visibleQuote(container)).toBe('The workshop made room for every question.');
      next?.focus();
      await act(async () => next?.click());
      expect(visibleQuote(container)).toBe('We left with a plan we could use.');
      expect(document.activeElement).toBe(next);
      for (const [key, quote] of [
        ['End', 'A thoughtful experience from start to finish.'],
        ['ArrowRight', 'The workshop made room for every question.'],
        ['ArrowLeft', 'A thoughtful experience from start to finish.'],
        ['Home', 'The workshop made room for every question.'],
      ]) {
        const event = new KeyboardEvent('keydown', { key, bubbles: true, cancelable: true });
        await act(async () => next?.dispatchEvent(event));
        expect(event.defaultPrevented).toBe(true);
        expect(visibleQuote(container)).toBe(quote);
        expect(document.activeElement).toBe(next);
      }
      expect(container.querySelector('output')?.textContent).toContain('1 of 3');
      const controlledId = next?.getAttribute('aria-controls');
      expect(controlledId).toBeTruthy();
      expect([...container.querySelectorAll('[id]')].some((node) => node.id === controlledId)).toBe(
        true,
      );
    });
  });

  it('keeps two carousels independent with unique control targets', async () => {
    await withMounted(
      <>
        <TrustSection section={testimonial} />
        <TrustSection section={{ ...testimonial, id: 'more-stories' }} />
      </>,
      async (container) => {
        const regions = [...container.querySelectorAll('[aria-roledescription="carousel"]')];
        expect(regions).toHaveLength(2);
        const [first, second] = regions;
        if (!first || !second) throw new Error('Both carousels must render.');
        const firstNext = first.querySelector<HTMLButtonElement>(
          'button[aria-label="Next testimonial"]',
        );
        const secondNext = second.querySelector<HTMLButtonElement>(
          'button[aria-label="Next testimonial"]',
        );
        expect(firstNext?.getAttribute('aria-controls')).not.toBe(
          secondNext?.getAttribute('aria-controls'),
        );
        await act(async () => firstNext?.click());
        expect(visibleQuote(first)).toBe('We left with a plan we could use.');
        expect(visibleQuote(second)).toBe('The workshop made room for every question.');
      },
    );
  });
});
