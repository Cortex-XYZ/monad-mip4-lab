# Understanding MIP-4: Reserve Balance Introspection

## Abstract

MIP-4 is a protocol upgrade for Monad. It introduces a lightweight **precompile** at `0x1001` with a method, `dippedIntoReserve()`, that lets a contract check **during execution** whether the transaction is currently in a **reserve-balance violation** state.

Without this tool, contracts run blind: Monad’s reserve-balance rule is enforced only at the *end* of execution, so a violating transaction can revert after all of its internal logic has already run, with no chance for the contract to react. With MIP-4, a contract can query the violation state mid-execution and adjust - by restoring balances, taking an alternative code path, or reverting early with a meaningful error.

## Quick Reference

| Property                                   | Value                                                                                             | Source     |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------- | ---------- |
| Precompile address                         | `0x1001` (follows the staking precompile at `0x1000`)                                             | MIP-4 spec |
| Method                                     | `dippedIntoReserve()`                                                                             | MIP-4 spec |
| Selector                                   | `0x3a61584e`                                                                                      | MIP-4 spec |
| Returns                                    | ABI-encoded `bool` (32-byte word)                                                                 | MIP-4 spec |
| Gas cost                                   | **100** (`GAS_DIPPED_INTO_RESERVE`, equal to one `tload`)                                         | MIP-4 spec |
| Complexity                                 | O(1) via incremental violation tracking                                                           | MIP-4 spec |
| Invocation                                 | `CALL` only; `STATICCALL` / `DELEGATECALL` / `CALLCODE` revert                                    | MIP-4 spec |
| Status                                     | Final                                                                                             | MIP-4 spec |
| Reserve threshold (`user_reserve_balance`) | **10 MON**, uniform for every EOA today (per-account customization is a possible future addition) | Monad docs |
| Execution delay (`k` / `D`)                | 3 blocks (≈ 1.2 s at 400 ms blocks)                                                               | Monad docs |

---

## 1. The Context: How the Standard EVM Works

To understand why Monad needs this, start with how standard Ethereum works.

The Ethereum Virtual Machine (EVM) is essentially a single-threaded state machine. When a transaction is submitted, the network processes it synchronously:

1. It checks whether the sender can afford the transaction’s upfront gas requirements.
2. It executes the transaction step by step.
3. It updates the global state.
4. It moves on to the next transaction.

**Analogy.** Picture a traditional grocery checkout. The cashier scans item 1 and deducts money from your wallet, scans item 2 and deducts money, and so on. If your wallet hits $0 at item 3, the cashier stops immediately - you know exactly when and why the transaction failed.

In the standard EVM execution model, contract code runs against the transaction’s current in-flight state. If an earlier step in the same execution changes a balance, later steps can reason about that updated state immediately.

---

## 2. Monad’s Architecture: Speed via Asynchronous Execution

Monad is an EVM-compatible Layer 1. It gets there not by sharding or by abandoning the EVM, but by changing *when* execution happens relative to consensus.

### Why interleaved execution is the bottleneck

In Ethereum, execution is a prerequisite to consensus. When validators agree on a block, they are agreeing on two things at once: the ordered list of transactions, *and* the Merkle root of the resulting state. To produce that Merkle root, the leader must fully execute the block before proposing it, and every validator must re-execute it before voting. Execution effectively happens *twice* and must still leave room for several rounds of global communication.

The practical effect is that execution gets only a small slice of the total block-time budget. Because execution sits on the critical path and blocks must complete on every node even in the worst case, the per-block gas limit has to be set conservatively. Monad refers to this design as having execution **interleaved** with consensus.

### The fix: order first, execute later

Monad decouples the two. Nodes reach consensus on the *ordering* of transactions without first executing them. The leader proposes an order without yet knowing the resulting state root, and validators can reach consensus on that ordering before the block’s transactions have fully executed. Only after a block is finalized does each node execute it locally to produce the agreed-upon state.

