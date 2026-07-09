import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "cre8tor — Your AI Head of Content",
  description:
    "cre8tor decides what to post, writes it in your voice, and grows your audience across LinkedIn, Instagram & X. Your personal AI content advisor.",
  applicationName: "cre8tor",
  openGraph: {
    title: "cre8tor — Your AI Head of Content",
    description:
      "Decide what to post, write in your voice, and grow. The AI content partner for serious creators.",
    type: "website",
  },
  metadataBase: new URL("https://cre8tor.ai"),
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" className="dark">
      <body className="min-h-screen bg-bg text-ink antialiased">{children}</body>
    </html>
  );
}
