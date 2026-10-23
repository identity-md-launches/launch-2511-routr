# ROUTR test coverage

The original `RoutrToken.t.sol` retains deployment, metadata, issuance, factory
distribution, basic ERC-20, and absent-admin-function checks.

`RoutrTokenProperties.t.sol` adds deterministic boundary cases and eight fuzz
properties (1,000 runs each). These cover approval replacement, revocation,
independent owner/spender pairs, finite versus unlimited spending, delegated
self-transfers, exact exhaustion, transfer round trips, and approval before funding.
Rejected transfers must preserve balances, supply, and allowances. Boundary tests
pin zero, one wei, the entire supply, `uint256.max`, and `uint256.max - 1`.

`RoutrTokenInvariant.t.sol` runs 256 random sequences of 128 handler calls with
`fail-on-revert` enabled. Only the seven action selectors in
`handlers/RoutrTokenHandler.sol` are targeted. Four actors hold the complete supply;
all successful transfers remain within that set. Initial balances and permissions
are established through real token calls, with no token storage overrides.

Two invariants are checked after each action:

- Total supply stays at `1_000_000_000 * 10**18`. Each holder's balance plus recorded
  debits equals recorded credits, and the sum of balances equals the fixed supply.
  Metadata and the initial-holder address remain unchanged.
- Every owner/spender allowance equals the independent authorization record.
  Only approvals and successful finite-allowance spending update that record.

The handler mixes valid transfers, full-balance transfers, approval changes,
delegated spending, insufficient balances/allowances, revocation, and zero-address
failures. Expected failures are checked for their exact revert data; unexpected
successes or reverts fail the suite. Credits/debits use requested amounts, not
observed token balances. A deterministic handler sequence also exercises positive
transfers and every deliberate failure mode.

Run from the repository root with the existing vendored dependencies:

```sh
forge build --offline --out test/scratch/out --cache-path test/scratch/cache
FOUNDRY_FUZZ_SEED=0x1921b91ff5bde5859d6ac675e1760039cfee1b855d4b2e8983a8ede2afcc1aa3 forge test --offline --out test/scratch/out --cache-path test/scratch/cache
```

The suite requires no fork, RPC, FFI, or environment setup beyond the optional fuzz
seed. Nothing under `test/scratch/` is imported or needed by the submitted tests.
