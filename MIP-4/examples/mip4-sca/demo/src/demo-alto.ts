/**
 * Demo Path B — through the self-hosted Alto bundler (SPEC §5.5).
 *
 * Submits the same 3-op bundle as Path A via ERC-4337 RPC
 * (eth_sendUserOperation), flushes the mempool with
 * debug_bundler_sendBundleNow (bundle-mode=manual), and asserts all three
 * userop receipts share one transaction with success true/false/true.
 *
 * Contrast run (`--contrast`): re-delegates Bob to the STOCK
 * Simple7702Account before submission to show the unguarded path.
 *
 * Prereqs:
 *   - npm run setup:testnet
 *   - Alto running: (cd bundler && docker compose --env-file ../.env up -d)
 */
import { readFileSync } from "node:fs";
import { parseEther, toHex, type Address, type Hex } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { ACCOUNTS_FILE, UNGUARDED_ACCOUNT_IMPL, clients, env, requireEnv } from "./config.js";
import { ENTRY_POINT_V08, RESERVE_DIPPED_SELECTOR, artifact, executeCalldata, fmt } from "./lib.js";

const SINK: Address = "0x000000000000000000000000000000000000dEaD";
const contrast = process.argv.includes("--contrast");

let rpcId = 0;
async function altoRpc<T>(method: string, params: unknown[]): Promise<T> {
  const res = await fetch(env.altoRpc, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: ++rpcId, method, params }),
  });
  const json = (await res.json()) as { result?: T; error?: { message: string } };
  if (json.error) throw new Error(`${method}: ${json.error.message}`);
  return json.result as T;
}

