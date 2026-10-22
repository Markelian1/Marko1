// @polsia:user-owned
'use client';

import { ArrowLeft, ArrowRight } from 'lucide-react';
import Image from 'next/image';
import Link from 'next/link';
import { type KeyboardEvent, useEffect, useId, useState } from 'react';
import { Button } from '@/components/ui/button';
import type {
  LandingMedia,
  LogosSection,
  StatsSection,
  TeamSection,
  TestimonialSection,
} from '@/lib/business/landing/types';
import { LandingAction } from './landing-action';
import styles from './trust-sections.module.css';

function Heading({ heading, description }: { heading?: string; description?: string }) {
  if (!heading && !description) return null;
  return (
    <div className={styles.heading}>
      {heading && <h2>{heading}</h2>}
      {description && <p>{description}</p>}
    </div>
  );
}

function Photo({ media, portrait = false }: { media: LandingMedia; portrait?: boolean }) {
  return (
    <figure className={styles.photo}>
      <div className={`${styles.photoFrame} ${portrait ? styles.portraitFrame : ''}`}>
        <Image
          src={media.src}
          alt={media.alt}
          fill
          sizes="(max-width: 700px) 100vw, 45vw"
          unoptimized
        />
      </div>
      {media.caption && <figcaption>{media.caption}</figcaption>}
    </figure>
  );
}

function Logos({ section }: { section: LogosSection }) {
  return (
    <div className={section.variant === 'band' ? styles.logosBand : styles.logosGrid}>
      <Heading heading={section.heading} description={section.description} />
      <ul className={styles.logos}>
        {section.items.map((item) => {
          const mark = item.image ? (
            <span className={styles.logoImage}>
              <Image src={item.image} alt={item.name} fill sizes="180px" unoptimized />
            </span>
          ) : (
            <span className={styles.logoName}>{item.name}</span>
          );
          return (
            <li key={item.name} className={styles.logo}>
              {item.href ? (
                <Link href={item.href} className={styles.logoLink}>
                  {mark}
                </Link>
              ) : (
                mark
              )}
            </li>
          );
        })}
      </ul>
    </div>
  );
}

function Stats({ section }: { section: StatsSection }) {
  return (
    <div className={section.variant === 'visual' ? styles.statsVisual : styles.statsInline}>
      <div className={styles.statsCopy}>
        <Heading heading={section.heading} description={section.description} />
        <dl className={styles.stats}>
          {section.items.map((item) => (
            <div className={styles.stat} key={item.label}>
              <dt>{item.label}</dt>
              <dd className={styles.statValue}>{item.value}</dd>
              {item.description && <dd className={styles.statDescription}>{item.description}</dd>}
            </div>
          ))}
        </dl>
      </div>
      {section.variant === 'visual' && section.media && <Photo media={section.media} portrait />}
    </div>
  );
}

function Team({ section }: { section: TeamSection }) {
  const founder = section.people[0];
  if (section.variant === 'founder' && founder) {
    return (
      <div className={`${styles.founder} ${founder.portrait ? styles.founderWithPortrait : ''}`}>
        {founder.portrait && <Photo media={founder.portrait} portrait />}
        <div className={styles.founderLetter}>
          <Heading heading={section.heading} description={section.description} />
          {founder.bio && <p className={styles.founderBio}>{founder.bio}</p>}
          <div className={styles.signature}>
            <h3>{founder.name}</h3>
            <p>{founder.role}</p>
          </div>
          {founder.action && <LandingAction action={founder.action} secondary compact />}
        </div>
      </div>
    );
  }
  return (
    <div className={styles.team}>
      <Heading heading={section.heading} description={section.description} />
      <ul className={styles.people}>
        {section.people.map((person) => (
          <li className={styles.person} key={person.name}>
            {person.portrait && <Photo media={person.portrait} portrait />}
            <div className={styles.personCopy}>
              <h3>{person.name}</h3>
              <p className={styles.personRole}>{person.role}</p>
              {person.bio && <p className={styles.personBio}>{person.bio}</p>}
              {person.action && <LandingAction action={person.action} secondary compact />}
            </div>
          </li>
        ))}
      </ul>
    </div>
  );
}

type Quote = NonNullable<TestimonialSection['items']>[number];

