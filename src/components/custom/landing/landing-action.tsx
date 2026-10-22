// @polsia:user-owned — shared real navigation action for landing sections.
'use client';
import { ArrowUpRight } from 'lucide-react';
import { useReducedMotion } from 'motion/react';
import * as m from 'motion/react-m';
import Link from 'next/link';
import { Button } from '@/components/ui/button';
import type { Action } from '@/lib/business/landing/types';
import styles from './landing-page.module.css';

const MotionLink = m.create(Link);

export function LandingAction({
  action,
  secondary = false,
  compact = false,
  onClick,
}: {
  action: Action;
  secondary?: boolean;
  compact?: boolean;
  onClick?: () => void;
}) {
  const reduceMotion = useReducedMotion();
  return (
    <Button
      asChild
      variant={secondary ? 'outline' : 'default'}
      className={`${styles.action} ${secondary ? styles.secondaryAction : ''} ${compact ? styles.compactAction : ''}`}
    >
      <MotionLink
        href={action.href}
        onClick={onClick}
        tabIndex={0}
        whileHover={reduceMotion ? undefined : { y: -2 }}
        whileTap={reduceMotion ? undefined : { scale: 0.98, y: 0 }}
        transition={{ duration: 0.18 }}
      >
        {action.label}
        {!compact && <ArrowUpRight aria-hidden="true" size={16} />}
      </MotionLink>
    </Button>
  );
}