async function main() {
  requireEnv(env.mip4AccountImpl, "MIP4_ACCOUNT_IMPL");
  const { publicClient, walletClient } = clients();
  const entryPointAbi = artifact("EntryPoint.sol", "EntryPoint").abi;
  const accountAbi = artifact("Mip4Account.sol", "Mip4Account").abi;

  const supported = await altoRpc<Address[]>("eth_supportedEntryPoints", []);
  if (!supported.map((a) => a.toLowerCase()).includes(ENTRY_POINT_V08.toLowerCase())) {
    console.error(`Alto does not serve EntryPoint v0.8 (got: ${supported.join(", ")})`);
    process.exit(1);
  }

  const keys: Hex[] = JSON.parse(readFileSync(ACCOUNTS_FILE, "utf8"));
  const signers = keys.map((k) => privateKeyToAccount(k));
  const names = ["Alice", "Bob", "Carol"];
  const amounts = [parseEther("0.05"), parseEther("1"), parseEther("0.05")];

  if (contrast) {
    console.log("CONTRAST RUN: re-delegating Bob to UnguardedAccount (same build, no guard)\n");
    const bob = signers[1];
    const authorization = await walletClient.signAuthorization({
      account: bob,
      contractAddress: UNGUARDED_ACCOUNT_IMPL,
    });
    const hash = await walletClient.sendTransaction({ to: bob.address, value: 0n, authorizationList: [authorization] });
    await publicClient.waitForTransactionReceipt({ hash });
  }

  // --- build, sign (via the packed hash from the EntryPoint), submit ---
  // Two valid outcomes for Bob's dipping op:
  //  (a) Alto --chain-type=monad: rejected AT SUBMISSION by the bundler's
  //      per-op reserve simulation (bundler-layer protection; Bob pays nothing)
  //  (b) op accepted and included: the on-chain Mip4ReserveGuard reverts it
  //      inside the bundle (account-layer protection)
  const userOpHashes: (Hex | null)[] = [];
  const rejectionReasons: (string | null)[] = [];
  for (let i = 0; i < 3; i++) {
    const nonce = (await publicClient.readContract({
      address: ENTRY_POINT_V08,
      abi: entryPointAbi,
      functionName: "getNonce",
      args: [signers[i].address, 0n],
    })) as bigint;

    // RPC-format (unpacked) userop for EntryPoint v0.8. Explicit gas limits:
    // Bob's execution reverts by design, so estimation would fail.
    const rpcOp = {
      sender: signers[i].address,
      nonce: toHex(nonce),
      callData: executeCalldata(accountAbi, SINK, amounts[i], "0x"),
      callGasLimit: toHex(300_000n),
      verificationGasLimit: toHex(300_000n),
      preVerificationGas: toHex(60_000n),
      maxFeePerGas: toHex(100_000_000_000n),
      maxPriorityFeePerGas: toHex(2_000_000_000n),
      signature: "0x" as Hex,
    };

    // sign over the canonical hash (packed form) computed by the EntryPoint
    const packed = {
      sender: rpcOp.sender,
      nonce,
      initCode: "0x" as Hex,
      callData: rpcOp.callData,
      accountGasLimits: ("0x" +
        (300_000n).toString(16).padStart(32, "0") +
        (300_000n).toString(16).padStart(32, "0")) as Hex,
      preVerificationGas: 60_000n,
      gasFees: ("0x" +
        (2_000_000_000n).toString(16).padStart(32, "0") +
        (100_000_000_000n).toString(16).padStart(32, "0")) as Hex,
      paymasterAndData: "0x" as Hex,
      signature: "0x" as Hex,
    };
    const userOpHash = (await publicClient.readContract({
      address: ENTRY_POINT_V08,
      abi: entryPointAbi,
      functionName: "getUserOpHash",
      args: [packed],
    })) as Hex;
    rpcOp.signature = await signers[i].sign({ hash: userOpHash });

    try {
      const submitted = await altoRpc<Hex>("eth_sendUserOperation", [rpcOp, ENTRY_POINT_V08]);
      userOpHashes.push(submitted);
      rejectionReasons.push(null);
      console.log(`${names[i]} op submitted: ${submitted}`);
    } catch (e: any) {
      userOpHashes.push(null);
      rejectionReasons.push(e.message);
      console.log(`${names[i]} op REJECTED at submission: ${e.message}`);
    }
  }

  const included = userOpHashes.filter(Boolean) as Hex[];
  if (included.length === 0) {
    console.error("\nNo ops accepted — nothing to bundle.");
    process.exit(1);
  }

  // --- flush the mempool into one bundle ---
  console.log("\nFlushing bundle (debug_bundler_sendBundleNow)...");
  await altoRpc("debug_bundler_sendBundleNow", []);

  // --- await receipts for accepted ops ---
  const receipts: (any | null)[] = [];
  for (let i = 0; i < 3; i++) {
    if (!userOpHashes[i]) {
      receipts.push(null);
      continue;
    }
    let receipt = null;
    for (let tries = 0; tries < 60 && !receipt; tries++) {
      // Alto answers with an error (not null) while the receipt is not yet
      // available, and can transiently fail against the public RPC — retry.
      receipt = await altoRpc<any>("eth_getUserOperationReceipt", [userOpHashes[i]]).catch(() => null);
      if (!receipt) await new Promise((r) => setTimeout(r, 2000));
    }
    if (!receipt) {
      console.error(`${names[i]}: no receipt after 120s`);
      process.exit(1);
    }
    receipts.push(receipt);
  }

  const txHashes = new Set(receipts.filter(Boolean).map((r) => r.receipt.transactionHash));
  console.log(`\nBundle tx: ${[...txHashes].join(", ")}`);
  let bobProtectedBy: string | null = null;
  for (let i = 0; i < 3; i++) {
    if (!receipts[i]) {
      console.log(`  ${names[i]}  rejected pre-bundle (bundler reserve simulation)`);
      if (i === 1) bobProtectedBy = "bundler layer (Alto --chain-type=monad per-op simulation)";
      continue;
    }
    const r = receipts[i];
    const reason = r.reason ?? "";
    const isDip = reason.includes(RESERVE_DIPPED_SELECTOR.slice(2));
    console.log(`  ${names[i]}  success=${r.success}${reason ? ` reason=${reason}${isDip ? " (ReserveDipped())" : ""}` : ""}`);
    if (i === 1 && r.success === false && isDip) bobProtectedBy = "account layer (on-chain Mip4ReserveGuard)";
  }

  const aliceOk = receipts[0]?.success === true;
  const carolOk = receipts[2]?.success === true;
  const ok = txHashes.size === 1 && aliceOk && carolOk && bobProtectedBy !== null;
  console.log(
    ok
      ? `\nAlice's and Carol's ops landed in one bundle tx; Bob's dipping op was stopped by the ${bobProtectedBy}. ✔`
      : "\nUnexpected outcome — inspect receipts above.",
  );
  const bob = signers[1];
  console.log(`Bob balance: ${fmt(await publicClient.getBalance({ address: bob.address }))} (still >= 10 MON)`);
  process.exitCode = ok ? 0 : 1;
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
