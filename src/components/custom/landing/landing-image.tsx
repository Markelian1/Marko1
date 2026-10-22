// @polsia:user-owned
import Image, { type ImageProps } from 'next/image';
import type { CSSProperties } from 'react';
import type { MediaFraming } from '@/lib/business/landing/types';
import styles from './landing-page.module.css';

/** Without framing, retain the existing Image element, props and DOM exactly. */
export function LandingImage({ framing, ...props }: ImageProps & { framing?: MediaFraming }) {
  if (!framing) return <Image {...props} />;
  const position = (point: MediaFraming['position']) => point && `${point.x}% ${point.y}%`;
  const style: CSSProperties & Record<`--land-media-${string}`, string | undefined> = {
    ...props.style,
    '--land-media-fit': framing.fit,
    '--land-media-position': position(framing.position),
    '--land-media-mobile-fit': framing.mobile?.fit,
    '--land-media-mobile-position': position(framing.mobile?.position),
  };
  const image = (
    <Image
      {...props}
      // Let picture choose the resource; a desktop preload would fetch both crops on mobile.
      priority={framing.mobile?.src ? false : props.priority}
      preload={framing.mobile?.src ? false : props.preload}
      loading={framing.mobile?.src && (props.priority || props.preload) ? 'eager' : props.loading}
      fetchPriority={
        framing.mobile?.src && (props.priority || props.preload) ? 'high' : props.fetchPriority
      }
      className={[props.className, styles.framedImage].filter(Boolean).join(' ')}
      data-framed-image="true"
      data-framed-fit={framing.fit ? 'true' : undefined}
      data-framed-position={framing.position ? 'true' : undefined}
      data-framed-mobile-fit={framing.mobile?.fit ? 'true' : undefined}
      data-framed-mobile-position={framing.mobile?.position ? 'true' : undefined}
      style={style}
    />
  );
  return framing.mobile?.src ? (
    <picture className={styles.responsivePicture}>
      <source media="(max-width: 700px)" srcSet={framing.mobile.src} />
      {image}
    </picture>
  ) : (
    image
  );
}
