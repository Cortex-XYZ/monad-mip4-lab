/**
 * Anvil integration suite (SPEC §5.6, revised): verifies the MIP-4 reserve
 * guard against REAL Monad reserve semantics using the Monad foundry fork's
 * `anvil --monad` (monad-revm: live 0x1001 precompile + failing-set tracking).
 *
 * Covers what `forge test` cannot (the fork's test EVM does not track
 * reserve debits):
 *   1. guard dip -> ReserveDipped() revert + frame unwind
 *   2. transient dip that recovers within the frame -> succeeds
 *   3. innocence rule: pre-existing dip -> guarded call proceeds
 *   4. exact-reserve boundary -> succeeds
 *   5. full EntryPoint v0.8 3-op bundle: middle op dips -> success true/false/true,
 *      ReserveDipped surfaced in UserOperationRevertReason, balances unwound,
 *      gas charged from deposit
 *   6. negative control: stock (unguarded) Simple7702Account leaves the
 *      account dipped (would revert the whole tx on real Monad)
 *
 * Note: anvil does NOT implement Monad's end-of-tx reserve enforcement, so
 * the whole-bundle protocol revert itself is demonstrated on testnet (demo/).
 *
 * Usage: npm run integration:anvil   (spawns its own anvil on port 8546)
 */
import { spawn } from "node:child_process";
import {
  createPublicClient,
  createTestClient,
  createWalletClient,
  decodeEventLog,
  encodeFunctionData,
  http,
  parseEther,
  type Address,
  type Hex,
} from "viem";
import { generatePrivateKey, privateKeyToAccount } from "viem/accounts";
import { foundry } from "viem/chains";
import {
  Checker,
  ENTRY_POINT_V08,
  RESERVE_DIPPED_SELECTOR,
  artifact,
  buildUserOp,
  executeCalldata,
  fmt,
  waitForRpc,
  type PackedUserOperation,
} from "./lib.js";

const PORT = 8546;
const RPC = `http://127.0.0.1:${PORT}`;
// anvil default account #0
const FUNDER_KEY: Hex = "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80";

const transport = http(RPC);
const publicClient = createPublicClient({ chain: foundry, transport });
const testClient = createTestClient({ chain: foundry, mode: "anvil", transport });
const funder = privateKeyToAccount(FUNDER_KEY);
const walletClient = createWalletClient({ chain: foundry, transport, account: funder });

async function deploy(file: string, contract: string): Promise<{ address: Address; abi: any }> {
  const { abi, bytecode } = artifact(file, contract);
  const hash = await walletClient.deployContract({ abi, bytecode, args: [] });
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  if (!receipt.contractAddress) throw new Error(`deploy failed: ${contract}`);
  return { address: receipt.contractAddress, abi };
}

/** Delegate an EOA to an implementation via a real EIP-7702 type-4 tx. */
async function delegate(eoaKey: Hex, impl: Address): Promise<Address> {
  const eoa = privateKeyToAccount(eoaKey);
  const authorization = await walletClient.signAuthorization({ account: eoa, contractAddress: impl });
  const hash = await walletClient.sendTransaction({
    to: eoa.address,
    authorizationList: [authorization],
    value: 0n,
  });
  await publicClient.waitForTransactionReceipt({ hash });
  const code = await publicClient.getCode({ address: eoa.address });
  if (!code?.toLowerCase().startsWith("0xef0100")) throw new Error(`delegation failed for ${eoa.address}`);
  return eoa.address;
}

/** DB-level funding so the balance counts as the tx-start original balance. */
async function fund(addr: Address, amount: bigint) {
  await testClient.setBalance({ address: addr, value: amount });
  await testClient.mine({ blocks: 1 });
}

