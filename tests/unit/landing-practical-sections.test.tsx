// @polsia:user-owned
import { domAnimation, LazyMotion } from 'motion/react';
import { act } from 'react';
import { createRoot, type Root } from 'react-dom/client';
import { renderToStaticMarkup } from 'react-dom/server';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { PracticalSection } from '@/components/custom/landing/practical-sections';
import type {
  AgendaSection,
  ComparisonSection,
  ContactSection,
} from '@/lib/business/landing/types';

vi.mock('@/components/custom/landing/landing-page.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/practical-sections.module.css', () => ({ default: {} }));

const contact: ContactSection = {
  id: 'visit',
  type: 'contact',
  variant: 'details',
  enabled: true,
  heading: 'Visit the workshop',
  description: 'Come by during opening hours.',
  address: '12 Example Street\nBristol',
  email: 'hello@example.com',
  phone: '+44 20 7946 0123',
  hours: [{ label: 'Monday to Friday', value: '09:00–17:00' }],
  action: { label: 'Arrange a visit', href: 'mailto:hello@example.com' },
};

const comparison: ComparisonSection = {
  id: 'restoration',
  type: 'comparison',
  variant: 'before-after',
  enabled: true,
  heading: 'The same room, restored',
  before: { src: '/before.jpg', alt: 'Room before restoration', label: 'Original' },
  after: { src: '/after.jpg', alt: 'Room after restoration', label: 'Restored' },
};

function renderSection(section: ContactSection | ComparisonSection | AgendaSection) {
  const container = document.createElement('div');
  container.innerHTML = renderToStaticMarkup(
    <LazyMotion features={domAnimation}>
      <PracticalSection section={section} />
    </LazyMotion>,
  );
  return container;
}

let root: Root | undefined;
beforeEach(() => vi.stubGlobal('IS_REACT_ACT_ENVIRONMENT', true));
afterEach(async () => {
  if (root) await act(async () => root?.unmount());
  root = undefined;
  document.body.replaceChildren();
  vi.unstubAllGlobals();
});

