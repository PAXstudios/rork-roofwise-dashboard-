"use client";

import { useId } from "react";
import { VIDEO_BG } from "@/lib/seed";
import type { Character } from "@/lib/types";

// Illustrated character faces, drawn procedurally in SVG so every character is
// visible offline. Presets have hand-tuned looks; custom characters without a
// photo get a deterministic look derived from their id.

interface Look {
  skin: string;
  hair: "curls" | "crop" | "buzz" | "bob" | "swoop" | "long";
  hairColor: string;
  shirt: string;
  glasses?: boolean;
  earrings?: boolean;
  lipTint?: string;
}

const PRESET_LOOKS: Record<string, Look> = {
  "char-maya": { skin: "#a9714b", hair: "curls", hairColor: "#221610", shirt: "#fb923c", earrings: true, lipTint: "#8c4a3a" },
  "char-jordan": { skin: "#e8b48c", hair: "crop", hairColor: "#5b3a21", shirt: "#14b8a6" },
  "char-alex": { skin: "#c68e5f", hair: "buzz", hairColor: "#1d1712", shirt: "#ef4444" },
  "char-sam": { skin: "#f2c9a0", hair: "bob", hairColor: "#d9a441", shirt: "#a855f7", earrings: true, lipTint: "#b05a63" },
  "char-chris": { skin: "#7a4a2b", hair: "crop", hairColor: "#120d09", shirt: "#3730a3", glasses: true },
  "char-nina": { skin: "#d8a07a", hair: "long", hairColor: "#2b1c14", shirt: "#65a30d", earrings: true, lipTint: "#a04f52" },
};

const SKINS = ["#f2c9a0", "#e8b48c", "#c68e5f", "#a9714b", "#7a4a2b", "#5c3a22"];
const HAIRS: Look["hair"][] = ["curls", "crop", "buzz", "bob", "swoop", "long"];
const HAIR_COLORS = ["#221610", "#5b3a21", "#d9a441", "#1d1712", "#4a2c17", "#0f0c0a"];
const SHIRTS = ["#6366f1", "#fb923c", "#14b8a6", "#a855f7", "#ef4444", "#65a30d"];

function hash(s: string) {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) >>> 0;
  return h;
}

function lookFor(c: Character): Look {
  if (PRESET_LOOKS[c.id]) return PRESET_LOOKS[c.id];
  const h = hash(c.id + c.name);
  const fem = c.gender === "female";
  return {
    skin: SKINS[h % SKINS.length],
    hair: fem ? (["curls", "bob", "long"] as const)[h % 3] : HAIRS[h % HAIRS.length],
    hairColor: HAIR_COLORS[(h >> 3) % HAIR_COLORS.length],
    shirt: SHIRTS[(h >> 6) % SHIRTS.length],
    earrings: fem,
    glasses: !fem && (h >> 9) % 3 === 0,
    lipTint: fem ? "#a04f52" : undefined,
  };
}

function Hair({ look }: { look: Look }) {
  const c = look.hairColor;
  switch (look.hair) {
    case "curls":
      return (
        <g fill={c}>
          <circle cx="32" cy="30" r="12" />
          <circle cx="50" cy="22" r="14" />
          <circle cx="68" cy="30" r="12" />
          <circle cx="26" cy="44" r="8" />
          <circle cx="74" cy="44" r="8" />
        </g>
      );
    case "crop":
      return <path d="M28 44c0-16 9-25 22-25s22 9 22 25c-3-9-9-13-22-13s-19 4-22 13z" fill={c} />;
    case "buzz":
      return <path d="M30 42c1-13 9-21 20-21s19 8 20 21c-4-7-10-10-20-10s-16 3-20 10z" fill={c} opacity="0.9" />;
    case "bob":
      return (
        <path
          d="M26 62c-2-26 8-40 24-40s26 14 24 40c-3-4-4-8-4-14-6 2-10-2-12-8-4 6-14 9-24 7-1 5-3 9-8 15z"
          fill={c}
        />
      );
    case "swoop":
      return <path d="M27 45c-1-15 8-26 23-26 12 0 21 7 22 20-8-7-16-9-26-6-9 3-15 6-19 12z" fill={c} />;
    case "long":
      return (
        <path
          d="M24 78c-3-30 2-56 26-56s29 26 26 56l-9-2c1-16 0-26-4-33-5 4-17 5-26 1-4 7-5 17-4 34z"
          fill={c}
        />
      );
  }
}

