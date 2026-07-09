import Link from "next/link";

export function Logo({ size = "md", href = "/" }: { size?: "sm" | "md" | "lg"; href?: string | null }) {
  const dim = size === "sm" ? 28 : size === "lg" ? 40 : 32;
  const text = size === "sm" ? "text-lg" : size === "lg" ? "text-2xl" : "text-xl";
  const mark = (
    <span className="flex items-center gap-2.5">
      <span
        className="relative grid place-items-center rounded-xl bg-brand-gradient text-white shadow-[0_8px_24px_-8px_rgba(99,102,241,0.8)]"
        style={{ width: dim, height: dim }}
        aria-hidden
      >
        <svg width={dim * 0.58} height={dim * 0.58} viewBox="0 0 24 24" fill="none">
          <path
            d="M12 2l2.2 6.5L21 10l-5.4 4 2 7-5.6-4.2L6.4 21l2-7L3 10l6.8-1.5z"
            fill="white"
            fillOpacity="0.95"
          />
        </svg>
      </span>
      <span className={`font-display font-semibold tracking-tight text-ink ${text}`}>
        cre8tor
      </span>
    </span>
  );
  if (href === null) return mark;
  return (
    <Link href={href} className="inline-flex">
      {mark}
    </Link>
  );
}
