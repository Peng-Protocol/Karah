## Overview
`Karah` enables ENS name owners (lessors) to lease names to lessees. Lessees can modify name and subname records during their lease period without owning the name. While `Konna` is a DAO template allowing individual groups of lessees to propose and vote on name changes for a particular co-leased name, acting as a single lessee in `Karah`.

**Version**: 0.0.11 (31/10/2025)  
**License**: BSL 1.1 - Peng Protocol 2025  
**Solidity**: ^0.8.2  

---

## Karah Contract

### Purpose
Manages ENS name leasing, with `Karah` owning names during active lease terms. Lessees can modify subnodes and records, while lessors retain ultimate control via reclamation.

### Key Parameters
- **Lease struct**: `lessor`, `currentUnitCost`, `currentToken`, `agreementCount`, `active`.
- **LeaseAgreement struct**: Per-lease history:
  - `lessee`, `unitCost`, `token`, `totalDuration`, `startTimestamp`, `daysWithdrawn`, `withdrawableAmount`, `ended`.
- **ensRegistry**, **owner**, `currentTime`, `isWarped`.
- **leases**: `node => Lease`.
- **agreements**: `node => leaseId => LeaseAgreement` (historical + active).
- **leaseCount**, **leaseNodes**, **lessorNodes**, **lesseeNodes**.
- **nodeTo*Index**: O(1) array ops.
- **lessorLeases**, **lesseeLeases**: `address => node => bool`.

### External Functions
- **createLease(node, unitCost, token)**: Transfers ENS ownership to `Karah`, sets terms.
- **updateLeaseTerms(node, unitCost, token)**: Updates future terms. **Note:** Allowed during active lease — affects renewals only.
- **subscribe(node, durationDays)**: Creates new `LeaseAgreement`, pulls via `transferFrom`, sets `withdrawableAmount = cost`, uses `_now()` for `startTimestamp`.
- **renew(node, renewalDays)**: Extends current agreement, uses **current** `unitCost`/`currentToken`. **Warning:** If terms changed mid-lease, `withdrawableAmount` may mix tokens (e.g., USDC + DAI). Lessors should avoid token changes during active leases.
- **endLease(node)**: Refunds unused days from `withdrawableAmount`, marks `ended`.
- **reclaimName(node)**: Ends lease + returns ENS ownership to lessor.
- **withdraw(node, leaseId)**: Lessor withdraws earned days from any agreement (active/ended). Uses `daysElapsed = ended ? totalDuration : (current - start)/1d` via `_now()`. Reverts if called at `startTimestamp` (0 days elapsed — correct).
- **modifyContent(...)***: Requires `daysElapsed < totalDuration` via `_now()` (strict; lease expires at exact end).
- **warp(timestamp)** / **unWarp()**: Owner-only time control for testing. `currentTime` stores effective time; `isWarped` toggles mode.
- **getAgreementDetails(node, leaseId)**: View any historical agreement.
- **Views**: `viewLeases`, `getAllLessorLeases`, `getAllLesseeLeases`, `getLeaseDetails` (active only, uses `_now()`), `getAgreementCount`, `getActiveLeasesCount`.

### Internal Call Trees
- **subscribe** → `_now()` → sets `startTimestamp`.
- **_calculateRefund** → `_now()` → computes `daysElapsed`.
- **withdraw** → `_now()` → computes `daysElapsed`.
- **modifyContent** → `_now()` → checks expiry.
- **getLeaseDetails** → `_now()` → computes `daysLeft`.

### Behavior Clarifications
- **Per-Agreement Accounting**: `withdrawableAmount` is isolated per `LeaseAgreement`. No cross-contamination.
- **Renewal Token Mixing**: If `updateLeaseTerms` changes token, renewal payments use new token. `withdrawableAmount` accumulates mixed tokens. **Documented risk** — lessors must not change token mid-lease.
- **Withdrawal Edge**: `withdraw` at `currentTime == startTimestamp` → 0 days → reverts "Nothing to withdraw" (correct).
- **Lease Expiry**: `modifyContent` allows changes for `< totalDuration` days (not `≤`). Standard.
- **Time Warping**: `warp()` sets `currentTime` and `isWarped=true`. All time-sensitive logic uses `_now()`. `unWarp()` resets to `block.timestamp`.

### Insights
- **Security**: Pre/post balance checks, isolated funds, safe math.
- **Gas**: O(1) array ops via index mappings. Three arrays maintained for top-down views.
- **Testability**: Full time control via `warp()`/`unWarp()` for deterministic testing.
- **Future (v0.0.12)**: Consider locking `updateLeaseTerms` while `active == true` to prevent token mixing.