The key observation is subtle but important: **once the ordering is fixed, the resulting state is already determined** - execution merely *reveals* it. A finalized sequence of transactions will always produce the same end state, even though that state is not known the instant consensus is reached. As on Ethereum, a transaction that “fails” during execution (for example, because a transfer exceeds the sender’s balance) is still a valid part of the block; its failure is simply part of the deterministic outcome.

Separating execution from consensus lets execution use the full block-time budget rather than only the portion left over after consensus work. That expanded budget, combined with optimistic parallel execution across CPU cores and the MonadDB state store, is what unlocks the throughput gains.

### The cost of decoupling: consensus is partly blind

Decoupling creates a new problem. If consensus runs ahead of execution, validators do not have the current state when they admit transactions into a block - they only have a *lagged* view. In Monad this lag is a system parameter, `k` (also written `D`), currently set to **3 blocks**. When validating block `n`, consensus assumes only the state as of the end of block `n − 3`. Since blocks are ~400 ms apart, that is roughly a **1.2-second** window in which transactions can be committed to blockspace before their effects are known.

Two mechanisms keep this safe:

### Delayed Merkle root

Block proposals cannot carry the state root of the block they propose, because that block has not been executed yet. Instead, each proposal includes the Merkle root from `k` blocks earlier. This lets nodes detect divergence after the fact: a node whose local execution of block `n − k` disagrees with the agreed root falls out of consensus, rolls back, and re-executes. It is a safety net confirming that everyone computed the same state.

This is also why teams with serious off-chain financial logic - exchanges, bridges, stablecoin issuers, and similar systems - are often advised to wait for a block to reach the **Verified** state, when its delayed Merkle root has been confirmed, rather than acting on **Finalized** alone.

### The Reserve Balance rule

This is the part MIP-4 is built around.

### The DoS problem Reserve Balance solves

Picture an attacker, Xavier, with a funded account. At block 998 he submits transactions that move his *entire* balance out to other accounts. At block 1000 - before block 998 has executed under the lagged view - he submits an expensive transaction. The network has already locked block 1000 in and consumed blockspace for it. But when execution catches up, Xavier’s account is empty, so the protocol cannot charge him for the gas his expensive transaction used.

Repeat this cheaply and you have a denial-of-service vector: validators burn compute that nobody pays for.

To close this, the protocol requires every externally owned account (EOA) to keep enough MON set aside to cover the gas of its in-flight transactions - those included less than `k` blocks ago. The threshold is a system parameter, `user_reserve_balance`, **currently set to 10 MON for every EOA**. It is uniform today; Monad’s docs note that a future version *could* let users customize it through a stateful precompile, but that is not live.

The guarantee this provides is what matters: an account always has enough set aside to pay for its in-flight transactions, so consensus can safely admit them despite its lagged view.

The mechanism distinguishes two kinds of spending:

* **Gas spend** (`gas_price × gas_limit`) is what *consensus* budgets against the reserve. For each account, consensus allows in-flight transactions only while their cumulative gas spend stays under the reserve (or the account’s lagged-state balance, whichever is lower).
* **Value spend** (the MON actually transferred out) is what the *execution-time* reserve check guards.

“Dips below” has an exact meaning in Monad’s reserve-balance rules: a violation occurs when an account’s balance is **decremented** and ends **below** its reserve threshold. A transaction whose balance ends at or above the threshold is fine. So is one that leaves the balance unchanged or higher, even if the account was already below reserve beforehand. Only a transaction that both decreases the balance and ends below the threshold is reverted. Intermediate dips during execution are allowed as long as the *ending* balance is sufficient.

### It’s lighter than it sounds: the “emptying transaction” exception

Crucially, the rule is designed *not* to interfere with normal use. Without an exception, an EOA could never spend below 10 MON, and an account holding less than that could never transact at all.

Monad’s reserve-balance mechanism therefore carves out an **emptying transaction** exception, defined precisely as a transaction where:

* the sender is undelegated;
* the sender has sent no other transaction in the prior `k` blocks; and
* no delegation or undelegation request for the sender occurred in the prior `k` blocks, including in the current transaction.

