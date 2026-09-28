// Filtre rapide (Next.js 16 : proxy.ts remplace middleware.ts).
// Vérifie seulement la PRÉSENCE du cookie de session pour rediriger tôt ;
// la vérification réelle de la session est faite côté serveur dans chaque
// page protégée (requireSession).
import { NextResponse, type NextRequest } from "next/server";
import { getSessionCookie } from "better-auth/cookies";

export function proxy(request: NextRequest) {
  if (!getSessionCookie(request)) {
    return NextResponse.redirect(new URL("/connexion", request.url));
  }
  return NextResponse.next();
}

export const config = {
  matcher: ["/tableau-de-bord/:path*", "/onboarding/:path*", "/securite/:path*"],
};
