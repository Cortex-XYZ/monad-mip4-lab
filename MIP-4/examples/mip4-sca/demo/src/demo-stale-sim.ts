/**
 * Demo: the STALE SIMULATION case — why the on-chain guard matters even
 * though bundlers simulate ops before accepting them.
 *
 * A bundler's simulation is a forecast made at time T0; the bundle executes
 * at T1. This script manufactures the T0→T1 divergence deterministically:
 *
 *   1. Bob holds ~11.65 MON. His op sends 1 MON -> forecast shows 10.65 left,
 *      no dip. The simulated bundle is clean — ANY bundler would accept it.
 *   2. AFTER the ops are signed and "accepted", Bob's balance drops by 1 MON
 *      (a plain transfer — exactly what a wallet owner might do while their
 *      userop sits in a mempool).
 *   3. The already-signed bundle is broadcast unchanged. At execution Bob has
 *      ~10.65; sending 1 MON leaves ~9.65 < 10 MON -> the op dips FOR REAL.
 *
 * Run twice — Bob guarded (Mip4Account), then Bob unguarded (UnguardedAccount):
 *   guarded   -> bundle COMMITS; only Bob's op fails (ReserveDipped)
 *   unguarded -> the protocol REVERTS THE ENTIRE BUNDLE at end-of-tx
 *
 * Usage: npm run demo:stale        (runs both variants back to back)
 * Prereq: npm run setup:testnet
 */
import { readFileSync } from "node:fs";
import { decodeEventLog, parseEther, encodeFunctionData, type Address, type Hex } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { ACCOUNTS_FILE, UNGUARDED_ACCOUNT_IMPL, clients, env, requireEnv } from "./config.js";
import {
  ENTRY_POINT_V08,
  RESERVE_DIPPED_SELECTOR,
  artifact,
  buildUserOp,
  executeCalldata,
  fmt,
  type PackedUserOperation,
} from "./lib.js";

const SINK: Address = "0x000000000000000000000000000000000000dEaD";
const BOB_START = parseEther("11.65"); // headroom so the T0 forecast is clean