An emptying transaction is allowed to proceed even if it takes the account below the reserve. In effect, it lets a consistently undelegated account dip below reserve once every `k` blocks (≈ once per 1.2 seconds). This works because consensus can *statically* determine the lowest an undelegated account’s balance can reach: an undelegated account is only debited by the value and gas in its own transaction data.

Since most ordinary transactions are the first one an account sends within any 3-block window, most users - even those with very low balances - never feel the constraint. Monad’s worked examples confirm the boundaries; for example, an account with 100 MON and a 1-MON reserve can send a 3-MON-plus-2-fee emptying transaction, but a *second* such transaction in the same block is excluded by consensus.

### Why EIP-7702 makes this more important

The complication is **EIP-7702 account delegation**, which lets an EOA temporarily run smart-contract code. Reserve balance becomes especially important here because a delegated account can have MON moved out by a transaction *someone else* submits, in a way consensus cannot fully inspect statically.

Per Monad’s reserve-balance docs, a delegated EOA **cannot use the emptying exception**, and the transactions that revert for it are the ones that decrement its balance and leave it below reserve. In practice, this means sponsored-gas workflows - where a delegated EOA starts empty and only receives MON involuntarily - can work fine. The blocked case is when such an account already holds some MON below reserve and the sponsored call tries to move more MON out of it.

This delegated population is exactly where silent reserve reverts become a recurring hazard, and exactly why mid-execution detection (MIP-4) is useful rather than academic.

### A consequence worth flagging: included-but-reverted transactions

Because consensus admits transactions it cannot fully evaluate, you can see transactions *included on-chain whose execution later reverts* - for example, an attempt to transfer out more MON than the account holds. These are still valid, gas-paying transactions; their only durable effect may be the gas decrement.

Ethereum also includes reverting transactions, so this is not a protocol difference in principle. But Monad’s asynchronous architecture makes it especially important to understand that “included in a finalized block” and “succeeded in execution” are not the same thing.

### Is the reserve configurable? Not yet.

Today the reserve is a uniform constant: 10 MON for every EOA. Monad’s documentation states that a future version *could* let users customize their reserve through a stateful precompile, but this is described as a possibility, not a shipped feature.

A precompile of this kind - referred to as `0xRESERVES`, with an `update(uint256)` method callable only by an EOA and reverting on internal calls - appears in Category Labs’ formal Coq *model* of the mechanism. That is a specification artifact, not confirmation of a deployed Monad contract. Treat per-account reserves as a forward-looking design point.

Importantly, this hypothetical reserve-*setting* precompile is different from the MIP-4 introspection precompile at `0x1001`, which only *reads* whether a reserve violation currently exists and changes no state.

> **A note on figures and confidence.** The `k = 3` delay, the 400 ms / 800 ms block and finality timings, and `user_reserve_balance = 10 MON` are taken from current Monad documentation and are protocol parameters that can be re-tuned. The MIP-4 precompile details - address `0x1001`, selector `0x3a61584e`, 100 gas, calldata semantics, and `CALL`-only invocation - come from the Final MIP-4 specification. Any dollar amounts or trade sizes used in examples below are illustrative, not measured.

---

## 3. The Problem: The “Blind” Smart Contract

The Reserve Balance rule creates a real headache for developers.

Because the protocol checks the reserve rule only at the *very end* of the transaction, the contract executing the logic is blind to it while its own code is running. The contract has no way to ask, mid-execution, whether it has already pushed some touched account into a reserve-balance violation.

**Example - an arbitrage bot.** Suppose a bot operates from an EIP-7702-delegated account (so the emptying exception does not apply to it) that holds a little over 10 MON.

1. It executes a multi-hop strategy that, as part of the routing, moves MON out of the account, leaving the ending balance at, say, 9.9 MON.
2. The trade itself nets a profit elsewhere, so from the bot’s internal logic everything succeeded.

But because the account’s balance was **decremented** and ends **below** the 10 MON reserve threshold, the reserve-balance check reverts the whole transaction. The bot’s apparent success is undone, and the gas spent on the computation is lost.