---

## Konna Contract

### Purpose
DAO template for lessees to collectively acquire and manage ENS name leases via proposals. Acts as a `Karah` lessee executing content changes, lease acquisition and termination.

### Key Parameters
- **Proposal struct**: `proposer`, `node`, `label`, `subnodeOwner`, `resolver`, `ttl`, `votesFor`, `expiry` (1–26 weeks), `executed`.
- **LeaseProposal struct**: `totalNeeded`, `collected`, `token`, `durationDays`.
- **proposals**: `id => Proposal`.
- **leaseProps**: `id => LeaseProposal` (for acquisition/termination).
- **contributions**: `id => voter => amount` (ERC20 contributed).
- **voted**: `id => voter => voted`.
- **members**: DAO members array.
- **proposalCount**, **karah**, **owner**, `currentTime`, `isWarped`.

### External Functions
#### Core
- `addMember`, `removeMember`: Owner-managed membership.
- `proposeChange`, `vote`, `executeChange`: ENS record/subnode updates via `Karah.modifyContent`. Uses `_now()` for expiry.
- `viewProposals(maxIterations)`: Top-down proposal IDs.

#### Lease Acquisition
- **proposeLease(node, durationDays, expiry)**: Member proposes lease. Fetches `currentUnitCost`, `currentToken` from `Karah.getLeaseDetails`. Sets `totalNeeded`. Uses `_now()` for expiry.
- **voteLease(id, inFavor, amount)**: Member votes + contributes ERC20. Caps pull to `totalNeeded - collected`. Pre/post balance check. Vote counts once. Uses `_now()` for expiry.
- **executeAcquisition(id)**: Requires quorum + full funding. approves `karah` to pull `totalNeeded`. Revert-safe. Transfers exact `totalNeeded` to `Karah` by calling `subscribe`. Uses `_now()` for expiry.
- **cancelStaleAcquisition(id)**: Post-expiry (via `_now()`), refunds all contributions proportionally.

#### Lease Termination
- **proposeTermination(node, expiry)**: Requires `lessee == address(this)` via `getLeaseDetails`. Uses `_now()` for expiry.
- **voteTermination(id, inFavor)**: Standard vote, no funds. Uses `_now()` for expiry.
- **executeTermination(id)**: Quorum → calls `Karah.endLease`. Measures **delta balance** (pre/post) to isolate refund. Distributes proportionally via `_refundContributions`. Uses `_now()` for expiry.

#### Admin
- `setKarah`, `transferOwnership`, **warp(timestamp)**, **unWarp()**: Time control for testing.

### Internal Call Trees
- **proposeLease** → `IKarah.getLeaseDetails` (view) → `_now()` for expiry.
- **voteLease** → `IERC20.transferFrom` + balance checks → updates `collected`, `contributions` → `_now()` for expiry.
- **executeAcquisition** → `IERC20.approve` → `IKarah.subscribe` → `_now()` for expiry.
- **cancelStaleAcquisition** → `_now()` → `_refundContributions(collected)`.
- **proposeTermination** → `IKarah.getLeaseDetails` → `_now()` for expiry.
- **executeTermination** → `IKarah.endLease` → balance delta → `_refundContributions(refund)` → `_now()` for expiry.
- **_voteBasic** → `_now()` for expiry.
- **warp/unWarp** → control `currentTime`, `isWarped`.

#### Helpers
- **isMember**: O(n) scan (small DAO).
- **_voteBasic**: Shared vote logic with `_now()`.
- **_refundContributions(id, amount)**: Proportional refund: `share = contrib * amount / collected`. Clears mapping.
- **_now()**: Returns `currentTime` if `isWarped`, else `block.timestamp`.

### Insights
- **Fund Isolation**: `executeTermination` uses **pre/post balance delta** — prevents draining other proposals (even same token).
- **Contribution Capping**: `voteLease` pulls only what's needed.
- **Proportional Refunds**: On stale or termination, contributors get fair share of actual refund.
- **Quorum**: `> members.length / 2` (strict majority).
- **Gas Control**: `maxIterations` in views; no unbounded loops.
- **Security**: Pre/post checks on all ERC20 moves. No reentrancy (single external call).
- **Flexibility**: Supports any ERC20 per lease. DAO can hold multiple leases.
- **Testability**: Full time control via `warp()`/`unWarp()` for deterministic proposal expiry, acquisition, and termination testing.
- `owner` can be another DAO (DAOception!).