import type { TranscriptSegment, TranscriptWord } from "./types";

const FILLERS = new Set(["um", "uh", "like", "you", "know", "so", "basically", "literally"]);

// A realistic demo transcript, deterministically derived from the clip length,
// with filler words, silence gaps, and a duplicate "alt take" so the editor's
// silence/filler/best-take tools have something real to act on. Real Whisper
// transcription can be wired behind OPENAI_API_KEY (see transcribeReal).

const SCRIPT_LINES = [
  "Okay so um the thing nobody tells you about growing on social",
  "is that consistency beats talent every single time",
  "Like I posted for ninety days straight before anything clicked",
  "uh and the moment I stopped chasing virality my reach actually went up",
  "So here's the exact system I use to never run out of ideas",
  "First, I keep a running note of every question my audience asks",
  "you know basically turning comments into content",
  "Second, I batch film on Sundays so weekdays stay free",
  "and third, I let AI handle the boring editing so I can focus on ideas",
  "If this helped, follow for more and I'll see you in the next one",
];

export function demoTranscript(durationSec: number): TranscriptSegment[] {
  const segments: TranscriptSegment[] = [];
  let t = 0;
  const lineCount = Math.max(4, Math.min(SCRIPT_LINES.length, Math.round(durationSec / 4)));

  for (let i = 0; i < lineCount; i++) {
    // occasional silence gap before a line
    if (i > 0 && i % 4 === 0) {
      const sStart = t;
      t += 1.4;
      segments.push({
        id: `seg-sil-${i}`,
        start: sStart,
        end: t,
        text: "(silence)",
        words: [],
        isSilence: true,
      });
    }

    const line = SCRIPT_LINES[i % SCRIPT_LINES.length];
    const tokens = line.split(" ");
    const words: TranscriptWord[] = [];
    const segStart = t;
    for (const tok of tokens) {
      const dur = 0.18 + Math.min(0.5, tok.length * 0.05);
      const w: TranscriptWord = {
        text: tok,
        start: t,
        end: t + dur,
        filler: FILLERS.has(tok.toLowerCase()),
      };
      words.push(w);
      t += dur + 0.04;
    }
    t += 0.3;
    segments.push({
      id: `seg-${i}`,
      start: segStart,
      end: t,
      text: line,
      words,
    });

    // an alternate (weaker) take of the 2nd line
    if (i === 1) {
      const altStart = t;
      const altTokens = "is that consistency beats talent basically always".split(" ");
      const altWords: TranscriptWord[] = altTokens.map((tok) => {
        const dur = 0.18 + Math.min(0.5, tok.length * 0.05);
        const w = { text: tok, start: t, end: t + dur, filler: FILLERS.has(tok.toLowerCase()) };
        t += dur + 0.04;
        return w;
      });
      t += 0.3;
      segments.push({
        id: `seg-alt-${i}`,
        start: altStart,
        end: t,
        text: altTokens.join(" "),
        words: altWords,
        isAltTake: true,
      });
    }
  }
  return segments;
}

// Optional real transcription via OpenAI Whisper. Returns null when no key so
// callers fall back to the demo transcript.
export async function transcribeReal(_fileUrl: string): Promise<TranscriptSegment[] | null> {
  if (!process.env.OPENAI_API_KEY) return null;
  // Wiring point: download the file, POST to the Whisper endpoint with
  // response_format=verbose_json, and map word timings into TranscriptSegment[].
  // Left as an integration seam so the app never hard-depends on a key.
  return null;
}