The point is structural: the offending condition - a touched account left in reserve violation - is invisible to the contract until the protocol acts at the end of execution.

---

## 4. The Solution: MIP-4

MIP-4 gives contracts a way to inspect reserve-balance violations **during execution**, rather than discovering only at the very end of the transaction that the protocol is about to revert.

At a high level, it adds a precompile at `0x1001` with a single method, `dippedIntoReserve()`. The purpose of that method is not to answer a generic question like “is this account below 10 MON?” Rather, it exposes a very specific protocol predicate:

> **If the transaction ended at this exact point in execution, would Monad’s reserve-balance check consider the transaction to be in violation?**

That is the core of MIP-4. It takes a check that previously existed only as an **end-of-execution protocol rule** and makes it queryable **mid-execution**.

### 4.1 From post-execution rule to mid-execution introspection

To see why this matters, it helps to be precise about what problem MIP-4 is solving.

Reserve balance on Monad is not enforced by smart contracts themselves. It is a protocol rule evaluated by the execution engine. If, after execution, the transaction has left some relevant account in a reserve-violating state, the transaction reverts. Before MIP-4, contracts had no built-in way to ask whether they had already crossed into that state while they were still running.

So the gap looked like this:

* **The protocol** knew, at the end of execution, whether reserve balance had been violated.
* **The contract** did not know, during execution, whether its current intermediate state would eventually fail that same check.

MIP-4 closes that gap. It does **not** change the reserve-balance rule. It does **not** create an exception or make violating transactions succeed. It simply lets contract code inspect the reserve-violation state before execution finishes, while there is still time to react.

That distinction is important. MIP-4 is an **introspection** feature, not a reserve-policy change.

### 4.2 What `dippedIntoReserve()` is actually checking

The easiest way to misunderstand `dippedIntoReserve()` is to think of it as a simple balance threshold check. It is more specific than that.

It is **not** asking:

* “Is the caller below 10 MON?”
* “Is `msg.sender` below reserve?”
* “Did the most recent transfer move too much MON?”

Instead, it is asking whether the **transaction’s current execution state** would fail Monad’s reserve-balance rule **if execution stopped right now**.

That is a transaction-level question, not an account-local one.

In the reserve-balance specification, the end-of-execution rule is expressed as a function usually referred to as **`DippedIntoReserve`**. Conceptually, it takes the set of accounts whose balances changed during the transaction and checks whether any of them violate the reserve constraint under the transaction’s current state. MIP-4 exposes that same kind of question *mid-execution*: rather than waiting for the transaction to finish and then evaluating reserve balance once, a contract can ask for the answer at an arbitrary point during execution.

The right mental model is therefore:

* Monad already has a protocol-level predicate that decides whether a transaction has “dipped into reserve.”
* MIP-4 makes that predicate observable before the transaction ends.

### 4.3 The check is transaction-wide, not account-local

Another important point is scope. `dippedIntoReserve()` is **global to the transaction**, not local to the contract that calls it.

The precompile does not inspect only the balance of the current contract or the current `msg.sender`. It evaluates the reserve-violation state of the **transaction as a whole**, using the accounts touched so far in the current execution state. In other words, the question is not “is *my* balance okay?” but “has *this transaction* currently put any relevant touched account into reserve violation?”

This matters because reserve balance is not necessarily violated by the contract that notices the problem. A transaction might flow through several contracts, and a delegated EOA might be debited somewhere deeper in the call tree. If that debit leaves the EOA in reserve violation, the top-level transaction is what ultimately reverts. MIP-4 lets any contract currently executing inside that transaction ask whether the transaction has entered that state.

The trade-off is that the answer is intentionally coarse-grained. The precompile returns a single `bool`. It tells you **that a reserve violation currently exists**, but not:

* which account is violating reserve;
* how far below reserve it is;
* or which sub-call caused it.

That design keeps the interface minimal, but it also means contracts need to structure their checks carefully if they want to attribute a violation to a specific operation. This is one reason bundlers are expected to call `dippedIntoReserve()` **after each UserOperation**, rather than only once at the very end of the bundle.

