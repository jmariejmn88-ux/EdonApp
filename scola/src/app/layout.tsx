import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Scola — pilotage financier scolaire",
  description: "Facturation, paiements, recouvrement et trésorerie des établissements scolaires.",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="fr">
      <body>
        <header className="topbar">
          <a href="/" className="brand">Scola</a>
        </header>
        <main className="container">{children}</main>
      </body>
    </html>
  );
}
