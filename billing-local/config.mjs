import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { configuration as baseConfiguration } from "./config-core.mjs";
export function configuration(env = process.env) {
  return baseConfiguration(env, {
    root: fileURLToPath(new URL(".", import.meta.url)),
    dataDir: resolve(env.S2T_BILLING_DATA_DIR || fileURLToPath(new URL(".data", import.meta.url))),
    readFile: readFileSync
  });
}