function QuoteContent({ item }: { item: Quote }) {
  return (
    <>
      <blockquote>{item.quote}</blockquote>
      <figcaption className={styles.attribution}>
        {item.portrait && (
          <span className={styles.quotePortrait}>
            <Image src={item.portrait.src} alt={item.portrait.alt} fill sizes="48px" unoptimized />
          </span>
        )}
        <span>
          <strong>{item.author}</strong>
          {item.role && <span className={styles.quoteRole}>{item.role}</span>}
        </span>
      </figcaption>
    </>
  );
}

function TestimonialCarousel({ section, items }: { section: TestimonialSection; items: Quote[] }) {
  const slidesId = useId();
  const [enhanced, setEnhanced] = useState(false);
  const [selection, setSelection] = useState(0);
  const activeIndex = selection % Math.max(items.length, 1);
  const activeItem = items[activeIndex];

  // The initial HTML is a readable collection, including when JavaScript is disabled.
  useEffect(() => setEnhanced(true), []);

  function select(index: number) {
    setSelection((index + items.length) % items.length);
  }

  function onControlKeyDown(event: KeyboardEvent<HTMLButtonElement>) {
    if (event.altKey || event.ctrlKey || event.metaKey) return;
    switch (event.key) {
      case 'ArrowLeft':
        select(activeIndex - 1);
        break;
      case 'ArrowRight':
        select(activeIndex + 1);
        break;
      case 'Home':
        select(0);
        break;
      case 'End':
        select(items.length - 1);
        break;
      default:
        return;
    }
    event.preventDefault();
  }

  return (
    <section
      className={styles.carousel}
      aria-label={section.heading || 'Customer stories'}
      aria-roledescription="carousel"
    >
      <Heading heading={section.heading} description={section.description} />
      <div id={slidesId} className={styles.carouselQuotes}>
        {items.map((item, index) => (
          <figure
            key={`${item.author}-${item.quote}`}
            className={styles.carouselQuote}
            hidden={enhanced && index !== activeIndex}
            aria-roledescription={enhanced ? 'slide' : undefined}
            aria-label={enhanced ? `${index + 1} of ${items.length}` : undefined}
          >
            <QuoteContent item={item} />
          </figure>
        ))}
      </div>
      {enhanced && items.length > 1 && activeItem && (
        <div className={styles.carouselControls}>
          <output className={styles.carouselStatus} aria-atomic="true">
            {activeIndex + 1} of {items.length}
            <span className={styles.srOnly}>
              {' '}
              {activeItem.author}: {activeItem.quote}
            </span>
          </output>
          <div className={styles.carouselButtons}>
            <Button
              type="button"
              variant="outline"
              size="icon"
              className={styles.carouselButton}
              aria-label="Previous testimonial"
              aria-controls={slidesId}
              aria-keyshortcuts="ArrowLeft ArrowRight Home End"
              onClick={() => select(activeIndex - 1)}
              onKeyDown={onControlKeyDown}
            >
              <ArrowLeft aria-hidden="true" size={18} />
            </Button>
            <Button
              type="button"
              variant="outline"
              size="icon"
              className={styles.carouselButton}
              aria-label="Next testimonial"
              aria-controls={slidesId}
              aria-keyshortcuts="ArrowLeft ArrowRight Home End"
              onClick={() => select(activeIndex + 1)}
              onKeyDown={onControlKeyDown}
            >
              <ArrowRight aria-hidden="true" size={18} />
            </Button>
          </div>
        </div>
      )}
    </section>
  );
}

function Testimonials({ section }: { section: TestimonialSection }) {
  const items = section.items ?? [];
  if (section.variant === 'carousel') {
    return <TestimonialCarousel section={section} items={items} />;
  }
  return (
    <div className={styles.testimonials}>
      <Heading heading={section.heading} description={section.description} />
      <div className={styles.quoteWall}>
        {items.map((item) => (
          <figure key={`${item.author}-${item.quote}`} className={styles.wallQuote}>
            <QuoteContent item={item} />
          </figure>
        ))}
      </div>
    </div>
  );
}

export function TrustSection({
  section,
}: {
  section: LogosSection | StatsSection | TeamSection | TestimonialSection;
}) {
  switch (section.type) {
    case 'logos':
      return <Logos section={section} />;
    case 'stats':
      return <Stats section={section} />;
    case 'team':
      return <Team section={section} />;
    case 'testimonial':
      return <Testimonials section={section} />;
  }
}