export function AvatarFace({
  character,
  size = 44,
  className = "",
}: {
  character: Character;
  size?: number;
  className?: string;
}) {
  const uid = useId().replace(/[:]/g, "");
  const look = lookFor(character);
  const bg = VIDEO_BG[character.swatch || "indigo"] || VIDEO_BG.indigo;
  const clip = `clip-${uid}`;

  return (
    <span
      aria-label={character.name}
      role="img"
      className={`inline-block overflow-hidden rounded-full ${className}`}
      style={{ width: size, height: size, background: bg }}
    >
      <svg viewBox="0 0 100 100" width={size} height={size} aria-hidden>
        <defs>
          <clipPath id={clip}>
            <circle cx="50" cy="50" r="50" />
          </clipPath>
        </defs>
        <g clipPath={`url(#${clip})`}>
          {/* shirt / shoulders */}
          <path d="M14 104c2-20 16-30 36-30s34 10 36 30z" fill={look.shirt} />
          {/* neck */}
          <rect x="43" y="62" width="14" height="16" rx="6" fill={look.skin} />
          <rect x="43" y="62" width="14" height="7" rx="3" fill="#00000022" />
          {/* long hair sits behind the head */}
          {look.hair === "long" && <Hair look={look} />}
          {/* ears */}
          <circle cx="29" cy="49" r="5" fill={look.skin} />
          <circle cx="71" cy="49" r="5" fill={look.skin} />
          {look.earrings && (
            <>
              <circle cx="29" cy="55" r="2" fill="#fbbf24" />
              <circle cx="71" cy="55" r="2" fill="#fbbf24" />
            </>
          )}
          {/* head */}
          <ellipse cx="50" cy="47" rx="21" ry="23" fill={look.skin} />
          {/* hair on top */}
          {look.hair !== "long" && <Hair look={look} />}
          {look.hair === "long" && (
            <path d="M29 44c0-14 8-22 21-22s21 8 21 22c-5-8-11-11-21-11s-16 3-21 11z" fill={look.hairColor} />
          )}
          {/* brows */}
          <path d="M38 41c2-2 6-2 8 0" stroke="#00000088" strokeWidth="2" strokeLinecap="round" fill="none" />
          <path d="M54 41c2-2 6-2 8 0" stroke="#00000088" strokeWidth="2" strokeLinecap="round" fill="none" />
          {/* eyes */}
          <circle cx="42" cy="48" r="2.6" fill="#1c1917" />
          <circle cx="58" cy="48" r="2.6" fill="#1c1917" />
          <circle cx="42.9" cy="47.2" r="0.8" fill="#fff" />
          <circle cx="58.9" cy="47.2" r="0.8" fill="#fff" />
          {look.glasses && (
            <g stroke="#0f172a" strokeWidth="1.8" fill="none">
              <circle cx="42" cy="48" r="6.5" />
              <circle cx="58" cy="48" r="6.5" />
              <path d="M48.5 48h3M35.5 47l-5-2M64.5 47l5-2" />
            </g>
          )}
          {/* nose */}
          <path d="M50 51v4c0 1.4-1.4 2.2-2.6 1.6" stroke="#00000033" strokeWidth="1.6" strokeLinecap="round" fill="none" />
          {/* smile */}
          <path
            d="M43 59c2.6 3.4 11.4 3.4 14 0"
            stroke={look.lipTint || "#00000066"}
            strokeWidth="2.4"
            strokeLinecap="round"
            fill="none"
          />
          {/* blush */}
          <circle cx="35" cy="54" r="3.4" fill="#f8717166" />
          <circle cx="65" cy="54" r="3.4" fill="#f8717166" />
        </g>
      </svg>
    </span>
  );
}
