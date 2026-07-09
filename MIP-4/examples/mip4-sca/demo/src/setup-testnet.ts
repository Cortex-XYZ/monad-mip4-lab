/**
 * Testnet demo setup (idempotent — SPEC §5.5).
 *   1. generate (or reuse) Alice/Bob/Carol keys -> demo/.accounts.json
 *   2. fund each with 10.6 MON from FUNDER_KEY
 *   3. 7702-delegate each to the Mip4Account implementation
 *   4. EntryPoint.depositTo(0.5 MON) for each  [validation-phase invariant, SPEC §5.3]
 *
 * Prereqs: .env with FUNDER_KEY (~40 MON) and MIP4_ACCOUNT_IMPL (from
 * `forge script script/DeployMip4Account.s.sol --rpc-url ... --broadcast`).
 */
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { parseEther, type Hex } from "viem";
import { generatePrivateKey, privateKeyToAccount } from "viem/accounts";
import { ACCOUNTS_FILE, clients, env, requireEnv } from "./config.js";
import { ENTRY_POINT_V08, artifact, fmt } from "./lib.js";

const TARGET_BALANCE = parseEther("10.6");
const TARGET_DEPOSIT = parseEther("0.5");

async function main() {
  const impl = requireEnv(env.mip4AccountImpl, "MIP4_ACCOUNT_IMPL");
  const { publicClient, walletClient } = clients();
  const entryPointAbi = artifact("EntryPoint.sol", "EntryPoint").abi;

  const implCode = await publicClient.getCode({ address: impl });
  if (!implCode || implCode === "0x") {
    console.error(`No code at MIP4_ACCOUNT_IMPL ${impl} — deploy it first.`);
    process.exit(1);
  }

  const keys: Hex[] = existsSync(ACCOUNTS_FILE)
    ? JSON.parse(readFileSync(ACCOUNTS_FILE, "utf8"))
    : [generatePrivateKey(), generatePrivateKey(), generatePrivateKey()];
  writeFileSync(ACCOUNTS_FILE, JSON.stringify(keys, null, 2));

  /**
   * Send value and VERIFY the receipt. A funder holding < 10 MON is itself
   * reserve-bound: each value transfer needs Monad's emptying exception,
   * which requires no funder txs in the previous k=3 blocks. A reverted
   * transfer is therefore normal — wait out the window and retry.
   */
  async function sendValueChecked(to: `0x${string}`, value: bigint, label: string) {
    for (let attempt = 1; attempt <= 4; attempt++) {
      const hash = await walletClient.sendTransaction({ to, value });
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      if (receipt.status === "success") return;
      console.log(`  ${label}: transfer reverted (funder reserve rule) — waiting out the k-block window, retry ${attempt}/4`);
      await new Promise((r) => setTimeout(r, 6000));
    }
    throw new Error(`${label}: transfer kept reverting — top up the funder above 10 MON or retry later`);
  }

  const names = ["Alice", "Bob", "Carol"];
  for (let i = 0; i < 3; i++) {
    const account = privateKeyToAccount(keys[i]);
    console.log(`\n${names[i]}: ${account.address}`);

    // 1. fund
    const balance = await publicClient.getBalance({ address: account.address });
    if (balance < TARGET_BALANCE) {
      await sendValueChecked(account.address, TARGET_BALANCE - balance, names[i]);
    }
    console.log(`  balance: ${fmt(await publicClient.getBalance({ address: account.address }))}`);

    // 2. delegate (7702 type-4 tx, funder pays)
    const code = await publicClient.getCode({ address: account.address });
    const expected = ("0xef0100" + impl.slice(2)).toLowerCase();
    if (code?.toLowerCase() !== expected) {
      const authorization = await walletClient.signAuthorization({ account, contractAddress: impl });
      const hash = await walletClient.sendTransaction({
        to: account.address,
        value: 0n,
        authorizationList: [authorization],
      });
      await publicClient.waitForTransactionReceipt({ hash });
    }
    console.log(`  delegated -> ${impl}`);

    // 3. EntryPoint deposit (so validation never touches the EOA balance)
    const deposit = (await publicClient.readContract({
      address: ENTRY_POINT_V08,
      abi: entryPointAbi,
      functionName: "balanceOf",
      args: [account.address],
    })) as bigint;
    if (deposit < TARGET_DEPOSIT) {
      for (let attempt = 1; attempt <= 4; attempt++) {
        const hash = await walletClient.writeContract({
          address: ENTRY_POINT_V08,
          abi: entryPointAbi,
          functionName: "depositTo",
          args: [account.address],
          value: TARGET_DEPOSIT - deposit,
        });
        const receipt = await publicClient.waitForTransactionReceipt({ hash });
        if (receipt.status === "success") break;
        if (attempt === 4) throw new Error(`${names[i]}: depositTo kept reverting`);
        console.log(`  depositTo reverted (funder reserve rule) — retry ${attempt}/4`);
        await new Promise((r) => setTimeout(r, 6000));
      }
    }
    const finalDeposit = (await publicClient.readContract({
      address: ENTRY_POINT_V08,
      abi: entryPointAbi,
      functionName: "balanceOf",
      args: [account.address],
    })) as bigint;
    console.log(`  entryPoint deposit: ${fmt(finalDeposit)}`);
  }

  console.log("\nSetup complete. Next: npm run demo:direct");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
