"use client";

import { useStore } from "@/lib/store";
import { useHydrated } from "@/lib/hooks";
import { AvatarFace } from "./AvatarFace";
import type { Character } from "@/lib/types";

// Circular avatar for a character: real photo/generated portrait (imageUrl)
// when present, otherwise an illustrated procedural face.
export function CharacterAvatar({
  character,
  size = 44,
}: {
  character: Character;
  size?: number;
}) {
  if (character.imageUrl) {
    return (
      // eslint-disable-next-line @next/next/no-img-element
      <img
        src={character.imageUrl}
        alt={character.name}
        width={size}
        height={size}
        className="rounded-full object-cover"
        style={{ width: size, height: size }}
      />
    );
  }
  return <AvatarFace character={character} size={size} />;
}

// Compact, self-contained picker meant to sit inside the UGC studio form.
export function CharacterPicker({
  value,
  onChange,
}: {
  value?: string;
  onChange: (id: string) => void;
}) {
  const hydrated = useHydrated();
  const characters = useStore((s) => s.characters);

  if (!hydrated) {
    return (
      <div className="flex gap-2 overflow-hidden">
        {Array.from({ length: 5 }).map((_, i) => (
          <div
            key={i}
            className="h-11 w-11 shrink-0 animate-pulse rounded-full bg-white/[0.04]"
          />
        ))}
      </div>
    );
  }

  return (
    <div className="flex flex-wrap gap-2 sm:flex-nowrap sm:overflow-x-auto sm:pb-1">
      {characters.map((c) => {
        const selected = c.id === value;
        return (
          <button
            key={c.id}
            type="button"
            onClick={() => onChange(c.id)}
            title={`${c.name} — ${c.vibe}`}
            aria-pressed={selected}
            className="flex w-16 shrink-0 flex-col items-center gap-1.5 outline-none"
          >
            <span
              className={`rounded-full p-0.5 transition ${
                selected
                  ? "ring-2 ring-brand-500 ring-offset-2 ring-offset-bg"
                  : "ring-1 ring-line hover:ring-line-strong"
              }`}
            >
              <CharacterAvatar character={c} size={44} />
            </span>
            <span
              className={`w-full truncate text-center text-[11px] ${
                selected ? "text-ink" : "text-ink-faint"
              }`}
            >
              {c.name}
            </span>
          </button>
        );
      })}
    </div>
  );
}
