// @polsia:user-owned
'use client';

import { useReducedMotion } from 'motion/react';
import { useEffect, useRef, useState } from 'react';
import type { LandingMedia, StepsSection } from '@/lib/business/landing/types';
import { LandingImage } from './landing-image';
import styles from './landing-page.module.css';

function NarrativeImage({ media }: { media: LandingMedia }) {
  return (
    <figure className={styles.narrativeMedia}>
      <div className={styles.narrativeImage}>
        <LandingImage
          src={media.src}
          alt={media.alt}
          framing={media.framing}
          fill
          sizes="(max-width: 850px) 90vw, 45vw"
          unoptimized
        />
      </div>
      {media.caption && <figcaption>{media.caption}</figcaption>}
    </figure>
  );
}

export function NarrativeSteps({ section }: { section: StepsSection }) {
  const list = useRef<HTMLOListElement>(null);
  const [active, setActive] = useState(0);
  const [enhanced, setEnhanced] = useState(false);
  const reducedMotion = useReducedMotion();
  // biome-ignore lint/correctness/useExhaustiveDependencies: Re-observe chapter DOM when configuration replaces items.
  useEffect(() => {
    if (reducedMotion || !list.current || typeof IntersectionObserver === 'undefined') return;
    const chapters = Array.from(list.current.children);
    const observer = new IntersectionObserver(
      (entries) => {
        const visible = entries.filter((entry) => entry.isIntersecting);
        const lastVisible = visible.at(-1);
        if (lastVisible) setActive(chapters.indexOf(lastVisible.target));
      },
      { rootMargin: '-15% 0px -50% 0px', threshold: 0 },
    );
    for (const chapter of chapters) observer.observe(chapter);
    setEnhanced(true);
    return () => observer.disconnect();
  }, [reducedMotion, section.items]);
  const current = section.items[active]?.media ?? section.media;
  return (
    <div
      className={styles.narrative}
      data-enhanced={enhanced && !reducedMotion ? 'true' : undefined}
    >
      <div className={styles.narrativeHeading}>
        <h2>{section.heading}</h2>
        {section.description && <p>{section.description}</p>}
      </div>
      <div className={styles.narrativeLayout}>
        <div className={styles.narrativeSticky}>
          {current && <NarrativeImage media={current} />}
        </div>
        <ol ref={list} className={styles.narrativeChapters}>
          {section.items.map((item, index) => {
            const media = item.media ?? section.media;
            return (
              <li key={item.title}>
                {media && (
                  <div className={styles.narrativeInlineImage}>
                    <NarrativeImage media={media} />
                  </div>
                )}
                <div className={styles.narrativeCopy}>
                  <span className={styles.narrativeNumber} aria-hidden="true">
                    {String(index + 1).padStart(2, '0')}
                  </span>
                  <h3>{item.title}</h3>
                  <p>{item.description}</p>
                </div>
              </li>
            );
          })}
        </ol>
      </div>
    </div>
  );
}
