// @polsia:user-owned
import Image from 'next/image';
import type { GallerySection, HeroSection } from '@/lib/business/landing/types';
import { LandingAction } from './landing-action';
import styles from './personal-sections.module.css';

export function ProfileHero({ section }: { section: HeroSection }) {
  const portrait = section.media;
  return (
    <div className={`${styles.profile} ${portrait?.src ? styles.withPortrait : ''}`}>
      <div className={styles.introduction}>
        {section.eyebrow && <p className={styles.role}>{section.eyebrow}</p>}
        <h1 className={styles.name}>{section.title}</h1>
        <p className={styles.description}>{section.description}</p>
        <div className={styles.actions}>
          <LandingAction action={section.primaryAction} />
          {section.secondaryAction && <LandingAction action={section.secondaryAction} secondary />}
        </div>
        {section.note && <p className={styles.note}>{section.note}</p>}
      </div>
      {portrait?.src && (
        <figure className={styles.portrait}>
          <div className={styles.portraitFrame}>
            <Image
              src={portrait.src}
              alt={portrait.alt}
              fill
              sizes="(max-width: 700px) 80vw, 32vw"
              priority
              unoptimized
            />
          </div>
          {portrait.caption && <figcaption>{portrait.caption}</figcaption>}
        </figure>
      )}
    </div>
  );
}

export function PortfolioGallery({ section }: { section: GallerySection }) {
  return (
    <div className={styles.portfolio}>
      <div className={styles.heading}>
        <h2>{section.heading}</h2>
        {section.description && <p>{section.description}</p>}
      </div>
      <div className={styles.projects}>
        {section.items.map((item) => (
          <article
            key={item.title}
            className={`${styles.project} ${item.image ? styles.withImage : ''}`}
          >
            {item.image && (
              <div className={styles.projectImage}>
                <Image
                  src={item.image}
                  alt={item.alt ?? item.title}
                  fill
                  sizes="(max-width: 700px) 90vw, 40vw"
                  unoptimized
                />
              </div>
            )}
            <div className={styles.projectCopy}>
              {(item.category || item.tag) && (
                <div className={styles.projectMeta}>
                  {item.category && <span>{item.category}</span>}
                  {item.tag && <span>{item.tag}</span>}
                </div>
              )}
              <h3 className={styles.projectTitle}>{item.title}</h3>
              {item.subtitle && <p className={styles.projectDescription}>{item.subtitle}</p>}
              {item.action && (
                <div className={styles.projectAction}>
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
