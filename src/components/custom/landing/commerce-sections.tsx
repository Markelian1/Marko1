// @polsia:user-owned
'use client';

import { ArrowLeftRight, ChevronDown } from 'lucide-react';
import Image from 'next/image';
import { useEffect, useId, useState } from 'react';
import type { CommerceSection as CommerceConfig } from '@/lib/business/landing/types';
import styles from './commerce-sections.module.css';
import { LandingAction } from './landing-action';

export function CommerceSectionContent({ section }: { section: CommerceConfig }) {
  const [enhanced, setEnhanced] = useState(false);
  const [selectedCategory, setSelectedCategory] = useState<string | null>(null);
  const id = useId();
  useEffect(() => setEnhanced(true), []);

  const categories = [
    ...new Set(section.items.flatMap((item) => (item.category ? [item.category] : []))),
  ];
  const canFilter = Boolean(section.filter) && categories.length > 1;
  const activeCategory =
    canFilter && selectedCategory && categories.includes(selectedCategory)
      ? selectedCategory
      : null;
  const items = activeCategory
    ? section.items.filter((item) => item.category === activeCategory)
    : section.items;
  const isRail = section.variant === 'rail';
  const ProductList = isRail ? 'section' : 'div';

  return (
    <div className={styles.commerce}>
      <header className={styles.heading}>
        <div>
          <h2>{section.heading}</h2>
          {section.description && <p>{section.description}</p>}
        </div>
        {section.notice && <p className={styles.notice}>{section.notice}</p>}
      </header>
      {enhanced && canFilter && section.filter && (
        <fieldset className={styles.filters}>
          <legend className={styles.visuallyHidden}>{section.filter.label}</legend>
          <button
            type="button"
            aria-pressed={activeCategory === null}
            aria-controls={`${id}-products`}
            onClick={() => setSelectedCategory(null)}
          >
            {section.filter.allLabel}
          </button>
          {categories.map((category) => (
            <button
              key={category}
              type="button"
              aria-pressed={activeCategory === category}
              aria-controls={`${id}-products`}
              onClick={() => setSelectedCategory(category)}
            >
              {category}
            </button>
          ))}
        </fieldset>
      )}
      {isRail && items.length > 1 && (
        <p id={`${id}-scroll-hint`} className={styles.scrollHint}>
          {section.scrollLabel ?? 'Scroll to explore'}
          <ArrowLeftRight className={styles.scrollIcon} size={18} aria-hidden="true" />
        </p>
      )}
      <ProductList
        id={`${id}-products`}
        className={`${styles.products} ${styles[section.variant] ?? ''}`}
        aria-label={isRail ? section.heading : undefined}
        aria-describedby={isRail && items.length > 1 ? `${id}-scroll-hint` : undefined}
        tabIndex={isRail ? 0 : undefined}
      >
        {items.map((item) => (
          <article key={item.id} className={styles.product} aria-labelledby={`${id}-${item.id}`}>
            <figure className={styles.photo}>
              <Image
                src={item.image.src}
                alt={item.image.alt}
                fill
                sizes="(max-width: 600px) 90vw, (max-width: 900px) 45vw, 30vw"
                unoptimized
              />
              {item.image.caption && <figcaption>{item.image.caption}</figcaption>}
            </figure>
            <div className={styles.copy}>
              {item.category && <p className={styles.category}>{item.category}</p>}
              <div className={styles.productTitle}>
                <h3 id={`${id}-${item.id}`}>{item.title}</h3>
                {item.price && <p className={styles.price}>{item.price}</p>}
              </div>
              {section.variant === 'lookbook' && item.description && (
                <p className={styles.productDescription}>{item.description}</p>
              )}
              {((section.variant !== 'lookbook' && item.description) ||
                Boolean(item.details?.length)) && (
                <details className={styles.details}>
                  <summary>
                    <span>
                      {section.detailsLabel ?? 'Product details'}
                      <span className={styles.visuallyHidden}>: {item.title}</span>
                    </span>
                    <ChevronDown size={16} aria-hidden="true" />
                  </summary>
                  {section.variant !== 'lookbook' && item.description && <p>{item.description}</p>}
                  {Boolean(item.details?.length) && (
                    <dl>
                      {item.details?.map((detail) => (
                        <div key={detail.label}>
                          <dt>{detail.label}</dt>
                          <dd>{detail.value}</dd>
                        </div>
                      ))}
                    </dl>
                  )}
                </details>
              )}
              {item.action && (
                <div className={styles.action}>
                  <LandingAction action={item.action} secondary compact />
                </div>
              )}
            </div>
          </article>
        ))}
      </ProductList>
    </div>
  );
}