describe('practical landing sections', () => {
  it('renders supplied contact details as usable contact links and opening hours', () => {
    const container = renderSection(contact);
    expect(container.querySelector('address')?.textContent).toContain('12 Example Street');
    expect(container.querySelector('a[href="mailto:hello@example.com"]')?.textContent).toBe(
      'hello@example.com',
    );
    expect(container.querySelector('a[href^="tel:"]')?.getAttribute('href')).toBe(
      'tel:+442079460123',
    );
    expect(container.querySelector('dt')?.textContent).toBe('Monday to Friday');
    expect(container.querySelector('dd')?.textContent).toBe('09:00–17:00');
    expect(
      [...container.querySelectorAll('a')]
        .find((a) => a.textContent?.includes('Arrange a visit'))
        ?.getAttribute('href'),
    ).toBe('mailto:hello@example.com');
    expect(container.querySelector('form, iframe')).toBeNull();
  });

  it('links the supplied map image to real directions', () => {
    const container = renderSection({
      ...contact,
      variant: 'map',
      map: {
        src: '/workshop-map.jpg',
        alt: 'Workshop entrance on Example Street',
        href: 'https://maps.example.com/workshop',
        caption: 'Entrance beside the courtyard',
      },
    });
    const map = container.querySelector('a[href="https://maps.example.com/workshop"]');
    expect(map?.querySelector('img')?.getAttribute('src')).toBe('/workshop-map.jpg');
    expect(map?.querySelector('img')?.getAttribute('alt')).toBe(
      'Workshop entrance on Example Street',
    );
    expect(container.textContent).toContain('Entrance beside the courtyard');
  });

  it('omits missing optional contact information', () => {
    const container = renderSection({
      id: 'contact',
      type: 'contact',
      variant: 'details',
      enabled: true,
      heading: 'Write to us',
      email: 'hello@example.com',
    });
    expect(container.querySelectorAll('a')).toHaveLength(1);
    expect(container.querySelector('dl, img')).toBeNull();
  });

  it('renders comparison values with row and column headers in a keyboard-focusable region', () => {
    const container = renderSection({
      ...comparison,
      variant: 'table',
      columns: [{ label: 'Essentials' }, { label: 'Complete', highlighted: true }],
      rows: [
        { label: 'Projects', values: ['One', 'Unlimited'] },
        { label: 'Support', values: ['Email', 'Priority'] },
      ],
    });
    expect(container.querySelector('table')?.getAttribute('aria-label')).toBe(
      'The same room, restored',
    );
    expect(
      [...container.querySelectorAll('thead th[scope="col"]')].map((node) => node.textContent),
    ).toEqual(['Feature', 'Essentials', 'Complete']);
    expect(
      [...container.querySelectorAll('tbody th[scope="row"]')].map((node) => node.textContent),
    ).toEqual(['Projects', 'Support']);
    expect([...container.querySelectorAll('td')].map((node) => node.textContent)).toEqual([
      'One',
      'Unlimited',
      'Email',
      'Priority',
    ]);
    expect(container.querySelector('section[aria-label]')?.getAttribute('tabindex')).toBe('0');
  });

  it('renders both before/after images and an explicitly labelled native range in server HTML', () => {
    const container = renderSection(comparison);
    expect([...container.querySelectorAll('img')].map((img) => img.alt)).toEqual([
      'Room after restoration',
      'Room before restoration',
    ]);
    const range = container.querySelector<HTMLInputElement>('input[type="range"]');
    expect(range?.value).toBe('50');
    expect(range?.disabled).toBe(true);
    expect(range?.min).toBe('0');
    expect(range?.max).toBe('100');
    expect(range?.labels?.[0]?.textContent).toContain('Compare images');
    expect(range?.getAttribute('aria-valuetext')).toBe('Original 50%, Restored 50%');
    expect(container.textContent).toContain('Original');
    expect(container.textContent).toContain('Restored');
  });

  it('updates the image reveal and accessible value without changing another comparison', async () => {
    const container = document.createElement('div');
    document.body.append(container);
    root = createRoot(container);
    await act(async () =>
      root?.render(
        <>
          <PracticalSection section={comparison} />
          <PracticalSection section={{ ...comparison, id: 'another-restoration' }} />
        </>,
      ),
    );
    const ranges = [...container.querySelectorAll<HTMLInputElement>('input[type="range"]')];
    const [firstRange, secondRange] = ranges;
    if (!firstRange || !secondRange) throw new Error('Both comparison controls must render.');
    expect(firstRange.disabled).toBe(false);
    expect(firstRange.id).not.toBe(secondRange.id);
    firstRange.focus();
    expect(document.activeElement).toBe(firstRange);
    const valueSetter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value')?.set;
    await act(async () => {
      valueSetter?.call(firstRange, '75');
      firstRange.dispatchEvent(new Event('input', { bubbles: true }));
    });
    expect(firstRange.getAttribute('aria-valuetext')).toBe('Original 75%, Restored 25%');
    expect(secondRange.value).toBe('50');
    expect(container.querySelector('figure[style]')?.getAttribute('style')).toContain('25%');
  });

  it.each(['schedule', 'curriculum'] as const)(
    'renders supplied %s items in order with optional actions',
    (variant) => {
      const container = renderSection({
        id: 'programme',
        type: 'agenda',
        variant,
        enabled: true,
        heading: 'A day in the workshop',
        items: [
          {
            title: 'Meet the material',
            label: 'Welcome',
            time: '09:00',
            duration: '45 minutes',
            description: 'Get to know your tools.',
          },
          {
            title: 'Make your first piece',
            description: 'Put the techniques into practice.',
            action: { label: 'See the materials', href: '/materials' },
          },
        ],
      });
      expect([...container.querySelectorAll('ol h3')].map((node) => node.textContent)).toEqual([
        'Meet the material',
        'Make your first piece',
      ]);
      expect(container.textContent).toContain('09:00');
      expect(container.textContent).toContain('45 minutes');
      expect(container.textContent).toContain('Welcome');
      expect(container.querySelector('a')?.getAttribute('href')).toBe('/materials');
      expect(container.querySelectorAll('a')).toHaveLength(1);
    },
  );
});
