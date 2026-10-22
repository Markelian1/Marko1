// @polsia:user-owned — supplied contact, comparison and programme content.
'use client';

import Image from 'next/image';
import Link from 'next/link';
import { useEffect, useId, useState } from 'react';
import type {
  AgendaSection,
  ComparisonSection,
  ContactSection,
} from '@/lib/business/landing/types';
import { LandingAction } from './landing-action';
import styles from './practical-sections.module.css';

function Heading({ heading, description }: { heading: string; description?: string }) {
  return (
    <header className={styles.heading}>
      <h2>{heading}</h2>
      {description && <p>{description}</p>}
    </header>
  );
}

function Contact({ section }: { section: ContactSection }) {
  return (
    <div className={`${styles.contact} ${styles[section.variant]}`}>
      <div className={styles.contactContent}>
        <Heading heading={section.heading} description={section.description} />
        <div className={styles.contactDetails}>
          {(section.address || section.email || section.phone) && (
            <address className={styles.address}>
              {section.address && <p>{section.address}</p>}
              {section.email && <Link href={`mailto:${section.email}`}>{section.email}</Link>}
              {section.phone && (
                <Link href={`tel:${section.phone.replace(/[^+\d]/g, '')}`}>{section.phone}</Link>
              )}
            </address>
          )}
          {section.hours && section.hours.length > 0 && (
            <dl className={styles.hours}>
              {section.hours.map((hour) => (
                <div key={hour.label}>
                  <dt>{hour.label}</dt>
                  <dd>{hour.value}</dd>
                </div>
              ))}
            </dl>
          )}
          {section.action && <LandingAction action={section.action} />}
        </div>
      </div>
      {section.variant === 'map' && section.map && (
        <figure className={styles.mapFigure}>
          <Link href={section.map.href} className={styles.mapLink}>
            <Image
              src={section.map.src}
              alt={section.map.alt}
              fill
              sizes="(max-width: 700px) 90vw, 45vw"
              unoptimized
            />
            <span className={styles.directions}>Get directions</span>
          </Link>
          {section.map.caption && <figcaption>{section.map.caption}</figcaption>}
        </figure>
      )}
    </div>
  );
}

function BeforeAfter({ section }: { section: ComparisonSection }) {
  const rangeId = useId();
  const [position, setPosition] = useState(50);
  const [enhanced, setEnhanced] = useState(false);
  useEffect(() => setEnhanced(true), []);
  const { before, after } = section;
  if (!before || !after) return null;
  return (
    <div className={styles.beforeAfter}>
      <div className={styles.imageComparison}>
        <figure className={styles.comparisonImage}>
          <Image src={after.src} alt={after.alt} fill sizes="90vw" unoptimized />
        </figure>
        <figure
          className={styles.comparisonImage}
          style={{ clipPath: `inset(0 ${100 - position}% 0 0)` }}
        >
          <Image src={before.src} alt={before.alt} fill sizes="90vw" unoptimized />
        </figure>
        <span
          className={styles.comparisonDivider}
          style={{ left: `${position}%` }}
          aria-hidden="true"
        />
      </div>
      <div className={styles.comparisonLabels}>
        <div>
          <strong>{before.label}</strong>
          {before.caption && <p>{before.caption}</p>}
        </div>
        <div>
          <strong>{after.label}</strong>
          {after.caption && <p>{after.caption}</p>}
        </div>
      </div>
      <div className={styles.rangeHeading}>
        <label htmlFor={rangeId}>Compare images</label>
        <output htmlFor={rangeId}>{position}%</output>
      </div>
      <input
        id={rangeId}
        className={styles.range}
        type="range"
        disabled={!enhanced}
        min={0}
        max={100}
        step={1}
        value={position}
        aria-valuetext={`${before.label} ${position}%, ${after.label} ${100 - position}%`}
        onChange={(event) => setPosition(event.currentTarget.valueAsNumber)}
      />
    </div>
  );
}

function Comparison({ section }: { section: ComparisonSection }) {
  return (
    <div className={styles.comparison}>
      <Heading heading={section.heading} description={section.description} />
      {section.variant === 'before-after' ? (
        <BeforeAfter section={section} />
      ) : (
        <section
          className={styles.tableScroller}
          aria-label={`${section.heading} comparison table`}
          // biome-ignore lint/a11y/noNoninteractiveTabindex: The overflowing table needs keyboard scrolling.
          tabIndex={0}
        >
          <table className={styles.comparisonTable} aria-label={section.heading}>
            <thead>
              <tr>
                <th scope="col">Feature</th>
                {section.columns?.map((column) => (
                  <th
                    scope="col"
                    key={column.label}
                    className={column.highlighted ? styles.highlighted : undefined}
                  >
                    {column.label}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {section.rows?.map((row) => (
                <tr key={row.label}>
                  <th scope="row">{row.label}</th>
                  {row.values.map((value, index) => (
                    <td
                      key={section.columns?.[index]?.label ?? index}
                      className={
                        section.columns?.[index]?.highlighted ? styles.highlighted : undefined
                      }
                    >
                      {value}
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </section>
      )}
    </div>
  );
}

function Agenda({ section }: { section: AgendaSection }) {
  return (
    <div className={`${styles.agenda} ${styles[section.variant]}`}>
      <Heading heading={section.heading} description={section.description} />
      <ol className={styles.agendaItems}>
        {section.items.map((item, index) => (
          <li className={styles.agendaItem} key={item.title}>
            <div className={styles.agendaMarker}>
              {section.variant === 'curriculum' && (
                <span className={styles.moduleNumber} aria-hidden="true">
                  {String(index + 1).padStart(2, '0')}
                </span>
              )}
              {item.time && <span className={styles.time}>{item.time}</span>}
              {item.duration && <span className={styles.duration}>{item.duration}</span>}
            </div>
            <div className={styles.agendaContent}>
              {item.label && <span className={styles.itemLabel}>{item.label}</span>}
              <h3>{item.title}</h3>
              {item.description && <p>{item.description}</p>}
            </div>
            {item.action && (
              <div className={styles.itemAction}>
                <LandingAction action={item.action} secondary compact />
              </div>
            )}
          </li>
        ))}
      </ol>
    </div>
  );
}

export function PracticalSection({
  section,
}: {
  section: ContactSection | ComparisonSection | AgendaSection;
}) {
  switch (section.type) {
    case 'contact':
      return <Contact section={section} />;
    case 'comparison':
      return <Comparison section={section} />;
    case 'agenda':
      return <Agenda section={section} />;
  }
}
