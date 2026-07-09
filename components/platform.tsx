import type { Platform } from "@/lib/types";
import {
  IconLinkedIn,
  IconInstagram,
  IconXSocial,
  IconTikTok,
  IconYouTube,
} from "./Icons";

export const PLATFORM_META: Record<
  Platform,
  { label: string; color: string; Icon: (p: any) => JSX.Element }
> = {
  linkedin: { label: "LinkedIn", color: "#0a66c2", Icon: IconLinkedIn },
  instagram: { label: "Instagram", color: "#e1306c", Icon: IconInstagram },
  x: { label: "X", color: "#e7e9ea", Icon: IconXSocial },
  tiktok: { label: "TikTok", color: "#25f4ee", Icon: IconTikTok },
  youtube: { label: "YouTube", color: "#ff0000", Icon: IconYouTube },
};

export function PlatformBadge({ platform, size = 18 }: { platform: Platform; size?: number }) {
  const m = PLATFORM_META[platform];
  const Icon = m.Icon;
  return (
    <span
      className="grid place-items-center rounded-lg"
      style={{ width: size + 14, height: size + 14, background: `${m.color}1f`, color: m.color }}
      title={m.label}
    >
      <Icon width={size} height={size} />
    </span>
  );
}
