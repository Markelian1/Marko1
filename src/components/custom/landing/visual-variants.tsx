// @polsia:user-owned
'use client';

import {
  ArrowUpRight,
  Clock3,
  Globe2,
  Heart,
  Layers3,
  Leaf,
  ShieldCheck,
  Sparkles,
} from 'lucide-react';
import Image from 'next/image';
import { type KeyboardEvent, useEffect, useId, useRef, useState } from 'react';
import type {
  FeaturesSection,
  GallerySection,
  HeroSection,
  LandingMedia,
} from '@/lib/business/landing/types';
import { LandingAction } from './landing-action';
import styles from './visual-variants.module.css';

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

function Heading({ heading, description }: { heading: string; description?: string }) {
  return (
    <header className={styles.heading}>
      <h2>{heading}</h2>
      {description && <p>{description}</p>}
    </header>
  );
}

function Photo({
  media,
  className = '',
  priority = false,
}: {
  media: LandingMedia;
  className?: string;
  priority?: boolean;
}) {
  return (
    <figure className={`${styles.photo} ${className}`}>
      <Image
        src={media.src}
        alt={media.alt}
        fill
        sizes="(max-width: 700px) 90vw, 50vw"
        priority={priority}
        unoptimized
      />
      {media.caption && <figcaption>{media.caption}</figcaption>}
    </figure>
  );
}

function HeroCopy({ section }: { section: HeroSection }) {
  return (
    <div className={styles.heroCopy}>
      {section.eyebrow && <p className={styles.eyebrow}>{section.eyebrow}</p>}
      <h1>{section.title}</h1>
      <p className={styles.heroDescription}>{section.description}</p>
      <div className={styles.actions}>
        <LandingAction action={section.primaryAction} />
        {section.secondaryAction && <LandingAction action={section.secondaryAction} secondary />}
      </div>
      {section.note && <p className={styles.heroNote}>{section.note}</p>}
    </div>
  );
}

function Hero({ section }: { section: HeroSection }) {
  const [firstDetail, secondDetail] = section.collage ?? [];
  if (section.variant === 'immersive') {
    return (
      <div className={styles.immersive}>
        {section.media?.src && (
          <Image
            className={styles.immersiveImage}
            src={section.media.src}
            alt={section.media.alt}
            fill
            sizes="100vw"
            priority
            unoptimized
          />
        )}
        <div className={styles.immersiveContent}>
          <HeroCopy section={section} />
        </div>
        {section.media?.caption && (
          <p className={styles.immersiveCaption}>{section.media.caption}</p>
        )}
      </div>
    );
  }
  return (
    <div className={styles.collageHero}>
      <HeroCopy section={section} />
      <div className={styles.collage} data-count={(section.collage?.length ?? 0) + 1}>
        {section.media?.src && (
          <Photo media={{ ...section.media, src: section.media.src }} priority />
        )}
        {firstDetail && <Photo media={firstDetail} />}
        {secondDetail && <Photo media={secondDetail} />}
      </div>
    </div>
  );
}

function Bento({ section }: { section: FeaturesSection }) {
  return (
    <div>
      <Heading heading={section.heading} description={section.description} />
      <div className={styles.bento}>
        {section.items.map((item) => {
          const Icon = icons[item.icon];
          return (
            <article className={styles.bentoCard} key={item.title}>
              <div className={styles.bentoCopy}>
                <Icon className={styles.featureIcon} size={25} aria-hidden="true" />
                <h3>{item.title}</h3>
                <p>{item.description}</p>
              </div>
              {item.media && <Photo media={item.media} />}
            </article>
          );
        })}
      </div>
    </div>
  );
}

