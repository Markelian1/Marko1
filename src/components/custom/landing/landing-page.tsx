// @polsia:user-owned
'use client';

import {
  ArrowUpRight,
  Check,
  Clock3,
  Globe2,
  Heart,
  Layers3,
  Leaf,
  Plus,
  ShieldCheck,
  Sparkles,
} from 'lucide-react';
import { domAnimation, LazyMotion, MotionConfig, useReducedMotion } from 'motion/react';
import * as m from 'motion/react-m';
import Image from 'next/image';
import Link from 'next/link';
import { useId } from 'react';
import {
  landingSectionStyle,
  landingThemeStyle,
  typographyPreset,
} from '@/lib/business/landing/theme';
import type {
  HeroSection,
  LandingConfig,
  LandingSection,
  StepsSection,
} from '@/lib/business/landing/types';
import { NarrativeSteps } from './art-direction-sections';
import { CampaignHero, MinimalCta } from './campaign-sections';
import { CommerceSectionContent } from './commerce-sections';
import { EditorialShowcase } from './editorial-showcase';
import { LandingAction } from './landing-action';
import { LandingImage } from './landing-image';
import { LandingNavbar } from './landing-navbar';
import styles from './landing-page.module.css';
import { PortfolioGallery, ProfileHero } from './personal-sections';
import { PracticalSection } from './practical-sections';
import { TrustSection } from './trust-sections';
import { VisualVariant } from './visual-variants';

const icons = {
  layers: Layers3,
  sparkles: Sparkles,
  clock: Clock3,
  shield: ShieldCheck,
  leaf: Leaf,
  heart: Heart,
  arrow: ArrowUpRight,
  globe: Globe2,
};

function HeroMedia({
  media,
  priority = false,
}: {
  media: HeroSection['media'];
  priority?: boolean;
}) {
  if (!media?.src) return null;
  if (media.kind === 'dashboard')
    return (
      <figure className={styles.productCapture}>
        <div className={styles.captureFrame}>
          <LandingImage
            src={media.src}
            alt={media.alt}
            framing={media.framing}
            fill
            sizes="(max-width: 700px) 100vw, 65vw"
            priority={priority}
            unoptimized
          />
        </div>
        {media.caption && <figcaption>{media.caption}</figcaption>}
      </figure>
    );
  return (
    <figure
      className={`${styles.heroImage} ${media.kind === 'product' ? styles.productImage : ''}`}
    >
      {media.src && (
        <LandingImage
          src={media.src}
          alt={media.alt}
          framing={media.framing}
          fill
          sizes="(max-width: 700px) 100vw, 65vw"
          priority={priority}
          unoptimized
        />
      )}
      {media.caption && (
        <figcaption>
          {media.caption}
          <ArrowUpRight size={16} aria-hidden="true" />
        </figcaption>
      )}
    </figure>
  );
}

function SectionHeading({ title, description }: { title: string; description?: string }) {
  return (
    <div className={styles.sectionHeading}>
      <h2>{title}</h2>
      {description && <p>{description}</p>}
    </div>
  );
}

function StepImage({ media }: { media: NonNullable<StepsSection['media']> }) {
  return (
    <div className={styles.stepImage}>
      <LandingImage
        src={media.src}
        alt={media.alt}
        framing={media.framing}
        fill
        sizes="(max-width: 850px) 100vw, 45vw"
        unoptimized
      />
    </div>
  );
}

function StepsContent({ section }: { section: StepsSection }) {
  const accordionName = useId();
  if (section.variant === 'narrative') return <NarrativeSteps section={section} />;
  return (
    <div className={styles[`steps_${section.variant}`]}>
      <SectionHeading title={section.heading} description={section.description} />
      {section.variant === 'image-accordion' ? (
        <div className={styles.stepsAccordionLayout}>
          {section.media && <StepImage media={section.media} />}
          <ol className={styles.stepAccordionItems}>
            {section.items.map((item, index) => (
              <li key={item.title}>
                <details className={styles.stepDisclosure} name={accordionName} open={index === 0}>
                  <summary>
                    <span className={styles.stepNumber}>{String(index + 1).padStart(2, '0')}</span>
                    <span className={styles.stepTitle}>{item.title}</span>
                    <Plus size={18} aria-hidden="true" />
                  </summary>
                  <p>{item.description}</p>
                </details>
              </li>
            ))}
          </ol>
        </div>
      ) : (
        <ol className={styles.stepItems}>
          {section.items.map((item, index) => (
            <li key={item.title}>
              {section.variant === 'alternating' && item.media && <StepImage media={item.media} />}
              <div className={styles.stepCopy}>
                <span className={styles.stepNumber}>{String(index + 1).padStart(2, '0')}</span>
                <h3>{item.title}</h3>
                <p>{item.description}</p>
              </div>
            </li>
          ))}
        </ol>
      )}
    </div>
  );
}

