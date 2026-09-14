import { createRemoteJWKSet, jwtVerify } from "jose";
import { requireThat } from "./money.mjs";
export function createIdentity(config, keyResolver) {
  if (!config) return null;
  const jwks = keyResolver || createRemoteJWKSet(new URL(config.jwks), { timeoutDuration: 5000 });
  return async (token) => {
    const { payload } = await jwtVerify(token, jwks, {
      issuer: config.issuer,
      audience: config.audience,
      algorithms: ["RS256", "ES256"],
      requiredClaims: ["sub", "exp", "iat"],
    });
    requireThat(
      typeof payload.sub === "string" && payload.sub.length > 0 && payload.sub.length <= 200,
      "identity",
      "Invalid account identity.",
      401,
    );
    return `${config.issuer}:${payload.sub}`;
  };
}
