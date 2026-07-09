import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import type { Abi, Address, Hex, PublicClient } from "viem";
import { concatHex, encodeFunctionData, numberToHex, pad, toHex } from "viem";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..");

/** Canonical addresses / constants (SPEC §7.1). */
export const ENTRY_POINT_V08: Address = "0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108";
export const MIP4_PRECOMPILE: Address = "0x0000000000000000000000000000000000001001";
export const RESERVE = 10n * 10n ** 18n; // 10 MON
export const RESERVE_DIPPED_SELECTOR: Hex = "0x417680f0"; // bytes4(keccak256("ReserveDipped()")), `cast sig "ReserveDipped()"`

/** Load a forge artifact (abi + creation bytecode). */
export function artifact(file: string, contract: string): { abi: Abi; bytecode: Hex } {
  const json = JSON.parse(readFileSync(join(root, "out", file, `${contract}.json`), "utf8"));
  return { abi: json.abi as Abi, bytecode: json.bytecode.object as Hex };
}

/** PackedUserOperation struct fields for EntryPoint v0.8. */
export interface PackedUserOperation {
  sender: Address;
  nonce: bigint;
  initCode: Hex;
  callData: Hex;
  accountGasLimits: Hex;
  preVerificationGas: bigint;
  gasFees: Hex;
  paymasterAndData: Hex;
  signature: Hex;
}

/** Pack two uint128s into the bytes32 layout EntryPoint v0.8 expects. */
export function packUints(high: bigint, low: bigint): Hex {
  return concatHex([pad(numberToHex(high), { size: 16 }), pad(numberToHex(low), { size: 16 })]);
}

export function buildUserOp(params: {
  sender: Address;
  nonce: bigint;
  callData: Hex;
  verificationGasLimit?: bigint;
  callGasLimit?: bigint;
  preVerificationGas?: bigint;
  maxPriorityFeePerGas?: bigint;
  maxFeePerGas?: bigint;
}): PackedUserOperation {
  return {
    sender: params.sender,
    nonce: params.nonce,
    initCode: "0x",
    callData: params.callData,
    accountGasLimits: packUints(params.verificationGasLimit ?? 300_000n, params.callGasLimit ?? 300_000n),
    preVerificationGas: params.preVerificationGas ?? 60_000n,
    gasFees: packUints(params.maxPriorityFeePerGas ?? 1_000_000_000n, params.maxFeePerGas ?? 5_000_000_000n),
    paymasterAndData: "0x",
    signature: "0x",
  };
}

export function executeCalldata(accountAbi: Abi, target: Address, value: bigint, data: Hex): Hex {
  return encodeFunctionData({ abi: accountAbi, functionName: "execute", args: [target, value, data] });
}

/** Wait until an RPC endpoint answers eth_chainId. */
export async function waitForRpc(url: string, timeoutMs = 15_000): Promise<void> {
  const started = Date.now();
  while (true) {
    try {
      const res = await fetch(url, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "eth_chainId", params: [] }),
      });
      if (res.ok) return;
    } catch {}
    if (Date.now() - started > timeoutMs) throw new Error(`RPC at ${url} not ready after ${timeoutMs}ms`);
    await new Promise((r) => setTimeout(r, 250));
  }
}

/** Tiny assertion helper with a running tally. */
export class Checker {
  passed = 0;
  failed = 0;

  check(name: string, cond: boolean, detail?: string) {
    if (cond) {
      this.passed++;
      console.log(`  ✓ ${name}`);
    } else {
      this.failed++;
      console.error(`  ✗ ${name}${detail ? ` — ${detail}` : ""}`);
    }
  }

  summary(label: string): boolean {
    const ok = this.failed === 0;
    console.log(`\n${ok ? "PASS" : "FAIL"}: ${label} — ${this.passed} passed, ${this.failed} failed`);
    return ok;
  }
}

/** Fetch MON balance shorthand. */
export async function bal(client: PublicClient, addr: Address): Promise<bigint> {
  return client.getBalance({ address: addr });
}

export const fmt = (wei: bigint) => `${Number(wei) / 1e18} MON`;
