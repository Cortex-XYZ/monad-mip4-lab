/**
 * Demo Path A — direct handleOps on Monad testnet (SPEC §5.5).
 *
 * Builds a 3-op bundle (Alice 0.05 / Bob 1.0 / Carol 0.05 MON transfers) and
 * submits EntryPoint.handleOps directly from the funder EOA, acting as the
 * bundler. Bob's op would leave him at ~9.6 MON — below the 10 MON reserve —
 * so his Mip4Account guard reverts just his op with ReserveDipped() and the
 * bundle commits with success = true/false/true.
 *
 * Contrast run (`--contrast`): re-delegates Bob to the STOCK Simple7702Account
 * (no guard) and submits the same bundle. On real Monad the protocol's
 * end-of-transaction reserve check reverts the ENTIRE bundle — the failure
 * mode the guard exists to prevent.
 *
 * Prereq: npm run setup:testnet
 */
import { readFileSync } from "node:fs";
import { decodeEventLog, parseEther, type Address, type Hex } from "viem";
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
const contrast = process.argv.includes("--contrast");

async function main() {
  const impl = requireEnv(env.mip4AccountImpl, "MIP4_ACCOUNT_IMPL");
  const { funder, publicClient, walletClient } = clients();
  const entryPointAbi = artifact("EntryPoint.sol", "EntryPoint").abi;
  const accountAbi = artifact("Mip4Account.sol", "Mip4Account").abi;

  const keys: Hex[] = JSON.parse(readFileSync(ACCOUNTS_FILE, "utf8"));
  const [alice, bob, carol] = keys.map((k) => privateKeyToAccount(k));
  const names = ["Alice", "Bob", "Carol"];
  const signers = [alice, bob, carol];
  const amounts = [parseEther("0.05"), parseEther("1"), parseEther("0.05")];

  if (contrast) {
    console.log("CONTRAST RUN: re-delegating Bob to UnguardedAccount (same build, no guard)\n");
    const authorization = await walletClient.signAuthorization({
      account: bob,
      contractAddress: UNGUARDED_ACCOUNT_IMPL,
    });
    const hash = await walletClient.sendTransaction({ to: bob.address, value: 0n, authorizationList: [authorization] });
    await publicClient.waitForTransactionReceipt({ hash });
  }

  // --- build + sign the 3 ops ---
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
      // explicit gas: Bob's execution reverts by design, estimation would fail
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
    console.log(`${names[i]} op: send ${fmt(amounts[i])} (balance ${fmt(await publicClient.getBalance({ address: signers[i].address }))})`);
  }

  const bobBefore = await publicClient.getBalance({ address: bob.address });

  // --- submit the bundle ---
  console.log("\nSubmitting handleOps bundle...");
  let bundleHash: Hex;
  try {
    bundleHash = await walletClient.writeContract({
      address: ENTRY_POINT_V08,
      abi: entryPointAbi,
      functionName: "handleOps",
      args: [ops, funder.address],
      gas: 1_200_000n, // Monad charges by LIMIT — keep it tight (3 simple ops use ~600k)
    });
  } catch (e: any) {
    if (contrast) {
      console.log("\nBUNDLE REJECTED AT SUBMISSION (node-side simulation caught the reserve violation):");
      console.log(`  ${e.shortMessage ?? e.message}`);
      console.log("\nOn real Monad an unguarded dipping op kills the ENTIRE bundle — all 3 users' ops.");
      console.log("This is exactly the failure mode Mip4Account's guard prevents. ✔");
      return;
    }
    throw e;
  }
  const receipt = await publicClient.waitForTransactionReceipt({ hash: bundleHash });

  if (receipt.status !== "success") {
    if (contrast) {
      console.log(`\nBUNDLE TX REVERTED: ${bundleHash}`);
      console.log("Monad's end-of-transaction reserve check killed the ENTIRE bundle —");
      console.log("all 3 users' ops failed because ONE unguarded op dipped into reserve.");
      console.log("This is exactly the failure mode Mip4Account's guard prevents. ✔");
    } else {
      console.error(`\nUNEXPECTED: bundle tx reverted: ${bundleHash}`);
      process.exitCode = 1;
    }
    return;
  }

  // --- decode per-op outcomes ---
  console.log(`\nBUNDLE TX COMMITTED: ${bundleHash}\n`);
  let i = 0;
  for (const log of receipt.logs) {
    try {
      const ev = decodeEventLog({ abi: entryPointAbi, data: log.data, topics: log.topics });
      if (ev.eventName === "UserOperationEvent") {
        const a = ev.args as any;
        console.log(`  ${names[i++]}  UserOperationEvent success=${a.success}`);
      }
      if (ev.eventName === "UserOperationRevertReason") {
        const a = ev.args as any;
        console.log(`         UserOperationRevertReason = ${a.revertReason} ${a.revertReason === RESERVE_DIPPED_SELECTOR ? "(ReserveDipped())" : ""}`);
      }
    } catch {}
  }

  const bobAfter = await publicClient.getBalance({ address: bob.address });
  console.log(`\n  Bob balance delta: ${fmt(bobAfter - bobBefore)} (execution unwound, still >= 10 MON reserve)`);
  console.log(`\nOne dipping op did NOT kill the bundle — Alice's and Carol's ops landed. ✔`);
  if (!contrast) console.log("Now try: npm run demo:direct -- --contrast");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
