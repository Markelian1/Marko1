// @polsia:user-owned
import Image from 'next/image';
import type { GallerySection } from '@/lib/business/landing/types';
import styles from './editorial-showcase.module.css';
import { LandingAction } from './landing-action';

export function EditorialShowcase({ section }: { section: GallerySection }) {
  return (
    <div
      className={`${styles.showcase} ${section.variant === 'story' ? styles.story : styles.mosaic}`}
    >
      <header className={styles.heading}>
        <h2>{section.heading}</h2>
        {section.description && <p>{section.description}</p>}
      </header>
      <div className={styles.items}>
        {section.items.map((item) => (
          <article
            key={item.title}
            className={`${styles.item} ${item.image ? '' : styles.textOnly}`}
          >
            {item.image && (
              <figure className={styles.photo}>
                <Image
                  src={item.image}
                  alt={item.alt ?? item.title}
                  fill
                  sizes="(max-width: 700px) 90vw, 60vw"
                  unoptimized
                />
              </figure>
            )}
            <div className={styles.copy}>
              {(item.category || item.tag) && (
                <div className={styles.meta}>
                  {item.category && <span>{item.category}</span>}
                  {item.tag && <span>{item.tag}</span>}
                </div>
              )}
              <div className={styles.titleRow}>
                <h3 className={styles.title}>{item.title}</h3>
                {item.price && <p className={styles.price}>{item.price}</p>}
              </div>
              {item.subtitle && <p className={styles.subtitle}>{item.subtitle}</p>}
              {item.action && (
                <div className={styles.action}>
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