### 4.4 What counts as a reserve violation

This is the part where the mechanics matter most.

Reserve balance on Monad is not simply “every touched account must always stay above 10 MON.” The actual rule is more nuanced. For each relevant balance-changing account, the reserve-balance logic compares the account’s **current balance** against a threshold derived from its reserve requirement, its original balance, and whether it is the transaction sender.

At a high level, the check works account by account over the set of balances changed by the transaction:

1. Take an account whose balance has changed.
2. Determine the reserve threshold that applies to that account under the reserve-balance rules.
3. Compare the account’s **current** balance in the in-flight execution state against that threshold.
4. If any relevant account fails, the transaction is considered to have dipped into reserve.

Two details are worth calling out.

#### Non-sender accounts

For a non-sender account, the relevant threshold is tied to that account’s reserve requirement, capped by its original balance before execution. Intuitively, the protocol is checking whether the transaction has taken that account below the level it is supposed to preserve.

#### The sender

For the sender, the threshold is adjusted to account for the transaction’s gas fees. That is because the sender’s gas spend is already part of the transaction’s intended execution accounting, so the reserve-balance logic does not treat sender-side gas spending the same way it treats arbitrary MON outflows.

The important takeaway for the article is that **`dippedIntoReserve()` is not just checking “balance < 10 MON.”** It is checking whether the current state violates Monad’s **actual reserve-balance predicate**, which is defined in terms of reserve thresholds, original balances, sender-specific handling, and the emptying-transaction rules.

That is why the precompile is useful: it exposes the **same condition the protocol itself cares about**, not a simplified approximation.

### 4.5 Why this can change during a transaction

A transaction does not have to be permanently “safe” or “unsafe” from start to finish. The reserve-violation state can change as execution proceeds.

For example, imagine a transaction that temporarily routes MON out of a delegated EOA as part of a more complex strategy:

1. At the start of the transaction, the account is above reserve.
2. Midway through execution, some operation moves MON out of the account, pushing it below its relevant reserve threshold.
3. Later in the same transaction, another operation routes MON back in and restores the balance above the threshold.

At step 2, the transaction is in reserve violation. At step 3, it is no longer in reserve violation.

That dynamic behavior is exactly why MIP-4 is useful. A contract can check the reserve state **after** a risky step, notice that it has temporarily created a violation, and then take corrective action before execution finishes. If the corrective action succeeds, a later call to `dippedIntoReserve()` can return `false` again.

So `dippedIntoReserve()` is best thought of as a **snapshot of the current reserve-violation state**, not a permanent verdict on the transaction. A `false` result means “the transaction is not in reserve violation **right now**,” not “the rest of the transaction is guaranteed to succeed.”

### 4.6 Why a naïve implementation would be O(n)

At this point, a natural question is: if the precompile is checking the reserve state of the whole transaction, why is it cheap? Why doesn’t every call have to scan every touched account?

A straightforward implementation would indeed be expensive.

Imagine maintaining a list of all accounts whose balances have changed during the transaction. If `dippedIntoReserve()` were implemented naively, then every time a contract called it, the execution engine would have to:

1. iterate through the full list of touched accounts;
2. recompute the reserve threshold for each one;
3. compare each account’s current balance against that threshold;
4. return `true` if any of them violates the rule.

If the transaction had touched `n` accounts, that would make a single call to `dippedIntoReserve()` cost **O(n)**.

That is undesirable for two reasons.

First, the cost of the check would grow with transaction complexity. A large bundle or a complex DeFi route may touch many accounts; a reserve check that gets more expensive the more work the transaction has already done is exactly the wrong shape for a function that may need to be called repeatedly.

Second, the most valuable uses of MIP-4 are precisely the ones that want to call it **many times**. An ERC-4337 bundler may want to call `dippedIntoReserve()` after each UserOperation. A smart account may want to call it after each risky balance-affecting phase of a multi-step strategy. If each call had to rescan the entire touched-account set, the cost would quickly become prohibitive.

