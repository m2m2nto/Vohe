import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Vohe Dictionaries",
  description: "Edit Vohe vocabulary decks and export them as .txt",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>
        <main>{children}</main>
      </body>
    </html>
  );
}
