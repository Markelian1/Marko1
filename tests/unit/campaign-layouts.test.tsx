// @polsia:user-owned
import { domAnimation, LazyMotion } from 'motion/react';
import type { ReactNode } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it, vi } from 'vitest';
import { CampaignHero, MinimalCta } from '@/components/custom/landing/campaign-sections';
import type { CtaSection, HeroSection } from '@/lib/business/landing/types';

vi.mock('@/components/custom/landing/campaign-sections.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/landing-page.module.css', () => ({ default: {} }));

const campaign: HeroSection = {
  id: 'campaign',
  enabled: true,
  type: 'hero',
  variant: 'campaign',
  eyebrow: 'A season outdoors',
  title: 'A little further.',
  description: 'A considered collection for the journeys ahead.',
  primaryAction: { label: 'Explore the collection', href: '#collection' },
  secondaryAction: { label: 'Read our story', href: '/story' },
  note: 'A fictional collection for this demonstration.',
  media: {
    kind: 'image',
    src: '/test-assets/campaign.jpg',
    alt: 'A woman carrying a plain leather bag beside a lake',
    caption: 'An illustrative lakeside campaign.',
  },
};

const cta: CtaSection = {
  id: 'invitation',
  enabled: true,
  type: 'cta',
  variant: 'minimal',
  heading: 'Find your next favourite.',
  description: 'Explore the details and discover a piece that feels like yours.',
  action: { label: 'View the collection', href: '#collection' },
  secondaryAction: { label: 'Email the studio', href: 'mailto:studio@example.com' },
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

describe('campaign and minimal layouts', () => {
  it('places supplied imagery before the headline and preserves every content field', () => {
    const container = renderStatic(<CampaignHero section={campaign} />);
    const image = container.querySelector('img');
    const headline = container.querySelector('h1');
    expect(image?.getAttribute('src')).toBe('/test-assets/campaign.jpg');
    expect(image?.getAttribute('loading')).toBe('eager');
    expect(image?.getAttribute('alt')).toBe('A woman carrying a plain leather bag beside a lake');
    expect(headline?.textContent).toBe(campaign.title);
    expect(image && headline && image.compareDocumentPosition(headline)).toBe(
      Node.DOCUMENT_POSITION_FOLLOWING,
    );
    expect(container.querySelector('figcaption')?.textContent).toBe(
      'An illustrative lakeside campaign.',
    );
    expect(container.textContent).toContain(campaign.eyebrow);
    expect(container.textContent).toContain(campaign.description);
    expect(container.textContent).toContain(campaign.note);
    expect([...container.querySelectorAll('a')].map((link) => link.getAttribute('href'))).toEqual([
      '#collection',
      '/story',
    ]);
  });

  it('renders real dashboard captures without adding mock interface content', () => {
    const container = renderStatic(
      <CampaignHero
        section={{
          ...campaign,
          media: {
            kind: 'dashboard',
            src: '/actual-capture.png',
            alt: 'The supplied application screenshot',
          },
        }}
      />,
    );
    expect(container.querySelector('img')?.getAttribute('src')).toBe('/actual-capture.png');
    expect(container.querySelector('img')?.getAttribute('alt')).toBe(
      'The supplied application screenshot',
    );
    expect(container.querySelector('figcaption')).toBeNull();
    expect(container.textContent).not.toMatch(/Website launch|Jamie Lee|All changes saved/);
  });

  it('does not invent image content when called with missing media outside validated config', () => {
    const container = renderStatic(<CampaignHero section={{ ...campaign, media: undefined }} />);
    expect(container.querySelector('img, figure, [role="img"]')).toBeNull();
    expect(container.querySelector('h1')?.textContent).toBe(campaign.title);
  });

  it('preserves the minimal CTA heading, description and working action destinations', () => {
    const container = renderStatic(<MinimalCta section={cta} />);
    expect(container.querySelector('h2')?.textContent).toBe(cta.heading);
    expect(container.querySelector('p')?.textContent).toBe(cta.description);
    expect([...container.querySelectorAll('a')].map((link) => link.getAttribute('href'))).toEqual([
      '#collection',
      'mailto:studio@example.com',
    ]);
    expect(container.querySelector('a')?.textContent).toContain('View the collection');
    expect(container.querySelector('button')).toBeNull();
  });

  it('omits empty description and secondary-action space from a minimal invitation', () => {
    const container = renderStatic(
      <MinimalCta section={{ ...cta, description: undefined, secondaryAction: undefined }} />,
    );
    expect(container.querySelector('h2')?.textContent).toBe(cta.heading);
    expect(container.querySelector('p')).toBeNull();
    expect(container.querySelectorAll('a')).toHaveLength(1);
  });
});
