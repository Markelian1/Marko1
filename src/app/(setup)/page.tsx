// @polsia:user-owned — configure the home page in src/lib/business/landing/config.ts.
import type { Metadata } from 'next';
import Link from 'next/link';
import { ArrowDown, ArrowRight, MoveUpRight } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import { siteDescription, siteName } from '@/lib/brand';

export const metadata: Metadata = {
  title: { absolute: siteName },
  description: siteDescription,
  alternates: { canonical: '/' },
};

const contactHref = 'mailto:wickmorrow-7@polsia.app';

const process = [
  {
    number: '01',
    title: 'Choose the instrument',
    description: 'Start with a market you want to trade, such as gold (XAUUSD).',
  },
  {
    number: '02',
    title: 'Tune the settings',
    description: 'Adjust the Expert Advisor’s parameters to suit your preferences.',
  },
  {
    number: '03',
    title: 'Let the rules run',
    description: 'Automate the actions in your setup with less manual monitoring.',
  },
];

export default function HomePage() {
  return (
    <main>
      <section aria-labelledby="hero-title" className="relative isolate overflow-hidden border-b border-border">
        <div
          aria-hidden="true"
          className="pointer-events-none absolute -right-28 -top-28 size-[28rem] rounded-full bg-primary/10 blur-3xl sm:size-[38rem]"
        />
        <div className="container-page relative grid gap-14 py-16 sm:py-24 lg:grid-cols-12 lg:items-center lg:gap-8 lg:py-28">
          <div className="relative z-10 lg:col-span-7">
            <p className="flex flex-wrap items-center gap-x-3 gap-y-1 text-caption font-semibold uppercase tracking-[0.16em] text-muted-foreground">
              <span className="text-primary">Wickmorrow</span>
              <span aria-hidden="true">/</span>
              <span>MetaTrader Expert Advisor</span>
            </p>
            <h1
              className="mt-7 max-w-4xl font-display text-5xl font-semibold leading-[0.99] tracking-[-0.045em] sm:text-7xl lg:text-display"
              id="hero-title"
            >
              Make room for the plan.
            </h1>
            <p className="mt-7 max-w-2xl text-xl font-medium leading-relaxed text-primary sm:text-2xl">
              Automated MetaTrader trading, guided by rules you control.
            </p>
            <p className="mt-4 max-w-xl text-body leading-relaxed text-muted-foreground sm:text-body-lg">
              Configure a strategy for an instrument or setup, then tune the robot to fit the way
              you want to trade.
            </p>
            <div className="mt-9 flex flex-wrap items-center gap-3">
              <Button asChild size="lg" className="group transition duration-200 ease-out hover:-translate-y-0.5">
                <Link href="#approach">
                  Explore the approach
                  <ArrowDown className="transition-transform duration-200 ease-out group-hover:translate-y-0.5" aria-hidden="true" />
                </Link>
              </Button>
              <Button asChild size="lg" variant="outline" className="transition duration-200 ease-out hover:-translate-y-0.5">
                <Link href={contactHref}>
                  Contact Wickmorrow
                  <MoveUpRight aria-hidden="true" />
                </Link>
              </Button>
            </div>
            <div className="mt-14 flex max-w-md items-center gap-4 border-t border-border pt-5 text-caption font-medium uppercase tracking-[0.12em] text-muted-foreground">
              <span>Rules you set</span>
              <span aria-hidden="true" className="h-px flex-1 bg-border" />
              <span>Execution on script</span>
            </div>
          </div>

          <div className="relative mx-auto w-full max-w-[30rem] lg:col-span-5 lg:col-start-9">
            <div className="mb-3 flex items-center justify-between text-caption font-semibold uppercase tracking-[0.13em] text-muted-foreground">
              <span>Rules before reaction</span>
              <span className="text-primary">01 — 03</span>
            </div>
            <div className="relative overflow-hidden border-y border-border py-8 sm:py-10">
              <svg aria-hidden="true" className="block w-full text-primary" fill="none" viewBox="0 0 440 250">
                <g className="text-muted-foreground" opacity="0.22" stroke="currentColor" strokeWidth="1">
                  <path d="M24 35H416M24 95H416M24 155H416M24 215H416" />
                  <path d="M84 18V232M176 18V232M268 18V232M360 18V232" strokeDasharray="3 7" />
                </g>
                <path
                  d="M24 180H106L145 139H235L274 180H350L391 111H416"
                  stroke="currentColor"
                  strokeLinecap="square"
                  strokeLinejoin="round"
                  strokeWidth="3"
                />
                <path d="M145 139V82M274 180V218M391 111V61" stroke="currentColor" strokeWidth="2" />
                <circle cx="106" cy="180" r="6" fill="currentColor" />
                <circle cx="235" cy="139" r="6" fill="currentColor" />
                <circle cx="350" cy="180" r="6" fill="currentColor" />
                <circle cx="391" cy="111" r="8" className="fill-background" stroke="currentColor" strokeWidth="3" />
              </svg>
              <div className="mt-5 grid grid-cols-3 gap-3 border-t border-border pt-4">
                {[
                  ['01', 'Instrument'],
                  ['02', 'Setup'],
                  ['03', 'Execution'],
                ].map(([number, label]) => (
                  <div key={number}>
                    <span className="text-caption font-semibold tabular-nums text-primary">{number}</span>
                    <p className="mt-1 text-small font-medium text-foreground">{label}</p>
                  </div>
                ))}
              </div>
            </div>
            <p className="mt-4 max-w-xs text-small leading-relaxed text-muted-foreground">
              A schematic of the process, not a live market chart.
            </p>
          </div>
        </div>
      </section>

      <section aria-labelledby="approach-title" className="section-lg" id="approach">
        <div className="container-page grid gap-12 lg:grid-cols-12 lg:gap-10">
          <div className="lg:col-span-4">
            <p className="text-eyebrow">A measured workflow</p>
            <h2 className="mt-5 max-w-md font-display text-h2 sm:text-5xl" id="approach-title">
              Built around your setup.
            </h2>
            <p className="mt-5 max-w-sm text-body leading-relaxed text-muted-foreground">
              Bring the approach you want to automate. Wickmorrow is designed to help carry its
              rules through with less manual monitoring.
            </p>
          </div>
          <ol className="divide-y divide-border border-y border-border lg:col-span-7 lg:col-start-6">
            {process.map((step) => (
              <li className="grid gap-3 py-6 sm:grid-cols-[3.5rem_1fr] sm:gap-5 sm:py-7" key={step.number}>
                <span className="font-display text-h4 tabular-nums text-primary">{step.number}</span>
                <div>
                  <h3 className="font-display text-h4 tracking-tight">{step.title}</h3>
                  <p className="mt-2 max-w-xl text-body leading-relaxed text-muted-foreground">
                    {step.description}
                  </p>
                </div>
              </li>
            ))}
          </ol>
        </div>
      </section>

      <section aria-labelledby="control-title" className="border-y border-border bg-muted/40 py-section-lg" id="control">
        <div className="container-page grid items-center gap-12 lg:grid-cols-12 lg:gap-10">
          <div className="lg:col-span-5">
            <p className="text-eyebrow">The details stay yours</p>
            <h2 className="mt-5 max-w-lg font-display text-h2 sm:text-5xl" id="control-title">
              One robot. Your rules.
            </h2>
            <p className="mt-5 max-w-lg text-body leading-relaxed text-muted-foreground sm:text-body-lg">
              Different instruments and strategies call for different settings. Wickmorrow is made
              to be adjusted to your preferences, rather than asking you to follow a fixed playbook.
            </p>
          </div>
          <Card className="rounded-sm border-border bg-card shadow-sm transition duration-200 ease-out hover:-translate-y-0.5 hover:shadow-lg lg:col-span-5 lg:col-start-8">
            <CardContent className="p-6 sm:p-8">
              <p className="text-caption font-semibold uppercase tracking-[0.14em] text-muted-foreground">
                Examples named for Wickmorrow
              </p>
              <dl className="mt-5 divide-y divide-border border-y border-border">
                <div className="flex flex-wrap items-baseline justify-between gap-x-5 gap-y-1 py-4">
                  <dt className="text-small text-muted-foreground">Instrument</dt>
                  <dd className="font-display text-h4 font-semibold tracking-tight">Gold · XAUUSD</dd>
                </div>
                <div className="flex flex-wrap items-baseline justify-between gap-x-5 gap-y-1 py-4">
                  <dt className="text-small text-muted-foreground">Setup</dt>
                  <dd className="font-display text-h4 font-semibold tracking-tight">Breakout</dd>
                </div>
                <div className="flex flex-wrap items-baseline justify-between gap-x-5 gap-y-1 py-4">
                  <dt className="text-small text-muted-foreground">Settings</dt>
                  <dd className="font-display text-h4 font-semibold tracking-tight">Your preferences</dd>
                </div>
              </dl>
              <p className="mt-4 text-caption leading-relaxed text-muted-foreground">
                Illustrative examples, not a recommendation to trade any instrument or setup.
              </p>
            </CardContent>
          </Card>
        </div>
      </section>

      <section aria-labelledby="contact-title" className="section-lg" id="contact">
        <div className="container-page grid gap-8 border-b border-border pb-section-lg sm:grid-cols-12 sm:items-end">
          <div className="sm:col-span-8">
            <p className="text-eyebrow">Start a conversation</p>
            <h2 className="mt-5 max-w-2xl font-display text-h2 sm:text-5xl" id="contact-title">
              Put your process first.
            </h2>
            <p className="mt-4 max-w-xl text-body leading-relaxed text-muted-foreground sm:text-body-lg">
              Ask about Wickmorrow and how rule-based automation could fit the way you trade.
            </p>
          </div>
          <div className="sm:col-span-4 sm:flex sm:justify-end">
            <Button asChild size="lg" className="group transition duration-200 ease-out hover:-translate-y-0.5">
              <Link href={contactHref}>
                Email Wickmorrow
                <ArrowRight className="transition-transform duration-200 ease-out group-hover:translate-x-1" aria-hidden="true" />
              </Link>
            </Button>
          </div>
        </div>
      </section>

      <section aria-labelledby="risk-title" className="px-gutter pb-16 sm:pb-20" id="risk">
        <div className="container-page grid gap-4 border-l-2 border-primary pl-5 sm:grid-cols-[12rem_1fr] sm:gap-10 sm:pl-7">
          <p className="text-caption font-semibold uppercase tracking-[0.14em] text-muted-foreground">
            A clear-eyed note
          </p>
          <div>
            <h2 className="font-display text-h4" id="risk-title">
              Automation can support consistency. It cannot promise an outcome.
            </h2>
            <p className="mt-3 max-w-3xl text-small leading-relaxed text-muted-foreground">
              Trading outcomes remain uncertain. Wickmorrow is designed to support rule-based
              execution and reduce manual monitoring; it does not promise profits or remove market
              risk.
            </p>
          </div>
        </div>
      </section>
    </main>
  );
}
