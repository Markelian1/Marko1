// @polsia:user-owned — shared navigation behavior for the landing navbar layouts.
'use client';

import { ArrowDown, Menu, X } from 'lucide-react';
import { useReducedMotion } from 'motion/react';
import * as m from 'motion/react-m';
import Link from 'next/link';
import { useEffect, useId, useRef, useState } from 'react';
import { Button } from '@/components/ui/button';
import type { LandingConfig } from '@/lib/business/landing/types';
import { LandingAction } from './landing-action';
import styles from './landing-page.module.css';

type Props = Pick<LandingConfig, 'brand' | 'navbar' | 'navigation' | 'primaryAction'> & {
  homeHref: string;
};

export function LandingNavbar({ brand, navbar, navigation, primaryAction, homeHref }: Props) {
  const [open, setOpen] = useState(false);
  const reduceMotion = useReducedMotion();
  const menuId = useId();
  const headerRef = useRef<HTMLElement>(null);
  const toggleRef = useRef<HTMLButtonElement>(null);
  const variant = navbar?.variant ?? 'classic';
  const labels = navbar?.labels;

  useEffect(() => {
    if (!open) return;
    const dismiss = (event: Event) => {
      if (event.target instanceof Node && !headerRef.current?.contains(event.target))
        setOpen(false);
    };
    const dismissWithEscape = (event: KeyboardEvent) => {
      if (event.key !== 'Escape') return;
      event.preventDefault();
      setOpen(false);
      toggleRef.current?.focus();
    };
    document.addEventListener('pointerdown', dismiss);
    document.addEventListener('focusin', dismiss);
    document.addEventListener('keydown', dismissWithEscape);
    return () => {
      document.removeEventListener('pointerdown', dismiss);
      document.removeEventListener('focusin', dismiss);
      document.removeEventListener('keydown', dismissWithEscape);
    };
  }, [open]);

  return (
    <header ref={headerRef} className={styles.header} data-navbar-variant={variant}>
      <div className={styles.navbarBar}>
        <Link
          href={homeHref}
          className={`${styles.brand} ${styles.navbarBrand}`}
          onClick={() => setOpen(false)}
        >
          <span className={styles.brandMark} aria-hidden="true">
            {brand.monogram}
          </span>
          <span className={styles.navbarBrandName}>{brand.name}</span>
        </Link>
        <nav
          className={styles.desktopNav}
          aria-label={labels?.navigation ?? `${brand.name} navigation`}
        >
          {navigation.map((item) => (
            <Link key={item.sectionId} href={`#${item.sectionId}`}>
              {item.label}
            </Link>
          ))}
        </nav>
        <div className={styles.navbarActions}>
          <div className={styles.headerAction}>
            <LandingAction action={primaryAction} compact />
          </div>
          <Button
            ref={toggleRef}
            type="button"
            variant="ghost"
            size="icon"
            className={styles.menuToggle}
            aria-expanded={open}
            aria-controls={menuId}
            aria-label={
              open
                ? (labels?.closeMenu ?? 'Close navigation')
                : (labels?.openMenu ?? 'Open navigation')
            }
            onClick={() => setOpen(!open)}
          >
            {open ? <X aria-hidden="true" /> : <Menu aria-hidden="true" />}
          </Button>
        </div>
      </div>
      {open && (
        <m.nav
          id={menuId}
          className={styles.mobileNav}
          aria-label={labels?.navigation ?? 'Mobile navigation'}
          initial={reduceMotion ? false : { opacity: 0, y: -6 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.18 }}
        >
          {navigation.map((item) => (
            <Link key={item.sectionId} href={`#${item.sectionId}`} onClick={() => setOpen(false)}>
              {item.label}
              <ArrowDown aria-hidden="true" size={14} />
            </Link>
          ))}
          <LandingAction action={primaryAction} onClick={() => setOpen(false)} />
        </m.nav>
      )}
    </header>
  );
}