### 4.7 The O(1) design: incremental violation tracking

The reason MIP-4 can be priced cheaply is that the precompile is **not** intended to recompute the reserve-balance predicate from scratch on every call. Instead, the execution engine tracks reserve-violation state **incrementally as balances change**.

The key idea is simple:

* whenever execution changes an account’s balance, the client updates that account’s reserve-violation status;
* if the account newly enters reserve violation, the transaction-level violation state is updated accordingly;
* if the account later recovers above its threshold, that state is updated again;
* by the time a contract calls `dippedIntoReserve()`, the answer has already been maintained by the execution engine as part of ordinary transaction processing.

So instead of “scan every touched account and recompute everything,” the implementation can behave more like:

* **on each balance update:** maintain the current reserve-violation state;
* **on `dippedIntoReserve()` call:** simply read whether the current transaction-level violation state is empty or non-empty.

That is what makes the precompile **O(1)** from the caller’s perspective. The expensive part - tracking whether balance changes have pushed any account into reserve violation - is distributed incrementally across the transaction as those balance changes happen. The precompile call itself is then just a lookup of already-maintained state.

This is also the right way to interpret the MIP’s 100-gas pricing. The precompile is cheap not because reserve balance is conceptually trivial, but because by the time the call happens, the heavy lifting has already been done incrementally during execution.

### 4.8 A useful way to picture the internal state

One way to think about the implementation is as a transaction-scoped set of “currently failing” accounts.

Conceptually:

* when an account’s balance changes, the engine checks whether that account is now violating reserve balance under the current execution state;
* if it is, the account is marked as failing;
* if it later recovers, it is removed from that failing set;
* `dippedIntoReserve()` returns `true` if and only if that set is currently non-empty.

Whether a specific client stores that state as a literal set, a counter, or some equivalent cached structure is an implementation detail. The important point is the computational pattern: **the violation state is maintained incrementally as the transaction executes, rather than recomputed from scratch every time it is queried.**

That is the difference between an O(n) scan and an O(1) read.

### 4.9 Why this matters for bundlers and delegated EOAs

This design is not just an optimization; it is what makes the feature practical for the use cases that motivated it.

#### ERC-4337 bundlers

A bundler processing many UserOperations in one transaction needs to know when a particular operation has pushed the bundle into reserve violation. If it can call `dippedIntoReserve()` after each UserOperation at constant cost, it can localize the problem to the operation that just ran and isolate or discard that operation rather than letting the entire bundle revert.

That only works if the check is cheap enough to call repeatedly. An O(n) scan after every UserOperation would make the gas cost of later operations depend on how much earlier work had already happened in the bundle. The O(1) design avoids that.

#### EIP-7702 delegated EOAs

Delegated EOAs are the accounts most exposed to reserve-balance surprises, because they can have MON moved out of them by contract logic in ways that consensus cannot fully predict from the top-level transaction alone. Those are exactly the accounts that benefit from being able to ask, mid-execution, whether the current flow has pushed them - or some other touched account in the transaction - into reserve violation.

In both cases, MIP-4’s value is not merely that it reveals reserve-balance state, but that it reveals it **cheaply enough to be checked at meaningful boundaries throughout a transaction**.

### 4.10 The core idea to emphasize

If there is one point Section 4 should leave the reader with, it is this:

* **Before MIP-4**, reserve balance was a hidden end-of-execution tripwire. Contracts could only discover it by failing.
* **After MIP-4**, the same reserve-balance rule is still there, but contracts can now ask - at any point during execution - whether the transaction has already crossed into that failure state.

And the reason that question is practical to ask is that Monad does not recompute it from scratch on every call. It keeps the reserve-violation state updated incrementally as balances change, so `dippedIntoReserve()` itself can be a cheap O(1) lookup rather than an O(n) scan over every account the transaction has touched.

That is the real contribution of MIP-4: not a new reserve rule, but a new way for contracts to *observe* the existing one while they still have time to do something about it.


---

## 5. Real-World Examples

### Example A - Remediating a reserve violation mid-transaction

