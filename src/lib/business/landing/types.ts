// @polsia:user-owned — serializable contract between an agent and the landing renderer.

export type Palette = 'cobalt' | 'forest' | 'wine';
export type TypographyPreset = 'sans' | 'editorial' | 'rounded';
/**
 * Your own font-family lists, read by the renderer through --land-display / --land-body.
 * Load the files yourself (@font-face in custom-style.css, .woff2 in public/fonts/).
 */
export type LandingFonts = { display: string; body: string };
export type Typography = TypographyPreset | LandingFonts;
export type Radius = 'sharp' | 'soft' | 'round';
export type Action = { label: string; href: string };
export type MediaFit = 'cover' | 'contain';
export type MediaPosition = { x: number; y: number };
export type MediaFraming = {
  fit?: MediaFit;
  position?: MediaPosition;
  mobile?: {
    src: string;
    fit?: MediaFit;
    position?: MediaPosition;
  };
};
export type NavbarVariant = 'classic' | 'centered' | 'floating' | 'minimal';
export type LandingNavbarConfig = {
  variant: NavbarVariant;
  labels?: { navigation?: string; openMenu?: string; closeMenu?: string };
};
export type LandingColors = { primary: string; accent: string; background: string; text: string };
export type LandingTheme = {
  /** A preset to inherit from; optional once all four `colors` are set. */
  palette?: Palette;
  typography: Typography;
  radius: Radius;
  colors?: Partial<LandingColors>;
};
export type SectionComposition = {
  width?: 'narrow' | 'wide' | 'full';
  spacing?: 'tight' | 'default' | 'generous';
  tone?: 'surface' | 'accent' | 'inverse';
  display?: 'standard' | 'large' | 'monumental';
};
export type SectionBase = {
  id: string;
  enabled: boolean;
  composition?: SectionComposition;
};
export type LandingMedia = {
  src: string;
  alt: string;
  caption?: string;
  framing?: MediaFraming;
};
export type HeroSection = SectionBase & {
  type: 'hero';
  variant: 'split' | 'centered' | 'cover' | 'immersive' | 'collage' | 'profile' | 'campaign';
  eyebrow?: string;
  title: string;
  description: string;
  primaryAction: Action;
  secondaryAction?: Action;
  note?: string;
  /** Centered/profile can omit media. Dashboard accepts a real screenshot, never a mock UI. */
  media?: {
    kind: 'image' | 'dashboard' | 'product';
    src?: string;
    alt: string;
    caption?: string;
    framing?: MediaFraming;
  };
  /** One or two additional images for the collage variant. */
  collage?: LandingMedia[];
};
export type FeatureIcon =
  | 'layers'
  | 'sparkles'
  | 'clock'
  | 'shield'
  | 'leaf'
  | 'heart'
  | 'arrow'
  | 'globe';
