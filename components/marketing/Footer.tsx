import Link from "next/link";
import { Logo } from "@/components/Logo";
import { IconLinkedIn, IconInstagram, IconXSocial } from "@/components/Icons";

const columns: { title: string; links: { label: string; href: string }[] }[] = [
  {
    title: "Product",
    links: [
      { label: "Features", href: "/#features" },
      { label: "How it works", href: "/#how" },
      { label: "Pricing", href: "/pricing" },
      { label: "Changelog", href: "#" },
    ],
  },
  {
    title: "Company",
    links: [
      { label: "About", href: "#" },
      { label: "Careers", href: "#" },
      { label: "Blog", href: "#" },
      { label: "Contact", href: "#" },
    ],
  },
  {
    title: "Resources",
    links: [
      { label: "Creator guide", href: "#" },
      { label: "Voice playbook", href: "#" },
      { label: "Help center", href: "#" },
      { label: "Community", href: "#" },
    ],
  },
  {
    title: "Legal",
    links: [
      { label: "Privacy", href: "#" },
      { label: "Terms", href: "#" },
      { label: "Security", href: "#" },
      { label: "Cookies", href: "#" },
    ],
  },
];

const socials = [
  { label: "LinkedIn", href: "#", Icon: IconLinkedIn },
  { label: "Instagram", href: "#", Icon: IconInstagram },
  { label: "X", href: "#", Icon: IconXSocial },
];

export function Footer() {
  return (
    <footer className="border-t border-line bg-bg-soft/40">
      <div className="container-page py-14">
        <div className="grid gap-10 md:grid-cols-[1.5fr_repeat(4,1fr)]">
          <div className="max-w-xs">
            <Logo size="md" href="/" />
            <p className="mt-4 text-sm leading-relaxed text-ink-soft">
              Your AI Head of Content. Know what to post, sound like you, and
              grow — every single week.
            </p>
          </div>

          {columns.map((col) => (
            <div key={col.title}>
              <h3 className="text-xs font-semibold uppercase tracking-wide text-ink-faint">
                {col.title}
              </h3>
              <ul className="mt-4 space-y-2.5">
                {col.links.map((l) => (
                  <li key={l.label}>
                    <Link
                      href={l.href}
                      className="text-sm text-ink-soft transition-colors hover:text-ink"
                    >
                      {l.label}
                    </Link>
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>

        <div className="mt-12 flex flex-col items-center justify-between gap-4 border-t border-line pt-6 sm:flex-row">
          <p className="text-sm text-ink-faint">© 2026 cre8tor. All rights reserved.</p>
          <div className="flex items-center gap-2">
            {socials.map(({ label, href, Icon }) => (
              <Link
                key={label}
                href={href}
                aria-label={label}
                className="grid h-9 w-9 place-items-center rounded-full border border-line text-ink-soft transition-colors hover:border-line-strong hover:text-ink"
              >
                <Icon width={17} height={17} />
              </Link>
            ))}
          </div>
        </div>
      </div>
    </footer>
  );
}