async function main() {
  console.log("Starting anvil --monad ...");
  const anvil = spawn("anvil", ["--monad", "--port", String(PORT), "--silent"], { stdio: "ignore" });
  const stop = () => anvil.kill();
  process.on("exit", stop);

  try {
    await waitForRpc(RPC);
    const c = new Checker();

    // --- deploy implementations & helpers ---
    const mip4Account = await deploy("Mip4Account.sol", "Mip4Account");
    const stockAccount = await deploy("Simple7702Account.sol", "Simple7702Account");
    const orchestrator = await deploy("TestDelegates.sol", "Orchestrator");
    const rebounder = await deploy("TestDelegates.sol", "Rebounder");
    const harnessImpl = await deploy("TestDelegates.sol", "GuardHarnessImpl");
    const spenderImpl = await deploy("TestDelegates.sol", "SpenderImpl");

    // EntryPoint v0.8 at its canonical address: deploy anywhere, copy code.
    // (OZ EIP712 recomputes the domain separator when address(this) differs
    // from the cached immutable, so the copy is hash-correct.)
    const epDeployed = await deploy("EntryPoint.sol", "EntryPoint");
    const epCode = await publicClient.getCode({ address: epDeployed.address });
    await testClient.setCode({ address: ENTRY_POINT_V08, bytecode: epCode! });
    const entryPoint = { address: ENTRY_POINT_V08, abi: epDeployed.abi };
    c.check("EntryPoint v0.8 installed at canonical address", (await publicClient.getCode({ address: ENTRY_POINT_V08 }))!.length > 2);

    const reserveDippedSelector = RESERVE_DIPPED_SELECTOR;

    // --- guard scenarios (via delegated EOAs + orchestrator, one tx each) ---
    console.log("\n[1] Guard dip -> revert + unwind");
    const gKey = generatePrivateKey();
    const guardedEoa = await delegate(gKey, harnessImpl.address);
    await fund(guardedEoa, parseEther("10.5"));
    const recipient: Address = "0x1111111111111111111111111111111111111111";

    const dipResult = (await publicClient.readContract({
      address: orchestrator.address,
      abi: orchestrator.abi,
      functionName: "guardedDip",
      args: [guardedEoa, recipient, parseEther("1")],
    })) as [boolean, boolean, bigint];
    c.check("guarded 1 MON spend reverted", dipResult[0]);
    c.check("revert reason is ReserveDipped()", dipResult[1]);
    c.check("balance restored inside tx", dipResult[2] === parseEther("10.5"), fmt(dipResult[2]));

    console.log("\n[2] Transient dip recovers within frame");
    const transientOk = await publicClient
      .simulateContract({
        address: guardedEoa,
        abi: harnessImpl.abi,
        functionName: "doGuarded",
        args: [rebounder.address, parseEther("2"), "0x"],
        account: funder,
      })
      .then(() => true)
      .catch(() => false);
    c.check("dip-then-recover call succeeds", transientOk);

    console.log("\n[3] Innocence rule: pre-existing dip");
    const sKey = generatePrivateKey();
    const spenderEoa = await delegate(sKey, spenderImpl.address);
    await fund(spenderEoa, parseEther("10.5"));
    const innocence = (await publicClient.readContract({
      address: orchestrator.address,
      abi: orchestrator.abi,
      functionName: "dipThenGuardedCall",
      args: [spenderEoa, guardedEoa, recipient, parseEther("1")],
    })) as boolean;
    c.check("guarded call proceeds despite pre-existing dip", innocence);

    console.log("\n[4] Exact-reserve boundary");
    const boundaryOk = await publicClient
      .simulateContract({
        address: guardedEoa,
        abi: harnessImpl.abi,
        functionName: "doGuarded",
        args: [recipient, parseEther("0.5"), "0x"], // 10.5 - 0.5 = exactly 10
        account: funder,
      })
      .then(() => true)
      .catch(() => false);
    c.check("ending exactly at reserve is not a violation", boundaryOk);

    // --- EntryPoint 3-op bundle ---
    console.log("\n[5] EntryPoint v0.8 bundle: op2 dips, bundle survives");
    const keys = [generatePrivateKey(), generatePrivateKey(), generatePrivateKey()];
    const accounts = keys.map((k) => privateKeyToAccount(k));
    const [alice, bob, carol] = accounts;
    for (const a of accounts) await delegate(keys[accounts.indexOf(a)], mip4Account.address);
    for (const a of accounts) await fund(a.address, parseEther("10.6"));
    for (const a of accounts) {
      const hash = await walletClient.writeContract({
        address: entryPoint.address,
        abi: entryPoint.abi,
        functionName: "depositTo",
        args: [a.address],
        value: parseEther("0.5"),
      });
      await publicClient.waitForTransactionReceipt({ hash });
    }

    const sink: Address = "0x2222222222222222222222222222222222222222";
    const amounts = [parseEther("0.05"), parseEther("1"), parseEther("0.05")]; // op2 dips: 10.6 - 1 = 9.6 < 10

    const ops: PackedUserOperation[] = [];
    for (let i = 0; i < 3; i++) {
      const nonce = (await publicClient.readContract({
        address: entryPoint.address,
        abi: entryPoint.abi,
        functionName: "getNonce",
        args: [accounts[i].address, 0n],
      })) as bigint;
      const op = buildUserOp({
        sender: accounts[i].address,
        nonce,
        callData: executeCalldata(mip4Account.abi, sink, amounts[i], "0x"),
      });
      const userOpHash = (await publicClient.readContract({
        address: entryPoint.address,
        abi: entryPoint.abi,
        functionName: "getUserOpHash",
        args: [op],
      })) as Hex;
      op.signature = await accounts[i].sign({ hash: userOpHash });
      ops.push(op);
    }

    const bobBefore = await publicClient.getBalance({ address: bob.address });
    const bobDepositBefore = (await publicClient.readContract({
      address: entryPoint.address,
      abi: entryPoint.abi,
      functionName: "balanceOf",
      args: [bob.address],
    })) as bigint;

    const bundleHash = await walletClient.writeContract({
      address: entryPoint.address,
      abi: entryPoint.abi,
      functionName: "handleOps",
      args: [ops, funder.address],
      gas: 3_000_000n,
    });
    const bundleReceipt = await publicClient.waitForTransactionReceipt({ hash: bundleHash });
    c.check("bundle transaction committed", bundleReceipt.status === "success");

    const opEvents: { sender: Address; success: boolean }[] = [];
    let bobRevertReason: Hex | undefined;
    for (const log of bundleReceipt.logs) {
      try {
        const ev = decodeEventLog({ abi: entryPoint.abi, data: log.data, topics: log.topics }) as {
          eventName: string;
          args: any;
        };
        if (ev.eventName === "UserOperationEvent") {
          const args = ev.args as any;
          opEvents.push({ sender: args.sender, success: args.success });
        }
        if (ev.eventName === "UserOperationRevertReason") {
          bobRevertReason = (ev.args as any).revertReason;
        }
      } catch {}
    }
    c.check("3 UserOperationEvents emitted", opEvents.length === 3, `got ${opEvents.length}`);
    c.check("op1 (Alice) succeeded", opEvents[0]?.success === true);
    c.check("op2 (Bob) failed", opEvents[1]?.success === false);
    c.check("op3 (Carol) succeeded", opEvents[2]?.success === true);
    c.check(
      "op2 revert reason is ReserveDipped()",
      bobRevertReason?.toLowerCase() === reserveDippedSelector.toLowerCase(),
      `got ${bobRevertReason}`,
    );

    const bobAfter = await publicClient.getBalance({ address: bob.address });
    const bobDepositAfter = (await publicClient.readContract({
      address: entryPoint.address,
      abi: entryPoint.abi,
      functionName: "balanceOf",
      args: [bob.address],
    })) as bigint;
    const sinkBal = await publicClient.getBalance({ address: sink });
    c.check("Bob's balance unchanged (execution unwound)", bobAfter === bobBefore, fmt(bobAfter));
    c.check("Bob still >= 10 MON reserve", bobAfter >= parseEther("10"));
    c.check("Bob's deposit was charged for the failed op", bobDepositAfter < bobDepositBefore);
    c.check("sink received only Alice+Carol transfers", sinkBal === parseEther("0.1"), fmt(sinkBal));

    // --- negative control: unguarded stock account stays dipped ---
    console.log("\n[6] Negative control: stock Simple7702Account (no guard)");
    const nKey = generatePrivateKey();
    const naked = privateKeyToAccount(nKey);
    await delegate(nKey, stockAccount.address);
    await fund(naked.address, parseEther("10.6"));
    {
      const hash = await walletClient.writeContract({
        address: entryPoint.address,
        abi: entryPoint.abi,
        functionName: "depositTo",
        args: [naked.address],
        value: parseEther("0.5"),
      });
      await publicClient.waitForTransactionReceipt({ hash });
    }
    const nakedNonce = (await publicClient.readContract({
      address: entryPoint.address,
      abi: entryPoint.abi,
      functionName: "getNonce",
      args: [naked.address, 0n],
    })) as bigint;
    const nakedOp = buildUserOp({
      sender: naked.address,
      nonce: nakedNonce,
      callData: executeCalldata(stockAccount.abi, sink, parseEther("1"), "0x"),
    });
    const nakedHash = (await publicClient.readContract({
      address: entryPoint.address,
      abi: entryPoint.abi,
      functionName: "getUserOpHash",
      args: [nakedOp],
    })) as Hex;
    nakedOp.signature = await naked.sign({ hash: nakedHash });
    const nakedBundle = await walletClient.writeContract({
      address: entryPoint.address,
      abi: entryPoint.abi,
      functionName: "handleOps",
      args: [[nakedOp], funder.address],
      gas: 1_500_000n,
    });
    await publicClient.waitForTransactionReceipt({ hash: nakedBundle });
    const nakedAfter = await publicClient.getBalance({ address: naked.address });
    c.check(
      "unguarded op left account below reserve (on real Monad the WHOLE tx would revert)",
      nakedAfter < parseEther("10"),
      fmt(nakedAfter),
    );

    const ok = c.summary("anvil --monad integration");
    process.exitCode = ok ? 0 : 1;
  } finally {
    stop();
  }
}

main().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