async function main() {
  const mip4Impl = requireEnv(env.mip4AccountImpl, "MIP4_ACCOUNT_IMPL");
  const { funder, publicClient, walletClient } = clients();
  const entryPointAbi = artifact("EntryPoint.sol", "EntryPoint").abi;
  const accountAbi = artifact("Mip4Account.sol", "Mip4Account").abi;

  const keys: Hex[] = JSON.parse(readFileSync(ACCOUNTS_FILE, "utf8"));
  const [alice, bob, carol] = keys.map((k) => privateKeyToAccount(k));
  const names = ["Alice", "Bob", "Carol"];
  const signers = [alice, bob, carol];
  const amounts = [parseEther("0.05"), parseEther("1"), parseEther("0.05")];

  async function sendChecked(tx: () => Promise<Hex>, label: string) {
    for (let attempt = 1; attempt <= 4; attempt++) {
      const receipt = await publicClient.waitForTransactionReceipt({ hash: await tx() });
      if (receipt.status === "success") return;
      console.log(`  ${label}: reverted (reserve rule) — retrying after k-block window`);
      await new Promise((r) => setTimeout(r, 6000));
    }
    throw new Error(`${label} kept reverting`);
  }

  async function delegateBob(impl: Address) {
    const expected = ("0xef0100" + impl.slice(2)).toLowerCase();
    if ((await publicClient.getCode({ address: bob.address }))?.toLowerCase() === expected) return;
    const authorization = await walletClient.signAuthorization({ account: bob, contractAddress: impl });
    await sendChecked(
      () => walletClient.sendTransaction({ to: bob.address, value: 0n, authorizationList: [authorization] }),
      "delegate Bob",
    );
  }

  async function runVariant(label: string, impl: Address) {
    console.log(`\n${"=".repeat(64)}\n${label}\n${"=".repeat(64)}`);
    await delegateBob(impl);

    // Bob starts with clean-forecast headroom
    const bobBalance = await publicClient.getBalance({ address: bob.address });
    if (bobBalance < BOB_START) {
      await sendChecked(
        () => walletClient.sendTransaction({ to: bob.address, value: BOB_START - bobBalance }),
        "top up Bob",
      );
    }
    console.log(`Bob balance at T0: ${fmt(await publicClient.getBalance({ address: bob.address }))}`);

    // --- T0: build + sign ops, and make the bundler's forecast ---
    const ops: PackedUserOperation[] = [];
    for (let i = 0; i < 3; i++) {
      const nonce = (await publicClient.readContract({
        address: ENTRY_POINT_V08,
        abi: entryPointAbi,
        functionName: "getNonce",
        args: [signers[i].address, 0n],
      })) as bigint;
      const op = buildUserOp({
        sender: signers[i].address,
        nonce,
        callData: executeCalldata(accountAbi, SINK, amounts[i], "0x"),
        maxFeePerGas: 100_000_000_000n,
        maxPriorityFeePerGas: 2_000_000_000n,
      });
      const userOpHash = (await publicClient.readContract({
        address: ENTRY_POINT_V08,
        abi: entryPointAbi,
        functionName: "getUserOpHash",
        args: [op],
      })) as Hex;
      op.signature = await signers[i].sign({ hash: userOpHash });
      ops.push(op);
    }

    const handleOpsData = encodeFunctionData({
      abi: entryPointAbi,
      functionName: "handleOps",
      args: [ops, funder.address],
    });

    const forecast = await publicClient
      .call({ to: ENTRY_POINT_V08, data: handleOpsData, account: funder.address })
      .then(() => "CLEAN — a bundler would accept and broadcast this bundle")
      .catch((e: any) => `FAILED (${(e.shortMessage ?? e.message).slice(0, 60)})`);
    console.log(`T0 bundler forecast (eth_call of the exact bundle): ${forecast}`);

    // --- T0 -> T1: state moves while the signed bundle is "in flight" ---
    const bobKey = keys[1];
    const bobWallet = (await import("viem")).createWalletClient({
      chain: publicClient.chain,
      transport: (await import("viem")).http(env.rpc),
      account: privateKeyToAccount(bobKey),
    });
    await sendChecked(
      () => bobWallet.sendTransaction({ to: funder.address, value: parseEther("1") }),
      "Bob's interleaved 1 MON transfer",
    );
    console.log(`T1 state moved: Bob spent 1 MON elsewhere -> ${fmt(await publicClient.getBalance({ address: bob.address }))}`);
    console.log("Bob's pending op now dips at execution. The forecast is stale.");

    // --- T1: broadcast the SAME signed bundle ---
    console.log("Broadcasting the already-signed bundle unchanged...");
    const bundleHash = await walletClient.sendTransaction({
      to: ENTRY_POINT_V08,
      data: handleOpsData,
      gas: 1_200_000n,
    });
    const receipt = await publicClient.waitForTransactionReceipt({ hash: bundleHash });

    if (receipt.status !== "success") {
      console.log(`\nRESULT: BUNDLE TX REVERTED — ${bundleHash}`);
      console.log("The protocol's end-of-tx reserve check destroyed ALL THREE users' ops.");
      console.log("The bundler burned the full gas cost and earned nothing.");
      return { committed: false, tx: bundleHash };
    }

    console.log(`\nRESULT: BUNDLE COMMITTED — ${bundleHash}`);
    let i = 0;
    for (const log of receipt.logs) {
      try {
        const ev = decodeEventLog({ abi: entryPointAbi, data: log.data, topics: log.topics }) as any;
        if (ev.eventName === "UserOperationEvent") console.log(`  ${names[i++]}  success=${ev.args.success}`);
        if (ev.eventName === "UserOperationRevertReason")
          console.log(`         reason=${ev.args.revertReason}${ev.args.revertReason === RESERVE_DIPPED_SELECTOR ? " (ReserveDipped())" : ""}`);
      } catch {}
    }
    return { committed: true, tx: bundleHash };
  }

  const guarded = await runVariant("VARIANT 1 — Bob GUARDED (Mip4Account)", mip4Impl);
  const unguarded = await runVariant("VARIANT 2 — Bob UNGUARDED (UnguardedAccount)", UNGUARDED_ACCOUNT_IMPL);

  // restore Bob's guard
  await delegateBob(mip4Impl);

  console.log(`\n${"=".repeat(64)}\nSAME stale forecast, two endings:`);
  console.log(`  guarded:   bundle ${guarded.committed ? "COMMITTED — only Bob's op failed" : "reverted (?)"}  ${guarded.tx}`);
  console.log(`  unguarded: bundle ${unguarded.committed ? "committed (?)" : "REVERTED — all 3 users wiped out"}  ${unguarded.tx}`);
  console.log("\nA bundler's simulation is a forecast; only the on-chain guard is");
  console.log("present at execution time, when the reserve check actually runs.");
  const ok = guarded.committed && !unguarded.committed;
  process.exitCode = ok ? 0 : 1;
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