function SectionContent({ section }: { section: LandingSection }) {
  switch (section.type) {
    case 'hero':
      if (section.variant === 'campaign') return <CampaignHero section={section} />;
      if (section.variant === 'profile') return <ProfileHero section={section} />;
      if (section.variant === 'immersive' || section.variant === 'collage')
        return <VisualVariant section={section} />;
      return (
        <div className={`${styles.hero} ${styles[`hero_${section.variant}`]}`}>
          <div className={styles.heroCopy}>
            {section.eyebrow && (
              <p className={styles.eyebrow}>
                <span />
                {section.eyebrow}
              </p>
            )}
            <h1>{section.title}</h1>
            <p className={styles.heroDescription}>{section.description}</p>
            <div className={styles.actions}>
              <LandingAction action={section.primaryAction} />
              {section.secondaryAction && (
                <LandingAction action={section.secondaryAction} secondary />
              )}
            </div>
            {section.note && (
              <p className={styles.heroNote}>
                <Check size={13} aria-hidden="true" />
                {section.note}
              </p>
            )}
          </div>
          <HeroMedia media={section.media} priority />
        </div>
      );
    case 'features':
      if (section.variant === 'bento' || section.variant === 'tabs')
        return <VisualVariant section={section} />;
      return (
        <div className={`${styles.features} ${styles[`features_${section.variant}`]}`}>
          <SectionHeading title={section.heading} description={section.description} />
          <div className={styles.featureItems}>
            {section.items.map((item) => {
              const Icon = icons[item.icon];
              return (
                <article className={styles.feature} key={item.title}>
                  <span className={styles.featureIcon}>
                    <Icon size={22} strokeWidth={1.5} />
                  </span>
                  <div>
                    <h3>{item.title}</h3>
                    <p>{item.description}</p>
                  </div>
                </article>
              );
            })}
          </div>
        </div>
      );
    case 'gallery':
      if (section.variant === 'mosaic' || section.variant === 'story')
        return <EditorialShowcase section={section} />;
      if (section.variant === 'portfolio') return <PortfolioGallery section={section} />;
      if (section.variant === 'catalog' || section.variant === 'menu')
        return <VisualVariant section={section} />;
      return (
        <div className={`${styles.gallery} ${styles[`gallery_${section.variant}`]}`}>
          <SectionHeading title={section.heading} description={section.description} />
          <div className={styles.galleryItems}>
            {section.items.map((item) => (
              <article className={styles.galleryCard} key={item.title}>
                <div className={styles.galleryImage}>
                  {item.image && (
                    <Image
                      src={item.image}
                      alt={item.alt ?? item.title}
                      fill
                      sizes="(max-width: 650px) 100vw, 40vw"
                      unoptimized
                    />
                  )}
                  {item.tag && <span className={styles.galleryTag}>{item.tag}</span>}
                </div>
                <div className={styles.galleryCaption}>
                  <div>
                    <h3>{item.title}</h3>
                    {item.subtitle && <p>{item.subtitle}</p>}
                  </div>
                  {item.action && <LandingAction action={item.action} secondary compact />}
                </div>
              </article>
            ))}
          </div>
        </div>
      );
    case 'commerce':
      return <CommerceSectionContent section={section} />;
    case 'steps':
      return <StepsContent section={section} />;
    case 'pricing':
      return (
        <div className={`${styles.pricing} ${styles[`pricing_${section.variant}`]}`}>
          <SectionHeading title={section.heading} description={section.description} />
          <div className={styles.pricingItems}>
            {section.plans.map((plan) => (
              <article
                className={`${styles.priceCard} ${plan.featured ? styles.featuredPlan : ''}`}
                key={plan.name}
              >
                <div className={styles.planHeading}>
                  <h3>{plan.name}</h3>
                  {plan.featured && <span>Our recommendation</span>}
                </div>
                <p>{plan.description}</p>
                <div className={styles.price}>
                  {plan.price}
                  {plan.period && <span>{plan.period}</span>}
                </div>
                <ul>
                  {plan.features.map((feature) => (
                    <li key={feature}>
                      <Check size={15} />
                      {feature}
                    </li>
                  ))}
                </ul>
                <LandingAction action={plan.action} secondary={!plan.featured} />
              </article>
            ))}
          </div>
        </div>
      );
    case 'testimonial':
      if (section.variant === 'wall' || section.variant === 'carousel')
        return <TrustSection section={section} />;
      return (
        <div className={`${styles.testimonial} ${styles[`testimonial_${section.variant}`]}`}>
          <span className={styles.quoteMark} aria-hidden="true">
            “
          </span>
          <blockquote>
            <p>{section.quote}</p>
            <footer>
              <span className={styles.authorAvatar}>
                {section.author
                  ?.split(' ')
                  .map((name) => name[0])
                  .slice(0, 2)
                  .join('')}
              </span>
              <div className={styles.authorDetails}>
                <cite>{section.author}</cite>
                <span>{section.role}</span>
              </div>
            </footer>
          </blockquote>
        </div>
      );
    case 'logos':
    case 'stats':
    case 'team':
      return <TrustSection section={section} />;
    case 'contact':
    case 'comparison':
    case 'agenda':
      return <PracticalSection section={section} />;
    case 'faq':
      return (
        <div className={`${styles.faq} ${styles[`faq_${section.variant}`]}`}>
          <SectionHeading title={section.heading} />
          <div className={styles.faqItems}>
            {section.items.map((item) => (
              <details
                className={styles.faqItem}
                key={item.question}
                open={section.variant === 'columns' ? true : undefined}
              >
                <summary>
                  {item.question}
                  <Plus size={18} aria-hidden="true" />
                </summary>
                <p>{item.answer}</p>
              </details>
            ))}
          </div>
        </div>
      );
    case 'cta':
      if (section.variant === 'minimal') return <MinimalCta section={section} />;
      return (
        <div className={`${styles.cta} ${styles[`cta_${section.variant}`]}`}>
          <div>
            <h2>{section.heading}</h2>
            {section.description && <p>{section.description}</p>}
          </div>
          <div className={styles.actions}>
            <LandingAction action={section.action} />
            {section.secondaryAction && (
              <LandingAction action={section.secondaryAction} secondary />
            )}
          </div>
        </div>
      );
  }
}

