# routr (ROUTR)

A fixed-supply ERC-20 token for an IdentityMD custom token launch on Ethereum (chain id 1).

| Field | Value |
|-------|-------|
| Solidity contract | `RoutrToken` (`src/RoutrToken.sol`) |
| `name()` | `routr` |
| `symbol()` | `ROUTR` |
| `decimals()` | `18` |
| Total supply | 1,000,000,000 ROUTR = `1000000000000000000000000000` minor units |
| Minted to | `msg.sender` of the constructor, once, in the constructor |
| Constructor arguments | none |
| Owner / admin | none |

## Behaviour

- The constructor mints the whole supply to the deployer and emits `Transfer(0, deployer, supply)` and `SupplyMinted(deployer, supply)`. `INITIAL_HOLDER()` records that address.
- There is no `mint`, `burn`, `pause`, blocklist, freeze, fee, tax, reflection or owner. `totalSupply()` can never increase after deployment, and nobody can move or freeze a holder's balance except through the holder's own `transfer`/`approve`.
- Transfers are OpenZeppelin v5 `ERC20` transfers: every transfer and `transferFrom` moves exactly the amount requested, so the launch flows (swarm share to the MerkleDistributor, pool seed through the Uniswap v4 PoolManager, remainder to the requester) arrive whole, and traders buy from and sell into the pool without a fee.
- `transferFrom` moves tokens only with the token owner's allowance, including when the deployer calls it.
- The contract has no `receive` or `fallback`, so it rejects ether.
- The constructor makes no external calls and needs no deployed contract, so it deploys on an empty chain.
- No library calls, no `delegatecall`, no `selfdestruct`, no proxy, no initializer.

## Deployment parameters

The token has no constructor arguments. Whoever deploys it holds the supply.

On the IdentityMD launch, the ProjectFactory deploys the token from the built bytecode, so the factory is `msg.sender` and receives the full supply. The factory then forwards the swarm's 10% to the launch's MerkleDistributor, seeds the pool with the requester's `poolBps` and sends the remainder to `economics.remainderTo`. None of that is coded in the token.

Launch values decided by the launch, for reference only (the manifest step writes `launch.json`; this repository does not contain one):

| Setting | Value |
|---------|-------|
| Chain | Ethereum, chain id 1 |
| Paired currency | IMD, `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7` |
| Pool fee | 12500 (1.25%) |
| Tick spacing | 60 |
| `economics.poolBps` | 8800 |
| `economics.initialMarketCapWei` | `2500000000000000000000` (2,500 IMD for the whole supply) |
| `economics.remainderTo` | `0x1ee3ffadfe138415a2ddaedeebe5f46616fa413d` |
| `token.totalSupply` | `1000000000000000000000000000` |
| `token.decimals` | 18 |

Build settings in `foundry.toml`: `solc = "0.8.26"`, `evm_version = "cancun"`, optimizer on at 200 runs, `bytecode_hash = "none"` and `cbor_metadata = false` so the deployed bytes are reproducible without a metadata hash.

## After launch

Nothing to configure. The token has no owner-settable values, no setters and no privileged roles. There are no operational responsibilities beyond the ordinary ones for any ERC-20:

- Whoever holds the deployer's tokens (on a launch, the factory, then the distributor, pool and `remainderTo` wallet) is responsible for their own keys and approvals.
- Holders should only approve spenders they trust; the usual ERC-20 approval front-running caveat applies when changing a non-zero allowance (set to zero first, or use the spender's own allowance flow).
- There is no upgrade path and no way to recover tokens sent to the token contract itself or to a wrong address.

## Assumptions and open items

- The brief named the deployer as the recipient of the supply and gave no owner, tax, burn or vesting rules, so the token has no admin surface at all. If a privileged power is wanted later, it needs a new contract; this one cannot be changed.
- The `SupplyMinted` event and the `TOKEN_NAME`, `TOKEN_SYMBOL`, `DECIMALS`, `TOTAL_SUPPLY` and `INITIAL_HOLDER` getters are conveniences beyond the ERC-20 standard. They are read-only.
- `script/DeployRoutrToken.s.sol` is a reviewable reference deployment for local use; the IdentityMD launch deploys the token itself. Nothing in this repository broadcasts a transaction or holds a key.
- Tests passing is not a security audit. The token is a thin wrapper over OpenZeppelin v5.4.0 `ERC20`, but an independent adversarial review before release is still the launch policy's responsibility. Slither was not run here (not available in this environment); the source avoids the patterns the verifier's Slither detectors reject (no `selfdestruct`, no `delegatecall`, no arbitrary `transferFrom` source, no initializer, no shifts, no `abi.encodePacked` of dynamic values).

## Layout

```
foundry.toml                 compiler pins and build settings
remappings.txt               forge-std and @openzeppelin/contracts remappings
src/RoutrToken.sol           the token
script/DeployRoutrToken.s.sol reference deploy script (deploy() is called by the tests)
test/RoutrToken.t.sol        unit and fuzz tests
lib/forge-std                forge-std v1.9.7, vendored as plain files
lib/openzeppelin-contracts   OpenZeppelin Contracts v5.4.0, vendored as plain files
```

Dependencies are committed as ordinary files, not git submodules, so the project builds offline.

## Tests

```
forge build
forge test
forge fmt --check
```

`test/RoutrToken.t.sol` covers:

- metadata, supply constants, and that the constructor mints the whole supply to `msg.sender`, including when a contract (standing in for the factory) deploys it;
- the constructor's events, independence of separate deployments, and the deploy script's `deploy()` function;
- `transfer` success paths (exact amount, whole balance, zero, self) and failure paths (insufficient balance, empty account, zero-address receiver);
- `approve` and `transferFrom` success paths (allowance spent, infinite allowance kept) and failure paths (no allowance, beyond allowance, owner balance too low, deployer pulling without allowance, zero-address spender);
- that none of the common mint, admin, pause, blocklist, freeze, lock, seize or burnFrom selectors exist, from a stranger or the deployer, and that a holder keeps and can still move its balance afterwards;
- that the contract rejects ether, fits EIP-170, and has no reachable `DELEGATECALL`, `CALLCODE` or `SELFDESTRUCT` in its runtime code;
- fuzz tests for supply conservation across single and chained transfers, revert above balance, and allowance accounting.

Tests read no environment variables and do not depend on the calling address, so they pass in any order and in parallel. The fuzz tests pass with the verifier's seed `FOUNDRY_FUZZ_SEED=0x1921b91ff5bde5859d6ac675e1760039cfee1b855d4b2e8983a8ede2afcc1aa3`.
