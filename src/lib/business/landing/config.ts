// @polsia:user-owned — onboarding edits this composition. See docs/landing.md.
import { siteName } from '@/lib/brand';
import type { LandingConfig } from './types';

export const landingConfig: LandingConfig = {
  id: 'home',
  theme: { palette: 'cobalt', typography: 'sans', radius: 'soft' },
  navbar: { variant: 'classic' },
  brand: {
    name: siteName,
    monogram: siteName.charAt(0),
    tagline: 'Made with care.',
  },
  navigation: [
    { label: 'Discover', sectionId: 'benefits' },
    { label: 'How it works', sectionId: 'how-it-works' },
    { label: 'Questions', sectionId: 'questions' },
  ],
  primaryAction: { label: 'Explore', href: '#benefits' },
  footer: {
    description: 'Thoughtful details. A clear purpose. Something made for you.',
    links: [
      { label: 'Discover', href: '#benefits' },
      { label: 'Questions', href: '#questions' },
    ],
    copyright: `© ${siteName}. All rights reserved.`,
  },
  sections: [
    {
      id: 'hero',
      enabled: true,
      type: 'hero',
      variant: 'split',
      eyebrow: `Welcome to ${siteName}`,
      title: 'Good things\nstart here.',
      description: 'Discover what we do, how it works, and what makes it right for you.',
      primaryAction: { label: 'Take a closer look', href: '#benefits' },
      secondaryAction: { label: 'How it works', href: '#how-it-works' },
      media: {
        kind: 'image',
        src: '/landing/placeholder.svg',
        alt: 'Placeholder for the business’s main image',
      },
    },
    {
      id: 'benefits',
      enabled: true,
      type: 'features',
      variant: 'grid',
      heading: 'A little more thought.\nA better experience.',
      items: [
        {
          title: 'A clear starting point',
          description: 'Explore the details and find what fits your needs.',
          icon: 'sparkles',
        },
        {
          title: 'The details that matter',
          description: 'Get to know the approach behind what we do.',
          icon: 'layers',
        },
        {
          title: 'Your next step',
          description: 'Find answers to your questions before moving forward.',
          icon: 'arrow',
        },
      ],
    },
    {
      id: 'how-it-works',
      enabled: true,
      type: 'steps',
      variant: 'timeline',
      heading: 'From curious to confident.',
      items: [
        { title: 'Discover', description: 'Start with an overview of what we offer.' },
        { title: 'Explore', description: 'Look at the details that matter most to you.' },
        { title: 'Decide', description: 'Take the next step when the fit feels right.' },
      ],
    },
    {
      id: 'questions',
      enabled: true,
      type: 'faq',
      variant: 'accordion',
      heading: 'A few things to know.',
      items: [
        {
          question: 'Where should I start?',
          answer: 'Begin with the overview above, then explore how it works.',
        },
        {
          question: 'How do I find what is right for me?',
          answer: 'Read through the details with your needs in mind before taking the next step.',
        },
      ],
    },
    {
      id: 'next-step',
      enabled: true,
      type: 'cta',
      variant: 'banner',
      heading: 'Find your starting point.',
      description: 'Take a closer look at what we have to offer.',
      action: { label: 'Explore', href: '#benefits' },
    },
  ],
};