export function LandingPage({ config }: { config: LandingConfig }) {
  const reduceMotion = useReducedMotion();
  const sections = config.sections.filter((section) => section.enabled);
  const visibleIds = new Set(sections.map((section) => section.id));
  const navigation = config.navigation.filter((item) => visibleIds.has(item.sectionId));
  return (
    <LazyMotion features={domAnimation} strict>
      <MotionConfig reducedMotion="user">
        <div
          className={styles.page}
          style={landingThemeStyle(config.theme)}
          data-palette={config.theme.palette}
          data-typography={typographyPreset(config.theme)}
          data-radius={config.theme.radius}
          data-landing={config.id}
        >
          <LandingNavbar
            brand={config.brand}
            navbar={config.navbar}
            navigation={navigation}
            primaryAction={config.primaryAction}
            homeHref={sections[0] ? `#${sections[0].id}` : '#landing-footer'}
          />
          <div className={styles.sections}>
            {sections.map((section) => (
              <m.section
                key={section.id}
                id={section.id}
                // Keep server-rendered content visible, even without JavaScript.
                // Keyframes start only when a section enters the viewport, once.
                initial={false}
                whileInView={reduceMotion ? undefined : { opacity: [0.7, 1], y: [12, 0] }}
                viewport={{ once: true, amount: 'some' }}
                transition={{ duration: 0.45, ease: [0.22, 1, 0.36, 1] }}
                data-section-id={section.id}
                data-section-type={section.type}
                data-section-variant={section.variant}
                data-composition-width={section.composition?.width}
                data-composition-spacing={section.composition?.spacing}
                data-composition-tone={section.composition?.tone}
                data-composition-display={section.composition?.display}
                style={
                  section.composition
                    ? landingSectionStyle(section.composition, config.theme)
                    : undefined
                }
                className={`${styles.section} ${section.type === 'hero' ? styles.heroSection : ''} ${section.type === 'testimonial' && (section.variant === 'spotlight' || section.variant === 'split') ? styles.quoteSection : ''} ${section.type === 'cta' ? styles.ctaSection : ''}`}
                aria-label={
                  section.type === 'testimonial'
                    ? 'Customer story'
                    : 'heading' in section
                      ? section.heading
                      : section.title
                }
              >
                <SectionContent section={section} />
              </m.section>
            ))}
          </div>
          <footer id="landing-footer" className={styles.footer}>
            <div className={styles.footerTop}>
              <div>
                <Link
                  href={sections[0] ? `#${sections[0].id}` : '#landing-footer'}
                  className={styles.brand}
                >
                  <span className={styles.brandMark}>{config.brand.monogram}</span>
                  {config.brand.name}
                </Link>
                <p>{config.footer.description}</p>
              </div>
              <div className={styles.footerLinks}>
                {config.footer.links
                  .filter(
                    (link) =>
                      !link.href.startsWith('#') ||
                      link.href === '#landing-footer' ||
                      visibleIds.has(link.href.slice(1)),
                  )
                  .map((link) => (
                    <Link key={`${link.label}-${link.href}`} href={link.href}>
                      {link.label}
                      <ArrowUpRight size={13} />
                    </Link>
                  ))}
              </div>
            </div>
            <div className={styles.footerBottom}>
              <span>{config.footer.copyright}</span>
              <span>{config.brand.tagline}</span>
            </div>
          </footer>
        </div>
      </MotionConfig>
    </LazyMotion>
  );
}
