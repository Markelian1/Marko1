// @polsia:user-owned
import Image from 'next/image';
import type { CtaSection, HeroSection } from '@/lib/business/landing/types';
import styles from './campaign-sections.module.css';
import { LandingAction } from './landing-action';

export function CampaignHero({ section }: { section: HeroSection }) {
  const media = section.media;
  return (
    <div className={styles.campaign}>
      {media?.src && (
        <figure className={styles.media}>
          <div className={styles.mediaFrame} data-media-kind={media.kind}>
            <Image
              src={media.src}
              alt={media.alt}
              fill
              sizes="(max-width: 700px) 88vw, 89vw"
              loading="eager"
              unoptimized
            />
          </div>
          {media.caption && <figcaption>{media.caption}</figcaption>}
        </figure>
      )}
      <div className={styles.campaignCopy}>
        {section.eyebrow && <p className={styles.eyebrow}>{section.eyebrow}</p>}
        <h1 className={styles.title}>{section.title}</h1>
        <p className={styles.description}>{section.description}</p>
        <div className={styles.campaignActions}>
          <LandingAction action={section.primaryAction} />
          {section.secondaryAction && <LandingAction action={section.secondaryAction} secondary />}
        </div>
        {section.note && <p className={styles.note}>{section.note}</p>}
      </div>
    </div>
  );
}

export function MinimalCta({ section }: { section: CtaSection }) {
  return (
    <div className={styles.minimal}>
      <h2 className={styles.headline}>{section.heading}</h2>
      <div className={styles.invitation}>
        {section.description && (
          <p className={styles.invitationDescription}>{section.description}</p>
        )}
        <div className={styles.invitationActions}>
          <LandingAction action={section.action} />
          {section.secondaryAction && (
            <div className={styles.secondaryAction}>
              <LandingAction action={section.secondaryAction} secondary />
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
