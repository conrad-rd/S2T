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

test('private live credits accept only the signed verified email claim', async () => {
  const pair = await generateKeyPair('RS256');
  const jwk = { ...await exportJWK(pair.publicKey), kid: 'email-fixture' };
  const config = { issuer: 'https://clerk.example.com', audience: 's2t-credits', jwks: 'https://clerk.example.com/jwks', allowedEmail: 'owner@example.com' };
  const verify = createIdentity(config, createLocalJWKSet({ keys: [jwk] }));
  const sign = claims => new SignJWT(claims).setProtectedHeader({ alg: 'RS256', kid: jwk.kid }).setSubject('user_fixture').setIssuer(config.issuer).setAudience(config.audience).setIssuedAt().setExpirationTime('1m').sign(pair.privateKey);
  assert.equal(await verify(await sign({ email: 'owner@example.com', email_verified: true })), config.issuer + ':user_fixture');
  for (const claims of [{}, { email: 'other@example.com', email_verified: true }, { email: 'owner@example.com', email_verified: false }, { email: 'owner@example.com', email_verified: 'true' }]) await assert.rejects(verify(await sign(claims)), /not approved/);
});
