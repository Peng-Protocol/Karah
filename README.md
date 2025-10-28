## Overview
`Karah` enables ENS name owners (lessors) to lease names to lessees. Lessees can modify name and subname records during their lease period without owning the name. While `Konna` is a DAO template allowing individual groups of lessees to propose and vote on name changes for a particular co-leased name, acting as a single lessee in `Karah`.

**Version**: 0.0.6 (28/10/2025)  
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
- **ensRegistry**, **owner**.
- **leases**: `node => Lease`.
- **agreements**: `node => leaseId => LeaseAgreement` (historical + active).
- **leaseCount**, **leaseNodes**, **lessorNodes**, **lesseeNodes**.
- **nodeTo*Index**: O(1) array ops.
- **lessorLeases**, **lesseeLeases**: `address => node => bool`.

### External Functions
- **createLease(node, unitCost, token)**: Transfers ENS ownership to `Karah`, sets terms.
- **updateLeaseTerms(node, unitCost, token)**: Updates future terms. **Note:** Allowed during active lease — affects renewals only.
- **subscribe(node, durationDays)**: Creates new `LeaseAgreement`, pulls via `transferFrom`, sets `withdrawableAmount = cost`.
- **renew(node, renewalDays)**: Extends current agreement, uses **current** `unitCost`/`currentToken`. **Warning:** If terms changed mid-lease, `withdrawableAmount` may mix tokens (e.g., USDC + DAI). Lessors should avoid token changes during active leases.
- **endLease(node)**: Refunds unused days from `withdrawableAmount`, marks `ended`.
- **reclaimName(node)**: Ends lease + returns ENS ownership to lessor.
- **withdraw(node, leaseId)**: Lessor withdraws earned days from any agreement (active/ended). Uses `daysElapsed = ended ? totalDuration : (now - start)/1d`. Reverts if called at `startTimestamp` (0 days elapsed — correct).
- **modifyContent(...)***: Requires `daysElapsed < totalDuration` (strict; lease expires at exact end).
- **getAgreementDetails(node, leaseId)**: View any historical agreement.
- **Views**: `viewLeases`, `getAllLessorLeases`, `getAllLesseeLeases`, `getLeaseDetails` (active only), `getAgreementCount`, `getActiveLeasesCount`.

### Behavior Clarifications
- **Per-Agreement Accounting**: `withdrawableAmount` is isolated per `LeaseAgreement`. No cross-contamination.
- **Renewal Token Mixing**: If `updateLeaseTerms` changes token, renewal payments use new token. `withdrawableAmount` accumulates mixed tokens. **Documented risk** — lessors must not change token mid-lease.
- **Withdrawal Edge**: `withdraw` at `block.timestamp == startTimestamp` → 0 days → reverts "Nothing to withdraw" (correct).
- **Lease Expiry**: `modifyContent` allows changes for `< totalDuration` days (not `≤`). Standard.
- **Konna Integration**: `executeAcquisition` uses `approve(karah, amount)` → `subscribe` pulls via `transferFrom`. Reverts undo approval.

### Insights
- **Security**: Pre/post balance checks, isolated funds, safe math.
- **Gas**: O(1) array ops via index mappings. Three arrays maintained for top-down views.
- **Future (v0.0.7)**: Consider locking `updateLeaseTerms` while `active == true` to prevent token mixing.

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
- **proposalCount**, **karah**, **owner**.
- **MIN_EXPIRY = 1 weeks**, **MAX_EXPIRY = 26 weeks**.

### External Functions
#### Core
- `addMember`, `removeMember`: Owner-managed membership.
- `proposeChange`, `vote`, `executeChange`: ENS record/subnode updates via `Karah.modifyContent`.
- `viewProposals(maxIterations)`: Top-down proposal IDs.

#### Lease Acquisition
- **proposeLease(node, durationDays, expiry)**: Member proposes lease. Fetches `currentUnitCost`, `currentToken` from `Karah.getLeaseDetails`. Sets `totalNeeded`.
- **voteLease(id, inFavor, amount)**: Member votes + contributes ERC20. Caps pull to `totalNeeded - collected`. Pre/post balance check. Vote counts once.
- **executeAcquisition(id)**: Requires quorum + full funding. approves `karah` to pull `totalNeeded`. Revert-safe. Transfers exact `totalNeeded` to `Karah` by calling `subscribe`. 
- **cancelStaleAcquisition(id)**: Post-expiry, refunds all contributions proportionally.

#### Lease Termination
- **proposeTermination(node, expiry)**: Requires `lessee == address(this)` via `getLeaseDetails`.
- **voteTermination(id, inFavor)**: Standard vote, no funds.
- **executeTermination(id)**: Quorum → calls `Karah.endLease`. Measures **delta balance** (pre/post) to isolate refund. Distributes proportionally via `_refundContributions`.

#### Admin
- `setKarah`, `transferOwnership`.

### Internal Call Trees
- **proposeLease** → `IKarah.getLeaseDetails` (view).
- **voteLease** → `IERC20.transferFrom` + balance checks → updates `collected`, `contributions`.
- **executeAcquisition** → `IERC20.transfer` (to Karah) + balance delta → `IKarah.subscribe`.
- **cancelStaleAcquisition** → `_refundContributions(collected)`.
- **proposeTermination** → `IKarah.getLeaseDetails` (checks lessee).
- **executeTermination** → `IKarah.endLease` → balance delta → `_refundContributions(refund)`.

#### Helpers
- **isMember**: O(n) scan (small DAO).
- **_voteBasic**: Shared vote logic.
- **_refundContributions(id, amount)**: Proportional refund: `share = contrib * amount / collected`. Clears mapping.

### Insights
- **Fund Isolation**: `executeTermination` uses **pre/post balance delta** — prevents draining other proposals (even same token).
- **Contribution Capping**: `voteLease` pulls only what's needed.
- **Proportional Refunds**: On stale or termination, contributors get fair share of actual refund.
- **Quorum**: `> members.length / 2` (strict majority).
- **Gas Control**: `maxIterations` in views; no unbounded loops.
- **Security**: Pre/post checks on all ERC20 moves. No reentrancy (single external call).
- **Flexibility**: Supports any ERC20 per lease. DAO can hold multiple leases.
- `owner` can be another DAO (DAOception!).