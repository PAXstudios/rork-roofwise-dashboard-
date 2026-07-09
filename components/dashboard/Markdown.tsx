"use client";

// Minimal, safe markdown-ish renderer for chat content. Handles paragraphs,
// bold, bullet/numbered lists, and headings — no raw HTML injection.
import { Fragment } from "react";

function inline(text: string, keyBase: string) {
  // split on **bold**
  const parts = text.split(/(\*\*[^*]+\*\*)/g);
  return parts.map((p, i) => {
    if (p.startsWith("**") && p.endsWith("**")) {
      return <strong key={`${keyBase}-b-${i}`}>{p.slice(2, -2)}</strong>;
    }
    return <Fragment key={`${keyBase}-t-${i}`}>{p}</Fragment>;
  });
}

export function Markdown({ content }: { content: string }) {
  const lines = content.split("\n");
  const blocks: JSX.Element[] = [];
  let list: { ordered: boolean; items: string[] } | null = null;
  let key = 0;

  const flush = () => {
    if (!list) return;
    const items = list.items.map((it, i) => (
      <li key={`li-${key}-${i}`}>{inline(it, `li-${key}-${i}`)}</li>
    ));
    blocks.push(
      list.ordered ? (
        <ol key={`ol-${key++}`}>{items}</ol>
      ) : (
        <ul key={`ul-${key++}`}>{items}</ul>
      )
    );
    list = null;
  };

  for (const raw of lines) {
    const line = raw.trimEnd();
    if (!line.trim()) {
      flush();
      continue;
    }
    const h = line.match(/^(#{1,3})\s+(.*)$/);
    if (h) {
      flush();
      const level = h[1].length;
      const Tag = (level === 1 ? "h1" : level === 2 ? "h2" : "h3") as keyof JSX.IntrinsicElements;
      blocks.push(<Tag key={`h-${key++}`}>{inline(h[2], `h-${key}`)}</Tag>);
      continue;
    }
    const ul = line.match(/^[-•→*]\s+(.*)$/);
    const ol = line.match(/^\d+[.)]\s+(.*)$/);
    if (ul) {
      if (!list || list.ordered) {
        flush();
        list = { ordered: false, items: [] };
      }
      list.items.push(ul[1]);
      continue;
    }
    if (ol) {
      if (!list || !list.ordered) {
        flush();
        list = { ordered: true, items: [] };
      }
      list.items.push(ol[1]);
      continue;
    }
    if (line.trim() === "---") {
      flush();
      blocks.push(<hr key={`hr-${key++}`} className="my-3 border-line" />);
      continue;
    }
    flush();
    blocks.push(<p key={`p-${key++}`}>{inline(line, `p-${key}`)}</p>);
  }
  flush();

  return <div className="prose-chat">{blocks}</div>;
}
