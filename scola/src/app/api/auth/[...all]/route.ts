// Point d'entrée HTTP de Better Auth (inscription, connexion, 2FA...).
import { toNextJsHandler } from "better-auth/next-js";
import { auth } from "@/lib/auth";

export const { GET, POST } = toNextJsHandler(auth);
