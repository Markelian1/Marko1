// @polsia:user-owned — validate the configured landing before rendering.
import { z } from 'zod';
import type { LandingConfig } from './types';

const text = z.string().trim().min(1).max(2000);
const color = z.string().regex(/^#(?:[0-9a-f]{3}|[0-9a-f]{6})$/i, 'Use #RGB or #RRGGBB.');
// A plain font-family list: names, quotes, commas, hyphens. No other CSS syntax,
// so a value can never break out of the inline style that carries it.
const fontFamily = z
  .string()
  .trim()
  .min(1)
  .max(200)
  .regex(/^[\p{L}\p{N} _"',-]+$/u, 'Use a comma-separated list of font-family names.');
const colorKeys = ['primary', 'accent', 'background', 'text'] as const;
const id = z.string().regex(/^[a-z][a-z0-9-]{0,63}$/);
const href = z
  .string()
  .max(2000)
  .refine((value) => {
    if (/[\s\\]/.test(value) || Array.from(value).some((character) => character.charCodeAt(0) < 32))
      return false;
    return (
      /^#[a-z][a-z0-9-]*$/i.test(value) ||
      /^\/(?!\/)/.test(value) ||
      /^https:\/\/[^/]+/.test(value) ||
      /^mailto:[^@]+@[^@]+$/.test(value)
    );
  }, 'Use a section anchor, local path, HTTPS URL or email address.');
const image = z
  .string()
  .max(2000)
  .refine((value) => /^\/(?!\/)[^\s\\]+$/.test(value) || /^https:\/\/[^\s\\]+$/.test(value));
const action = z.object({ label: text, href }).strict();
const position = z
  .object({ x: z.number().min(0).max(100), y: z.number().min(0).max(100) })
  .strict();
const framing = z
  .object({
    fit: z.enum(['cover', 'contain']).optional(),
    position: position.optional(),
    mobile: z
      .object({
        src: image,
        fit: z.enum(['cover', 'contain']).optional(),
        position: position.optional(),
      })
      .strict()
      .optional(),
  })
  .strict();
const stepMedia = z.object({ src: image, alt: text, framing: framing.optional() }).strict();
const media = z
  .object({ src: image, alt: text, caption: text.optional(), framing: framing.optional() })
  .strict();
const composition = z
  .object({
    width: z.enum(['narrow', 'wide', 'full']).optional(),
    spacing: z.enum(['tight', 'default', 'generous']).optional(),
    tone: z.enum(['surface', 'accent', 'inverse']).optional(),
    display: z.enum(['standard', 'large', 'monumental']).optional(),
  })
  .strict();
const base = { id, enabled: z.boolean(), composition: composition.optional() };
const heading = { heading: text, description: text.optional() };
const section = z.discriminatedUnion('type', [
  z
    .object({
      ...base,
      type: z.literal('hero'),
      variant: z.enum([
        'split',
        'centered',
        'cover',
        'immersive',
        'collage',
        'profile',
        'campaign',
      ]),
      eyebrow: text.optional(),
      title: text,
      description: text,
      primaryAction: action,
      secondaryAction: action.optional(),
      note: text.optional(),
      collage: z.array(media).min(1).max(2).optional(),
      media: z
        .object({
          kind: z.enum(['image', 'dashboard', 'product']),
          src: image.optional(),
          alt: text,
          caption: text.optional(),
          framing: framing.optional(),
        })
        .strict()
        .optional(),
    })
    .strict(),
  z
    .object({
      ...base,
      type: z.literal('features'),
      variant: z.enum(['grid', 'split', 'list', 'bento', 'tabs']),
      ...heading,
      items: z
        .array(
          z
            .object({
              title: text,
              description: text,
              media: media.optional(),
              icon: z.enum([
                'layers',
                'sparkles',
                'clock',
                'shield',
                'leaf',
                'heart',
                'arrow',
                'globe',
              ]),
            })
            .strict(),
        )
        .min(1)
        .max(12),
    })
    .strict(),
  z
    .object({
      ...base,
      type: z.literal('gallery'),
      variant: z.enum(['cards', 'editorial', 'catalog', 'menu', 'portfolio', 'mosaic', 'story']),
      ...heading,
      items: z
        .array(
          z
            .object({
              title: text,
              subtitle: text.optional(),
              image: image.optional(),
              alt: text.optional(),
              tag: text.optional(),
              price: text.optional(),
              category: text.optional(),
              action: action.optional(),
            })
            .strict(),
        )
        .min(1)
        .max(12),
    })
    .strict(),
  z
    .object({
      ...base,
      type: z.literal('commerce'),
      variant: z.enum(['grid', 'featured', 'compact', 'rail', 'lookbook']),
      ...heading,
      notice: text.optional(),
      filter: z.object({ label: text, allLabel: text }).strict().optional(),
      detailsLabel: text.optional(),
      scrollLabel: text.optional(),
      items: z
        .array(
          z
            .object({
              id,
              title: text,
              image: media,
              price: text.optional(),
              category: text.optional(),
              description: text.optional(),
              details: z
                .array(z.object({ label: text, value: text }).strict())
                .min(1)
                .max(12)
                .optional(),
              action: action.optional(),
            })
            .strict(),
        )
        .min(1)
        .max(24),
    })
    .strict(),
  z
    .object({
      ...base,
      type: z.literal('steps'),
      variant: z.enum([
        'timeline',
        'cards',
        'vertical',
        'image-accordion',
        'alternating',
        'narrative',
      ]),
      ...heading,
      media: stepMedia.optional(),
      items: z
        .array(z.object({ title: text, description: text, media: stepMedia.optional() }).strict())
        .min(1)
        .max(8),
    })
    .strict(),
  z
    .object({
      ...base,
      type: z.literal('pricing'),
      variant: z.enum(['cards', 'compact']),
      ...heading,
      plans: z
        .array(
          z
            .object({
              name: text,
              description: text,
              price: text,
              period: text.optional(),
              features: z.array(text).max(20),
              action,
              featured: z.boolean().optional(),
            })
            .strict(),
        )
        .min(1)
        .max(6),
    })
    .strict(),
  z
    .object({
      ...base,
      type: z.literal('testimonial'),
      variant: z.enum(['spotlight', 'split', 'wall', 'carousel']),
      quote: text.optional(),
      author: text.optional(),
      role: text.optional(),
      heading: text.optional(),
      description: text.optional(),
      items: z
        .array(
          z
            .object({
              quote: text,
              author: text,
              role: text.optional(),
              portrait: media.optional(),
            })
            .strict(),
        )
        .min(1)
        .max(12)
        .optional(),
    })
    .strict(),
  z
    .object({
      ...base,
      type: z.literal('logos'),
      variant: z.enum(['band', 'grid']),
      ...heading,
      items: z
        .array(z.object({ name: text, image: image.optional(), href: href.optional() }).strict())
        .min(1)
        .max(24),
    })
    .strict(),
  z
    .object({
      ...base,
      type: z.literal('stats'),
      variant: z.enum(['inline', 'visual']),
      ...heading,
      items: z
        .array(z.object({ value: text, label: text, description: text.optional() }).strict())
        .min(1)
        .max(6),
      media: media.optional(),
    })
    .strict(),
  z
    .object({
      ...base,
      type: z.literal('team'),
      variant: z.enum(['founder', 'grid']),
      ...heading,
      people: z
        .array(
          z
            .object({
              name: text,
              role: text,
              bio: text.optional(),
              portrait: media.optional(),
              action: action.optional(),
            })
            .strict(),
        )
        .min(1)
        .max(12),
    })
    .strict(),
  z
    .object({
      ...base,
      type: z.literal('contact'),
      variant: z.enum(['details', 'map']),
      ...heading,
      address: text.optional(),
      email: z.string().trim().email().max(320).optional(),
      phone: z
        .string()
        .trim()
        .min(3)
        .max(40)
        .regex(/^\+?[\d\s().-]+$/)
        .refine((value) => /\d/.test(value))
        .optional(),
      hours: z
        .array(z.object({ label: text, value: text }).strict())
        .min(1)
        .max(14)
        .optional(),
      action: action.optional(),
      map: media
        .extend({
          href: href.refine(
            (value) => value.startsWith('https://'),
            'Use an HTTPS directions URL.',
          ),
        })
        .strict()
        .optional(),
    })
    .strict(),
  z
    .object({
      ...base,
      type: z.literal('comparison'),
      variant: z.enum(['table', 'before-after']),
      ...heading,
      columns: z
        .array(z.object({ label: text, highlighted: z.boolean().optional() }).strict())
        .min(2)
        .max(4)
        .optional(),
      rows: z
        .array(z.object({ label: text, values: z.array(text).min(2).max(4) }).strict())
        .min(1)
        .max(12)
        .optional(),
      before: media.extend({ label: text }).strict().optional(),
      after: media.extend({ label: text }).strict().optional(),
    })
    .strict(),
  z
    .object({
      ...base,
      type: z.literal('agenda'),
      variant: z.enum(['schedule', 'curriculum']),
      ...heading,
      items: z
        .array(
          z
            .object({
              title: text,
              description: text.optional(),
              label: text.optional(),
              time: text.optional(),
              duration: text.optional(),
              action: action.optional(),
            })
            .strict(),
        )
        .min(1)
        .max(20),
    })
    .strict(),
  z
    .object({
      ...base,
      type: z.literal('faq'),
      variant: z.enum(['accordion', 'columns']),
      heading: text,
      items: z
        .array(z.object({ question: text, answer: text }).strict())
        .min(1)
        .max(16),
    })
    .strict(),
  z
    .object({
      ...base,
      type: z.literal('cta'),
      variant: z.enum(['banner', 'centered', 'minimal']),
      ...heading,
      action,
      secondaryAction: action.optional(),
    })
    .strict(),
]);

export const landingConfigSchema: z.ZodType<LandingConfig> = z
  .object({
    id,
    theme: z
      .object({
        palette: z.enum(['cobalt', 'forest', 'wine']).optional(),
        typography: z.union([
          z.enum(['sans', 'editorial', 'rounded']),
          z.object({ display: fontFamily, body: fontFamily }).strict(),
        ]),
        radius: z.enum(['sharp', 'soft', 'round']),
        colors: z
          .object({ primary: color, accent: color, background: color, text: color })
          .partial()
          .strict()
          .optional(),
      })
      .strict()
      .refine(
        (theme) =>
          theme.palette !== undefined ||
          colorKeys.every((key) => theme.colors?.[key] !== undefined),
        { message: 'Set theme.palette or all four theme.colors.', path: ['palette'] },
      ),
    brand: z.object({ name: text, monogram: text, tagline: text }).strict(),
    navbar: z
      .object({
        variant: z.enum(['classic', 'centered', 'floating', 'minimal']),
        labels: z
          .object({
            navigation: text.optional(),
            openMenu: text.optional(),
            closeMenu: text.optional(),
          })
          .strict()
          .optional(),
      })
      .strict()
      .optional(),
    navigation: z.array(z.object({ label: text, sectionId: id }).strict()).max(8),
    primaryAction: action,
    footer: z
      .object({ description: text, links: z.array(action).max(12), copyright: text })
      .strict(),
    sections: z.array(section).min(1).max(20),
  })
  .strict()
  .superRefine((config, context) => {
    const ids = new Set<string>();
    config.sections.forEach((item, index) => {
      if (ids.has(item.id))
        context.addIssue({
          code: 'custom',
          path: ['sections', index, 'id'],
          message: 'Section IDs must be unique.',
        });
      ids.add(item.id);
      const issue = (path: (string | number)[], message: string) =>
        context.addIssue({ code: 'custom', path: ['sections', index, ...path], message });
      if (item.type === 'hero') {
        if (!item.media && item.variant !== 'centered' && item.variant !== 'profile')
          issue(['media'], 'This hero layout needs supplied media.');
        if (item.media && !item.media.src)
          issue(
            ['media', 'src'],
            'Supply a real image or product capture; invented dashboard UI is not supported.',
          );
        if (item.variant === 'profile' && item.media && item.media.kind !== 'image')
          issue(['media', 'kind'], 'A profile portrait must be a supplied image of the person.');
        if (
          (item.variant === 'immersive' || item.variant === 'collage') &&
          (!item.media?.src || item.media.kind === 'dashboard')
        )
          issue(['media'], 'Immersive and collage heroes need supplied image or product media.');
        if (item.variant === 'collage' && !item.collage)
          issue(['collage'], 'Collage heroes need one or two additional images.');
        if (item.media?.kind === 'dashboard' && item.media.framing) {
          const crop = item.media.framing;
          if (
            crop.fit === 'cover' ||
            crop.position ||
            crop.mobile?.fit === 'cover' ||
            crop.mobile?.position
          )
            issue(
              ['media', 'framing'],
              'Product captures may use contain framing only; decorative cropping is not supported.',
            );
        }
      }
      if (item.type === 'features' && item.variant === 'tabs')
        item.items.forEach((entry, entryIndex) => {
          if (!entry.media) issue(['items', entryIndex, 'media'], 'Every feature tab needs media.');
        });
      if (item.type === 'gallery')
        item.items.forEach((entry, entryIndex) => {
          if (item.variant !== 'menu' && item.variant !== 'portfolio' && !entry.image)
            issue(
              ['items', entryIndex, 'image'],
              'This gallery layout needs an image for every item.',
            );
          if (entry.image && !entry.alt)
            issue(['items', entryIndex, 'alt'], 'Supplied images need descriptive alt text.');
          if (item.variant === 'portfolio' && entry.alt && !entry.image)
            issue(['items', entryIndex, 'image'], 'Alt text needs its supplied project image.');
        });
      if (item.type === 'commerce') {
        const productIds = new Set<string>();
        item.items.forEach((entry, entryIndex) => {
          if (productIds.has(entry.id))
            issue(['items', entryIndex, 'id'], 'Product IDs must be unique within a collection.');
          productIds.add(entry.id);
        });
      }
      if (item.type === 'testimonial') {
        if (item.variant === 'wall' || item.variant === 'carousel') {
          if (!item.items)
            issue(['items'], 'Quote collections need attributable testimonial items.');
        } else {
          for (const field of ['quote', 'author', 'role'] as const)
            if (!item[field]) issue([field], 'Single testimonials need quote, author and role.');
        }
      }
      if (item.type === 'stats' && item.variant === 'visual' && !item.media)
        issue(['media'], 'Visual statistics need supplied media.');
      if (item.type === 'contact') {
        if (item.variant === 'map' && !item.map)
          issue(['map'], 'Map contact sections need a supplied map image and directions URL.');
        if (
          !item.address &&
          !item.email &&
          !item.phone &&
          !item.hours &&
          !item.action &&
          !(item.variant === 'map' && item.map)
        )
          issue(['address'], 'Provide contact details, opening hours or a working contact action.');
      }
      if (item.type === 'comparison') {
        if (item.variant === 'table') {
          if (!item.columns) issue(['columns'], 'Comparison tables need named columns.');
          if (!item.rows) issue(['rows'], 'Comparison tables need criteria rows.');
          item.rows?.forEach((row, rowIndex) => {
            if (item.columns && row.values.length !== item.columns.length)
              issue(['rows', rowIndex, 'values'], 'Supply one value for each comparison column.');
          });
        } else {
          if (!item.before) issue(['before'], 'Before/after comparisons need both labeled images.');
          if (!item.after) issue(['after'], 'Before/after comparisons need both labeled images.');
        }
      }
      if (item.type === 'steps') {
        if (item.variant === 'image-accordion' && !item.media)
          context.addIssue({
            code: 'custom',
            path: ['sections', index, 'media'],
            message: 'Image-accordion steps need section media with src and alt.',
          });
        if (item.variant === 'alternating')
          item.items.forEach((step, stepIndex) => {
            if (!step.media)
              context.addIssue({
                code: 'custom',
                path: ['sections', index, 'items', stepIndex, 'media'],
                message: 'Every alternating step needs media with src and alt.',
              });
          });
        if (item.variant === 'narrative' && !item.media)
          context.addIssue({
            code: 'custom',
            path: ['sections', index, 'media'],
            message: 'Narrative steps need fallback media for chapters without an image.',
          });
      }
    });
  });
