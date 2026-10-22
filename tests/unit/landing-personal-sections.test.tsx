// @polsia:user-owned
import { domAnimation, LazyMotion } from 'motion/react';
import type { ReactNode } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it, vi } from 'vitest';
import { PortfolioGallery, ProfileHero } from '@/components/custom/landing/personal-sections';
import type { GallerySection, HeroSection } from '@/lib/business/landing/types';

vi.mock('@/components/custom/landing/personal-sections.module.css', () => ({ default: {} }));
vi.mock('@/components/custom/landing/landing-page.module.css', () => ({ default: {} }));

const profile: HeroSection = {
  id: 'about-me',
  enabled: true,
  type: 'hero',
  variant: 'profile',
  eyebrow: 'Independent designer in Copenhagen',
  title: 'Alex Rivera',
  description: 'I design thoughtful digital tools for people doing meaningful work.',
  primaryAction: { label: 'Email Alex', href: 'mailto:alex@example.com' },
  secondaryAction: { label: 'Selected work', href: '#work' },
  note: 'Available for collaborations from October.',
};

const portfolio: GallerySection = {
  id: 'work',
  enabled: true,
  type: 'gallery',
  variant: 'portfolio',
  heading: 'Selected work',
  description: 'A few projects I have shaped with good people.',
  items: [
    {
      title: 'Field notes',
      subtitle: 'An independent publication about the spaces we share.',
      category: 'Editorial design',
      tag: '2026',
      action: { label: 'Read Field notes', href: 'https://example.com/field-notes' },
    },
    {
      title: 'Open studio',
      subtitle: 'Making the work of local artists easier to discover.',
      image: '/work/open-studio.jpg',
      alt: 'The Open studio directory on a laptop',
      action: { label: 'View Open studio', href: '/work/open-studio' },
    },
    { title: 'Small observations', subtitle: 'Personal sketches and experiments.' },
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

describe('personal landing sections', () => {
  it('introduces a person without inventing imagery or a product dashboard', () => {
    const container = renderStatic(<ProfileHero section={profile} />);
    expect(container.querySelector('h1')?.textContent).toBe('Alex Rivera');
    expect(container.textContent).toContain(profile.eyebrow);
    expect(container.textContent).toContain(profile.description);
    expect(container.textContent).toContain(profile.note);
    expect(container.querySelectorAll('a')).toHaveLength(2);
    expect(container.querySelector('a')?.getAttribute('href')).toBe('mailto:alex@example.com');
    expect(container.querySelector('a[href="#work"]')?.textContent).toContain('Selected work');
    expect(container.querySelector('img, figure, [role="img"]')).toBeNull();
    expect(container.textContent).not.toContain('Workspace');
  });

  it('renders an optional real portrait with its supplied alternative text and caption', () => {
    const container = renderStatic(
      <ProfileHero
        section={{
          ...profile,
          media: {
            kind: 'image',
            src: '/alex-rivera.jpg',
            alt: 'Alex Rivera in their Copenhagen studio',
            caption: 'At the studio, September 2026',
          },
        }}
      />,
    );
    expect(container.querySelectorAll('img')).toHaveLength(1);
    expect(container.querySelector('img')?.getAttribute('src')).toBe('/alex-rivera.jpg');
    expect(container.querySelector('img')?.getAttribute('alt')).toBe(
      'Alex Rivera in their Copenhagen studio',
    );
    expect(container.querySelector('figcaption')?.textContent).toBe(
      'At the studio, September 2026',
    );
  });

  it('omits optional profile copy and a secondary action when they are not supplied', () => {
    const { eyebrow: _eyebrow, note: _note, secondaryAction: _action, ...minimal } = profile;
    const container = renderStatic(<ProfileHero section={minimal} />);
    expect(container.querySelectorAll('h1')).toHaveLength(1);
    expect(container.querySelectorAll('p')).toHaveLength(1);
    expect(container.querySelectorAll('a')).toHaveLength(1);
  });

  it('renders mixed text and image projects with supplied metadata and destinations', () => {
    const container = renderStatic(<PortfolioGallery section={portfolio} />);
    expect(container.querySelector('h2')?.textContent).toBe('Selected work');
    expect(container.textContent).toContain(portfolio.description);
    const projects = [...container.querySelectorAll('article')];
    expect(projects).toHaveLength(3);
    expect(projects.map((project) => project.querySelector('h3')?.textContent)).toEqual([
      'Field notes',
      'Open studio',
      'Small observations',
    ]);
    expect(projects[0]?.textContent).toContain('Editorial design');
    expect(projects[0]?.textContent).toContain('2026');
    expect(projects[0]?.querySelector('img')).toBeNull();
    expect(projects[0]?.querySelector('a')?.getAttribute('href')).toBe(
      'https://example.com/field-notes',
    );
    expect(projects[1]?.querySelector('img')?.getAttribute('alt')).toBe(
      'The Open studio directory on a laptop',
    );
    expect(projects[1]?.querySelector('a')?.getAttribute('href')).toBe('/work/open-studio');
    expect(projects[2]?.querySelector('a, img')).toBeNull();
    expect(container.querySelectorAll('img')).toHaveLength(1);
    expect(container.querySelector('[hidden], [aria-hidden="true"] img')).toBeNull();
  });

  it('keeps a text-only portfolio useful without empty image frames or fabricated numbering', () => {
    const container = renderStatic(
      <PortfolioGallery
        section={{ ...portfolio, items: [{ title: 'Small observations', subtitle: 'Sketches.' }] }}
      />,
    );
    expect(container.querySelector('h3')?.textContent).toBe('Small observations');
    expect(container.querySelector('img, figure, [role="img"]')).toBeNull();
    expect(container.textContent).not.toMatch(/01|Read more|Coming soon/);
  });
});
