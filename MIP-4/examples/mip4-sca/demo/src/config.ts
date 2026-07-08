import { existsSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { createPublicClient, createWalletClient, defineChain, http, type Address, type Hex } from "viem";
import { privateKeyToAccount } from "viem/accounts";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..");

/** Minimal .env loader (project root). Values already in process.env win. */
function loadEnv() {
  const path = join(root, ".env");
  if (!existsSync(path)) return;
  for (const line of readFileSync(path, "utf8").split("\n")) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/);
    if (m && !(m[1] in process.env)) process.env[m[1]] = m[2];
  }
}
loadEnv();

export const env = {
  rpc: process.env.MONAD_TESTNET_RPC ?? "https://testnet-rpc.monad.xyz",
  funderKey: process.env.FUNDER_KEY as Hex | undefined,
  mip4AccountImpl: process.env.MIP4_ACCOUNT_IMPL as Address | undefined,
  altoRpc: process.env.ALTO_RPC ?? "http://localhost:4337",
};

export const monadTestnet = defineChain({
  id: 10143,
  name: "Monad Testnet",
  nativeCurrency: { name: "MON", symbol: "MON", decimals: 18 },
  rpcUrls: { default: { http: [env.rpc] } },
});

/** Our UnguardedAccount control impl (contrast runs): identical build to
 *  Mip4Account minus the reserve guard. Deployed via CREATE2 (script/DeployUnguardedAccount.s.sol). */
export const UNGUARDED_ACCOUNT_IMPL: Address = "0x6750919E4a48CcEDA04d1e2b406328d6350861b7";

/** Canonical stock Simple7702Account v0.8 on Monad testnet (alternative control). */
export const STOCK_SIMPLE7702_IMPL: Address = "0xe6Cae83BdE06E4c305530e199D7217f42808555B";

export const ACCOUNTS_FILE = join(root, "demo", ".accounts.json");

export function requireEnv<T>(value: T | undefined, name: string): T {
  if (value === undefined || value === ("" as unknown)) {
    console.error(`Missing ${name} — set it in .env (see .env.example)`);
    process.exit(1);
  }
  return value;
}

export function clients() {
  const funder = privateKeyToAccount(requireEnv(env.funderKey, "FUNDER_KEY"));
  const publicClient = createPublicClient({ chain: monadTestnet, transport: http() });
  const walletClient = createWalletClient({ chain: monadTestnet, transport: http(), account: funder });
  return { funder, publicClient, walletClient };
}
