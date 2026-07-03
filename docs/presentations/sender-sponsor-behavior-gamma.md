# Sender vs Sponsor Behavior in Monad MIP-4

## Slide 1: The question we asked

Hey guys, do we have an answer to this for sponsor/sender behaviors?

- Can someone else trigger delegated EOA execution that causes the delegated EOA to dip below reserve?
- Does the delegated EOA behave differently when it submits its own transaction?

Speaker note:
This is the whole investigation in two questions. We are not trying to explain all of MIP-4 here. We are isolating one behavior: does the transaction sender change what `dippedIntoReserve()` reports?

---

## Slide 2: Why this question matters

EIP-7702 lets an EOA temporarily behave like a smart account.

That creates two roles:

- the delegated EOA whose code runs
- the transaction sender who pays gas

Sometimes they are the same account.

Sometimes they are different accounts.

Speaker note:
Before EIP-7702, we usually think of an EOA as both the signer and gas payer. With sponsorship, those roles can split. That split is exactly why we tested sender vs sponsor behavior.

---

## Slide 3: The two flows we compared

Sponsor-submitted flow:

```text
sponsor pays gas
delegated EOA executes
delegated EOA sends MON out
```

Authority-submitted flow:

```text
delegated EOA pays gas
delegated EOA executes
delegated EOA sends MON out
```

Speaker note:
The account whose balance matters is the delegated EOA. The question is whether reserve tracking changes when the delegated EOA is also the transaction sender.

---

## Slide 4: What the official docs already tell us

Monad docs say reserve accounting separates spend into:

- gas spend
- value spend

If the delegated EOA is not the sender:

```text
gas spend = 0
value spend = MON sent out by delegated code
```

If the delegated EOA is the sender:

```text
gas spend = paid by the delegated EOA
value spend = transaction value / execution effects
```

Speaker note:
The docs tell us the two flows are not identical. The self-submitted path includes gas spend from the authority. But the docs do not give us the exact `dippedIntoReserve()` trace for both paths.

---

## Slide 5: What we needed to verify

The docs imply the reserve rule should still apply.

But our research question was more concrete:

```text
When the delegated EOA drops below 10 MON during execution,
does dippedIntoReserve() return true in both sender modes?
```

We needed transaction evidence, not only a reading of the docs.

Speaker note:
This is the difference between specification understanding and implementation evidence. The docs tell us what should happen. The experiment tells us what actually happened on Testnet.

---

## Slide 6: Our experiment shape

We kept the important path the same:

- real Monad Testnet
- real EIP-7702 type-4 authorization-list transaction
- same delegated authority
- same delegated implementation
- same refund sink
- same `probeDrainRestore` function
- same reserve check points

We changed one thing:

```text
transaction sender
```

Speaker note:
This is the discipline of the experiment. If we changed too many things, we would not know what caused the result.

---

## Slide 7: What the probe measured

The probe measured reserve state at three points:

```text
before drain
during drain below 10 MON
after refund above 10 MON
```

And recorded:

- `lastBeforeBalance`
- `lastDuringBalance`
- `lastAfterBalance`
- `lastBeforeDip`
- `lastDuringDip`
- `lastAfterDip`

Speaker note:
This gives us both balance movement and the boolean returned by MIP-4. We are not guessing from revert behavior alone.

---

## Slide 8: Sponsor-submitted result

Transaction:

```text
0x83ec8ec23c84b8d5a83f91cea7bad5ed70931bc7b63cfdfab3bae4276dac5a33
```

Sender:

```text
0xF156a49d339918cAae23243C661BCca0537f0de4
```

Observed balances:

```text
before = 20447430148844345000
during = 9999999999999999999
after  = 20447430148844345000
```

Observed dips:

```text
false -> true -> false
```

Speaker note:
This confirms that someone else can submit a transaction that causes delegated EOA execution, and during that execution the delegated EOA can observe `dippedIntoReserve() == true`.

---

## Slide 9: Authority-submitted result

Transaction:

```text
0x45164d211f3318567acac5e580101f58552a2e58a0e760c368e28f5a8fdccaaa
```

Sender:

```text
0x1ef26b741ddd257073f01e81e220fE61262F43b5
```

Observed balances:

```text
start chain balance = 20447430148844345000
before probe        = 20392319724039345000
during              = 9944889575194999999
after               = 20392319724039345000
```

Observed dips:

```text
false -> true -> false
```

Speaker note:
The authority-submitted path also returned true while below reserve. The exact balances differ because the authority paid gas before the probe measured its in-execution balance.

---

## Slide 10: The core answer

Answer 1:

```text
Yes. Someone else can trigger delegated EOA execution that causes the delegated EOA to dip below reserve.
```

Answer 2:

```text
In the tested path, the delegated EOA did not avoid reserve tracking by submitting the transaction itself.
```

Both paths produced:

```text
false -> true -> false
```

Speaker note:
This is the punchline. Sponsor-vs-sender did not change whether the reserve signal fired in our tested path.

---

## Slide 11: The important difference

Sponsor case:

```text
sponsor pays gas
authority balance changes only from delegated code movement
```

Authority case:

```text
authority pays gas
authority balance is already lower before the probe drains MON
```

So the boolean matched:

```text
duringDip = true
```

But the balances were not identical.

Speaker note:
This is the nuance. We should not say the two flows are exactly the same. We should say both flows triggered reserve detection when the delegated EOA dropped below 10 MON.

---

## Slide 12: What we can safely conclude

Verified for this Testnet path:

```text
protocol-created EIP-7702 delegated EOA
real type-4 authorization-list transaction
delegated EOA decrements below 10 MON during execution
= dippedIntoReserve() returns true
```

This held for:

- sponsor-submitted transaction
- authority-submitted transaction

Speaker note:
This is a verified sufficient condition. It is not the complete MIP-4 state machine.

---

## Slide 13: What we should not overclaim

We should not say:

```text
sender and sponsor behavior are always identical
```

We should say:

```text
In our tested path, sender classification did not prevent dippedIntoReserve() from becoming true.
```

Open variants still exist:

- exact-boundary sender variants
- below-reserve starting states
- nested call visibility
- ERC-4337 bundle behavior

Speaker note:
This keeps the research credible. We proved one useful thing. We did not solve the full state machine.

---

## Slide 14: Why this contribution matters

The official docs describe the expected rule.

Our repo adds transaction-level evidence:

- exact transaction hashes
- exact sender roles
- exact balance transitions
- exact `dippedIntoReserve()` values

That makes the behavior easier for other developers to reproduce.

Speaker note:
This is where we can explain our contribution without pretending we invented the concept. The docs specify. We verify and make it reproducible.

---

## Slide 15: What this means for Issue #9

Now we know:

```text
sponsor-vs-sender can both trigger true
```

The next question is different:

```text
How long does that true state last?
```

Issue #9 should test whether `dippedIntoReserve()` is:

- current-state based
- transaction-history based
- account-local
- transaction-global
- affected by nested call depth

Speaker note:
This creates a clean transition to the next research issue. We are moving from “can it become true?” to “what exactly does true mean over time?”

---

## Slide 16: Final punchline

The important distinction is not only:

```text
who submitted the transaction?
```

The important condition is:

```text
did the delegated EOA's balance decrement below reserve during execution?
```

In both sender modes we tested, once that happened:

```text
dippedIntoReserve() returned true
```

Speaker note:
This is the line to leave people with. Sender role affects gas accounting. It did not stop reserve detection in the tested path.
