import type { ChatMode } from "./types";

// A capable offline fallback used when no ANTHROPIC_API_KEY is set, so the
// product is fully explorable in demo mode. It produces context-aware,
// non-trivial responses based on the user's last message and mode.

const hooks = [
  "Here's what nobody tells you:",
  "Unpopular opinion:",
  "I learned this the hard way:",
  "Steal this framework:",
  "The truth about {topic}:",
];

function titleCase(s: string) {
  return s.replace(/\b\w/g, (c) => c.toUpperCase());
}

export function demoReply(mode: ChatMode, userText: string, history: number): string {
  const topic = extractTopic(userText);

  if (mode === "interview") {
    const qs = [
      `Love it. So when it comes to ${topic}, what's the moment you realized the conventional advice was wrong?`,
      `That's gold. Can you give me a specific example — what actually happened, and what did it cost you?`,
      `Okay, and if a beginner came to you today about ${topic}, what's the ONE thing you'd tell them to do first?`,
      `Perfect. I think we've got a great story here. Want me to turn this into a post? I'll write it in your voice.`,
    ];
    return qs[Math.min(history, qs.length - 1)];
  }

  if (mode === "analyze") {
    return `Looking at your recent posts, here's what stands out:

**What's resonating** 📈
Your highest-performing posts share one thing: they open with a *specific* number or a contrarian claim, then pay it off fast. Your "$0 growth playbook" post did 512k impressions because the promise was concrete and the delivery was tight.

**Patterns in your top posts**
1. Short first line (under 8 words) → 2.3× the reach of longer openers
2. Story → lesson structure outperforms pure how-to by ~40% on engagement
3. Posts that end with an invitation ("steal this", "what would you add?") get 3× the comments

**What to create next**
1. A "mistakes I made" post about ${topic} — vulnerability + specificity is your sweet spot
2. Turn your best comment thread into a standalone post
3. A carousel breaking your ${topic} framework into 5 steps

Want me to draft any of these in your voice?`;
  }

  // voice / chat → write a post
  const hook = hooks[history % hooks.length].replace("{topic}", topic);
  return `${hook}

Most people approach ${topic} backwards. They optimize for reach before they've earned trust.

Here's the shift that changed everything for me:

→ Lead with the outcome your audience wants
→ Prove it with one specific story, not five vague tips
→ Make the next step obvious

Do that consistently and the algorithm becomes a rounding error. Your audience carries you.

The creators who win aren't the loudest. They're the clearest.

---
*Want a punchier hook or a different angle? Just say the word — or ask me to tailor it for LinkedIn vs X.*`;
}

function extractTopic(text: string): string {
  const cleaned = text
    .toLowerCase()
    .replace(/write (me )?a (post|thread|tweet) (about|on)/g, "")
    .replace(/(help me with|about|on|for|the)/g, " ")
    .trim();
  const words = cleaned.split(/\s+/).filter((w) => w.length > 3).slice(0, 3);
  return words.length ? titleCase(words.join(" ")) : "your niche";
}
