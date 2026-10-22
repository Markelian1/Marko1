// @polsia:user-owned — available landing sections and layouts for the onboarding agent.
import type { NavbarVariant, SectionType } from './types';

/** Select independently of the hero and section layouts with config.navbar.variant. */
export const navbarCatalog = {
  classic: {
    label: 'Classic',
    description:
      'Brand left, visible navigation and primary action. A familiar default for service and product sites.',
  },
  centered: {
    label: 'Centered brand',
    description:
      'Brand in the middle, navigation left and action right. Suits a concise editorial, hospitality or retail identity.',
  },
  floating: {
    label: 'Floating bar',
    description:
      'An inset rounded bar above the hero. Uses the page theme, with visible navigation and action.',
  },
  minimal: {
    label: 'Minimal',
    description:
      'Brand and menu toggle at every width; the action moves into the menu on narrow screens. Keeps campaign and portfolio pages focused while links remain in the menu.',
  },
} as const satisfies Record<NavbarVariant, { label: string; description: string }>;

export const sectionCatalog = {
  hero: {
    label: 'Hero',
    description:
      'Introduce the offer and its primary action. Centered works without imagery; profile introduces a person with an optional real portrait. Immersive/collage need supplied imagery; campaign places a wide image above centered copy. Product screenshots must show the actual product.',
    variants: ['split', 'centered', 'cover', 'immersive', 'collage', 'profile', 'campaign'],
  },
  features: {
    label: 'Benefits',
    description:
      'Explain features, services or differentiators. Bento uses varied card sizes; tabs need media on every item.',
    variants: ['grid', 'split', 'list', 'bento', 'tabs'],
  },
  gallery: {
    label: 'Showcase',
    description:
      'Show projects or offers. Portfolio presents selected work with optional real project images; catalog adds prices/actions; menu groups by category. Mosaic pairs varied image sizes; story alternates image and text. Use commerce for product details and category browsing.',
    variants: ['cards', 'editorial', 'catalog', 'menu', 'portfolio', 'mosaic', 'story'],
  },
  commerce: {
    label: 'Product collection',
    description:
      'Merchandise with supplied photos, prices, expandable information and optional category filters. Grid gives equal weight; featured emphasizes the first product; compact shows more products per row; rail scrolls horizontally; lookbook alternates large photos and product copy. Actions link to real product or purchase flows; this is not a cart or checkout.',
    variants: ['grid', 'featured', 'compact', 'rail', 'lookbook'],
  },
  steps: {
    label: 'How it works',
    description:
      'Explain a sequence: timeline or cards in columns; vertical beside an introduction; image-accordion with section.media; alternating with media on every item.',
    variants: ['timeline', 'cards', 'vertical', 'image-accordion', 'alternating'],
  },
  pricing: {
    label: 'Pricing',
    description: 'Compare plans, packages or offers.',
    variants: ['cards', 'compact'],
  },
  testimonial: {
    label: 'Testimonial',
    description:
      'Show supplied, attributable quotes. Spotlight/split use quote/author/role; wall/carousel use items with optional portraits.',
    variants: ['spotlight', 'split', 'wall', 'carousel'],
  },
  logos: {
    label: 'References',
    description:
      'Display supplied client or partner names/logos in a compact band or grid. Never invent endorsements.',
    variants: ['band', 'grid'],
  },
  stats: {
    label: 'Key figures',
    description:
      'Highlight supplied figures inline or beside media. Visual requires section.media; omit unverified claims.',
    variants: ['inline', 'visual'],
  },
  team: {
    label: 'People',
    description:
      'Introduce one founder with a personal letter, or a team grid. Founder displays the first person; grid displays everyone.',
    variants: ['founder', 'grid'],
  },
  contact: {
    label: 'Contact & location',
    description:
      'Show address, email, phone, hours or a working contact action. Map needs a supplied map image and HTTPS directions URL.',
    variants: ['details', 'map'],
  },
  comparison: {
    label: 'Comparison',
    description:
      'Compare criteria in a table (one value per column) or supplied labeled before/after images.',
    variants: ['table', 'before-after'],
  },
  agenda: {
    label: 'Programme',
    description:
      'Present scheduled sessions with times, or learning modules with durations. Actions link to working flows.',
    variants: ['schedule', 'curriculum'],
  },
  faq: {
    label: 'FAQ',
    description: 'Answer common questions.',
    variants: ['accordion', 'columns'],
  },
  cta: {
    label: 'Call to action',
    description:
      'Invite the visitor to take the next step. Minimal uses an unboxed headline and prominent text link.',
    variants: ['banner', 'centered', 'minimal'],
  },
} as const satisfies Record<
  SectionType,
  { label: string; description: string; variants: readonly string[] }
>;