function FeatureTabs({ section }: { section: FeaturesSection }) {
  const id = useId();
  const [selected, setSelected] = useState(0);
  const [enhanced, setEnhanced] = useState(false);
  const tabs = useRef<(HTMLButtonElement | null)[]>([]);
  const active = Math.min(selected, section.items.length - 1);

  // The initial HTML exposes every benefit; only hydrated tabs hide inactive panels.
  useEffect(() => setEnhanced(true), []);

  function navigate(event: KeyboardEvent<HTMLButtonElement>, index: number) {
    let next: number;
    switch (event.key) {
      case 'ArrowRight':
        next = (index + 1) % section.items.length;
        break;
      case 'ArrowLeft':
        next = (index - 1 + section.items.length) % section.items.length;
        break;
      case 'Home':
        next = 0;
        break;
      case 'End':
        next = section.items.length - 1;
        break;
      default:
        return;
    }
    event.preventDefault();
    setSelected(next);
    tabs.current[next]?.focus();
  }

  return (
    <div className={styles.tabs}>
      <Heading heading={section.heading} description={section.description} />
      <div
        className={styles.tabList}
        role="tablist"
        aria-label={section.heading}
        hidden={!enhanced}
      >
        {section.items.map((item, index) => {
          const Icon = icons[item.icon];
          return (
            <button
              key={item.title}
              ref={(node) => {
                tabs.current[index] = node;
              }}
              type="button"
              role="tab"
              id={`${id}-tab-${index}`}
              aria-controls={`${id}-panel-${index}`}
              aria-selected={active === index}
              tabIndex={active === index ? 0 : -1}
              onClick={() => setSelected(index)}
              onKeyDown={(event) => navigate(event, index)}
            >
              <Icon size={18} aria-hidden="true" />
              {item.title}
            </button>
          );
        })}
      </div>
      <div className={styles.tabPanels}>
        {section.items.map((item, index) => (
          <div
            className={styles.tabPanel}
            key={item.title}
            id={`${id}-panel-${index}`}
            role="tabpanel"
            aria-labelledby={`${id}-tab-${index}`}
            tabIndex={enhanced ? 0 : undefined}
            hidden={enhanced && active !== index}
          >
            <div className={styles.tabCopy}>
              <h3>{item.title}</h3>
              <p>{item.description}</p>
            </div>
            {item.media && <Photo media={item.media} />}
          </div>
        ))}
      </div>
    </div>
  );
}

function Catalog({ section }: { section: GallerySection }) {
  return (
    <div>
      <Heading heading={section.heading} description={section.description} />
      <div className={styles.catalog}>
        {section.items.map((item) => (
          <article className={styles.catalogItem} key={item.title}>
            {item.image && <Photo media={{ src: item.image, alt: item.alt ?? '' }} />}
            <div className={styles.catalogCopy}>
              {item.tag && <p className={styles.tag}>{item.tag}</p>}
              <div className={styles.catalogTitle}>
                <h3>{item.title}</h3>
                {item.price && <span className={styles.price}>{item.price}</span>}
              </div>
              {item.subtitle && <p>{item.subtitle}</p>}
              {item.action && (
                <div className={styles.itemAction}>
                  <LandingAction action={item.action} secondary compact />
                </div>
              )}
            </div>
          </article>
        ))}
      </div>
    </div>
  );
}

function Menu({ section }: { section: GallerySection }) {
  const groups = new Map<string, GallerySection['items']>();
  for (const item of section.items) {
    const category = item.category ?? '';
    const group = groups.get(category);
    if (group) group.push(item);
    else groups.set(category, [item]);
  }

  return (
    <div className={styles.menu}>
      <Heading heading={section.heading} description={section.description} />
      <div className={styles.menuGroups}>
        {[...groups].map(([category, items]) => (
          <div className={styles.menuGroup} key={category}>
            {category && <h3>{category}</h3>}
            <ul>
              {items.map((item) => (
                <li className={styles.menuRow} key={item.title}>
                  {item.image && <Photo media={{ src: item.image, alt: item.alt ?? '' }} />}
                  <div className={styles.menuCopy}>
                    <div className={styles.menuTitle}>
                      <h4>{item.title}</h4>
                      {item.price && <span className={styles.price}>{item.price}</span>}
                    </div>
                    {item.subtitle && <p>{item.subtitle}</p>}
                    {item.tag && <span className={styles.menuTag}>{item.tag}</span>}
                    {item.action && (
                      <div className={styles.itemAction}>
                        <LandingAction action={item.action} secondary compact />
                      </div>
                    )}
                  </div>
                </li>
              ))}
            </ul>
          </div>
        ))}
      </div>
    </div>
  );
}

export function VisualVariant({
  section,
}: {
  section: HeroSection | FeaturesSection | GallerySection;
}) {
  switch (section.type) {
    case 'hero':
      return <Hero section={section} />;
    case 'features':
      return section.variant === 'tabs' ? (
        <FeatureTabs section={section} />
      ) : (
        <Bento section={section} />
      );
    case 'gallery':
      return section.variant === 'menu' ? (
        <Menu section={section} />
      ) : (
        <Catalog section={section} />
      );
  }
}
