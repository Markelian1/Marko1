// @polsia:user-owned
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it, vi } from 'vitest';
import { LandingPage } from '@/components/custom/landing/landing-page';
import { landingConfig } from '@/lib/business/landing/config';
import { landingConfigSchema } from '@/lib/business/landing/schema';

vi.mock('@/components/custom/landing/campaign-sections.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/editorial-showcase.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/personal-sections.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/commerce-sections.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/landing-page.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/visual-variants.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/trust-sections.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/practical-sections.module.css', () => ({ default: {} }));

const media = { src: '/landing/placeholder.svg', alt: 'A project in progress' };
const items = [
  { title: 'Discover', description: 'Define the brief.' },
  { title: 'Design', description: 'Explore a direction.' },
  { title: 'Deliver', description: 'Bring the project to life.' },
];
const steps = {
  id: 'process',
  type: 'steps',
  enabled: true,
  heading: 'From idea to delivery',
  items,
};

function composition(sections: unknown[]) {
  return { ...landingConfig, sections };
}

function renderSections(sections: unknown[]) {
  const config = landingConfigSchema.parse(composition(sections));
  const container = document.createElement('div');
  container.innerHTML = renderToStaticMarkup(<LandingPage config={config} />);
  return container;
}

describe('steps composition', () => {
  it.each(['timeline', 'cards', 'vertical'])(
    'accepts %s without images and renders every step in order',
    (variant) => {
      const container = renderSections([{ ...steps, variant }]);
      expect(
        [...container.querySelectorAll('#process ol h3')].map((node) => node.textContent),
      ).toEqual(['Discover', 'Design', 'Deliver']);
      expect(container.querySelector('#process img')).toBeNull();
    },
  );

  it('renders an image beside native accordion disclosures, with the first step open', () => {
    const container = renderSections([{ ...steps, variant: 'image-accordion', media }]);
    expect(container.querySelector('#process img')?.getAttribute('alt')).toBe(media.alt);
    const disclosures = [...container.querySelectorAll('#process details')];
    expect(disclosures).toHaveLength(3);
    expect(disclosures.map((node) => node.hasAttribute('open'))).toEqual([true, false, false]);
    expect(disclosures.map((node) => node.querySelector('p')?.textContent)).toEqual([
      'Define the brief.',
      'Explore a direction.',
      'Bring the project to life.',
    ]);
    expect(disclosures.every((node) => node.querySelector('summary'))).toBe(true);
  });

  it('gives multiple accordion sections independent disclosure groups', () => {
    const section = { ...steps, variant: 'image-accordion', media };
    const container = renderSections([section, { ...section, id: 'another-process' }]);
    const firstGroup = container.querySelector('#process details')?.getAttribute('name');
    const secondGroup = container.querySelector('#another-process details')?.getAttribute('name');
    expect(firstGroup).toBeTruthy();
    expect(secondGroup).toBeTruthy();
    expect(firstGroup).not.toBe(secondGroup);
  });

  it('renders each alternating step with its own supplied image and description', () => {
    const container = renderSections([
      {
        ...steps,
        variant: 'alternating',
        items: items.map((item) => ({ ...item, media: { ...media, alt: item.title } })),
      },
    ]);
    expect(
      [...container.querySelectorAll('#process ol img')].map((node) => node.getAttribute('alt')),
    ).toEqual(['Discover', 'Design', 'Deliver']);
    expect(container.querySelectorAll('#process ol h3')).toHaveLength(3);
  });

  it.each([
    { ...steps, variant: 'image-accordion' },
    { ...steps, variant: 'alternating', items: [{ ...items[0], media }, items[1]] },
  ])('rejects an image layout with missing imagery', (section) => {
    const result = landingConfigSchema.safeParse(composition([section]));
    expect(result.success).toBe(false);
    if (result.success) throw new Error('Missing image must be rejected.');
    expect(result.error.issues.some((issue) => issue.path.at(-1) === 'media')).toBe(true);
  });

  it.each([
    { src: 'javascript:alert(1)', alt: 'Project' },
    { src: '/landing/placeholder.svg', alt: '' },
  ])('rejects unsafe or unlabelled step imagery', (invalidMedia) => {
    for (const section of [
      { ...steps, variant: 'image-accordion', media: invalidMedia },
      { ...steps, variant: 'alternating', items: [{ ...items[0], media: invalidMedia }] },
    ]) {
      expect(landingConfigSchema.safeParse(composition([section])).success).toBe(false);
    }
  });
});