A user with an EIP-7702-delegated account interacts with a DeFi contract in a way that moves MON out of their account, leaving the ending balance at ~8 MON - below the 10 MON reserve.

* **Without MIP-4:** Execution completes, the reserve check sees the account decremented below 10 MON, and the whole transaction reverts.
* **With MIP-4:** Before finishing, the contract calls `dippedIntoReserve()`, gets `true`, and remediates - for instance, it routes additional MON back into the account so the *ending* balance is at or above 10 MON. Because the reserve check cares about the ending state, the transaction can then pass.

The contract still has to size the top-up carefully, because its own remediation logic consumes gas and may itself affect balances.

### Example B - The ERC-4337 bundler

A **bundler** packs many user operations from unrelated users into one transaction. This is the headline use case the MIP authors explicitly call out: the precompile is intended for **bundler entrypoint contracts**, and the O(1) design was chosen specifically so that one UserOp’s gas cost does not depend on how many ran before it.

Suppose a bundle contains 50 user operations:

* Operations 1–49 execute cleanly.
* Operation 50 moves MON out of a delegated account and leaves it below 10 MON.

Outcomes:

* **Without MIP-4:** The reserve violation from operation 50 reverts the whole transaction. The other 49 fail alongside it, and the bundler has paid gas for work that produced nothing.
* **With MIP-4:** The entrypoint calls `dippedIntoReserve()` after processing each operation. When it detects the violation at operation 50, it can revert just that operation’s effects - for example, by isolating it in a nested call frame and catching the failure - while preserving the rest of the bundle.

One caveat matters here: the precompile reports whether *any* touched account is currently in violation across the whole transaction. It does **not** tell you *which* account caused the problem. A bundler design therefore needs to structure its checks so it can attribute a detected violation to the operation that caused it - for example, by checking immediately after each operation or by isolating each operation in a sub-call.

---

## Summary

MIP-4 turns a silent, end-of-execution reserve-balance revert into a condition contracts can observe and respond to *during* execution.

For 100 gas - the cost of one transient-storage load - a contract can call the precompile at `0x1001`, learn whether the transaction is **currently** in a reserve-balance violation state, and then decide whether to restore balances, branch to a safer path, or revert early with a clearer error.

The main beneficiaries are delegated EOAs and ERC-4337 bundlers:

* **Delegated EOAs**, because they cannot rely on the emptying-transaction exception and are therefore more exposed to reserve-triggered reverts.
* **Bundlers**, because a single violating UserOp can otherwise sink an entire batch.

The precompile does not change the reserve-balance rule itself. It simply exposes reserve-violation state to contracts while execution is still in progress, giving them a chance to react before the transaction reaches Monad’s final reserve check.

---

## Sources

* **MIP-4 specification (status: Final)** - `monad-crypto/MIPs`, `MIPS/MIP-4.md`. Source for the precompile address, selector (`0x3a61584e`), 100-gas cost, calldata semantics, `CALL`-only requirement, and intended bundler use case.
* **MIP-4 discussion thread** - Monad Research Forum, “MIP-4: Reserve Balance Introspection.” Source for the design history (opcode → precompile) and the rationale behind the O(1) incremental-recomputation approach.
* **Reserve Balance** - Monad Developer Documentation, `developer-essentials/reserve-balance`. Source for `user_reserve_balance = 10 MON`, the gas-spend vs. value-spend distinction, the “dips below” definition, the emptying-transaction exception, EIP-7702 behavior, the worked examples, and the note that per-account customization is only a future possibility.
* **Asynchronous Execution** - Monad Developer Documentation, `monad-arch/consensus/asynchronous-execution`. Source for the interleaved-vs-asynchronous comparison, the delayed Merkle root, `k = D = 3`, and the Verified-state guidance.
* **How Monad Works** - Monad Blog. Source for the DoS example and reserve-balance intuition.
* **Coq model of reserve balance** - Category Labs, `category-research`. Origin of the modeled `0xRESERVES` reserve-setting precompile (a specification artifact, not a confirmed deployed contract).