export type FeaturesSection = SectionBase & {
  type: 'features';
  variant: 'grid' | 'split' | 'list' | 'bento' | 'tabs';
  heading: string;
  description?: string;
  items: { title: string; description: string; icon: FeatureIcon; media?: LandingMedia }[];
};
export type GallerySection = SectionBase & {
  type: 'gallery';
  variant: 'cards' | 'editorial' | 'catalog' | 'menu' | 'portfolio' | 'mosaic' | 'story';
  heading: string;
  description?: string;
  items: {
    title: string;
    subtitle?: string;
    image?: string;
    alt?: string;
    tag?: string;
    action?: Action;
    price?: string;
    category?: string;
  }[];
};
export type CommerceSection = SectionBase & {
  type: 'commerce';
  variant: 'grid' | 'featured' | 'compact' | 'rail' | 'lookbook';
  heading: string;
  description?: string;
  notice?: string;
  filter?: { label: string; allLabel: string };
  detailsLabel?: string;
  /** Localized scrolling hint displayed by the rail layout. */
  scrollLabel?: string;
  items: {
    id: string;
    title: string;
    image: LandingMedia;
    price?: string;
    category?: string;
    description?: string;
    details?: { label: string; value: string }[];
    action?: Action;
  }[];
};
export type StepsSection = SectionBase & {
  type: 'steps';
  variant: 'timeline' | 'cards' | 'vertical' | 'image-accordion' | 'alternating' | 'narrative';
  heading: string;
  description?: string;
  /** Required for image-accordion. */
  media?: LandingMedia;
  items: {
    title: string;
    description: string;
    /** Required on every item for alternating. */
    media?: LandingMedia;
  }[];
};
export type PricingSection = SectionBase & {
  type: 'pricing';
  variant: 'cards' | 'compact';
  heading: string;
  description?: string;
  plans: {
    name: string;
    description: string;
    price: string;
    period?: string;
    features: string[];
    action: Action;
    featured?: boolean;
  }[];
};
export type TestimonialSection = SectionBase & {
  type: 'testimonial';
  variant: 'spotlight' | 'split' | 'wall' | 'carousel';
  quote?: string;
  author?: string;
  role?: string;
  heading?: string;
  description?: string;
  items?: { quote: string; author: string; role?: string; portrait?: LandingMedia }[];
};
export type LogosSection = SectionBase & {
  type: 'logos';
  variant: 'band' | 'grid';
  heading: string;
  description?: string;
  items: { name: string; image?: string; href?: string }[];
};
export type StatsSection = SectionBase & {
  type: 'stats';
  variant: 'inline' | 'visual';
  heading: string;
  description?: string;
  items: { value: string; label: string; description?: string }[];
  media?: LandingMedia;
};
export type TeamSection = SectionBase & {
  type: 'team';
  variant: 'founder' | 'grid';
  heading: string;
  description?: string;
  people: { name: string; role: string; bio?: string; portrait?: LandingMedia; action?: Action }[];
};
export type ContactSection = SectionBase & {
  type: 'contact';
  variant: 'details' | 'map';
  heading: string;
  description?: string;
  address?: string;
  email?: string;
  phone?: string;
  hours?: { label: string; value: string }[];
  action?: Action;
  /** A supplied map image and a real directions link; no API key or invented map. */
  map?: LandingMedia & { href: string };
};
export type ComparisonSection = SectionBase & {
  type: 'comparison';
  variant: 'table' | 'before-after';
  heading: string;
  description?: string;
  columns?: { label: string; highlighted?: boolean }[];
  rows?: { label: string; values: string[] }[];
  before?: LandingMedia & { label: string };
  after?: LandingMedia & { label: string };
};
export type AgendaSection = SectionBase & {
  type: 'agenda';
  variant: 'schedule' | 'curriculum';
  heading: string;
  description?: string;
  items: {
    title: string;
    description?: string;
    label?: string;
    time?: string;
    duration?: string;
    action?: Action;
  }[];
};
export type FaqSection = SectionBase & {
  type: 'faq';
  variant: 'accordion' | 'columns';
  heading: string;
  items: { question: string; answer: string }[];
};
export type CtaSection = SectionBase & {
  type: 'cta';
  variant: 'banner' | 'centered' | 'minimal';
  heading: string;
  description?: string;
  action: Action;
  secondaryAction?: Action;
};
export type LandingSection =
  | HeroSection
  | FeaturesSection
  | GallerySection
  | CommerceSection
  | StepsSection
  | PricingSection
  | TestimonialSection
  | LogosSection
  | StatsSection
  | TeamSection
  | ContactSection
  | ComparisonSection
  | AgendaSection
  | FaqSection
  | CtaSection;
export type SectionType = LandingSection['type'];
export type LandingConfig = {
  id: string;
  theme: LandingTheme;
  brand: { name: string; monogram: string; tagline: string };
  /** Omit to preserve the classic navbar in existing compositions. */
  navbar?: LandingNavbarConfig;
  navigation: { label: string; sectionId: string }[];
  primaryAction: Action;
  footer: { description: string; links: Action[]; copyright: string };
  sections: LandingSection[];
};
