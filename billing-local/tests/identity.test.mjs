import test from "node:test";
import assert from "node:assert/strict";
import { generateKeyPair, exportJWK, createLocalJWKSet, SignJWT } from "jose";
import { createIdentity } from "../identity.mjs";
test("verified identity rejects foreign issuer, audience, signature and expired tokens", async () => {
  const keys = await generateKeyPair("RS256"),
    jwk = await exportJWK(keys.publicKey);
  jwk.kid = "fixture";
  const config = {
    issuer: "https://identity.example",
    audience: "s2t",
    jwks: "https://identity.example/jwks",
  };
  const verify = createIdentity(config, createLocalJWKSet({ keys: [jwk] }));
  const token = (
    issuer = config.issuer,
    audience = config.audience,
    expiry = "1h",
    key = keys.privateKey,
  ) =>
    new SignJWT({})
      .setProtectedHeader({ alg: "RS256", kid: "fixture" })
      .setSubject("user1")
      .setIssuer(issuer)
      .setAudience(audience)
      .setIssuedAt()
      .setExpirationTime(expiry)
      .sign(key);
  assert.equal(await verify(await token()), "https://identity.example:user1");
  await assert.rejects(verify(await token("https://attacker.example")));
  await assert.rejects(verify(await token(config.issuer, "other-app")));
  await assert.rejects(verify(await token(config.issuer, config.audience, "-1h")));
  const wrong = await generateKeyPair("RS256");
  await assert.rejects(verify(await token(config.issuer, config.audience, "1h", wrong.privateKey)));
});
