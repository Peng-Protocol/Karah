## Overview
`Karah` enables ENS name owners (lessors) to lease names to lessees. Lessees can modify name and subname records during their lease period without owning the name. While `Konna` is a DAO template allowing individual groups of lessees to propose and vote on name changes for a particular co-leased name, acting as a single lessee in `Karah`.

**Version**: 0.0.3 (28/10/2025)  
**License**: BSL 1.1 - Peng Protocol 2025  
**Solidity**: ^0.8.2  

---

## Karah Contract

### Purpose
Manages ENS name leasing, with `Karah` owning names during active lease terms. Lessees can modify subnodes and records, while lessors retain ultimate control via reclamation.

### Key Parameters
- **Lease struct**: Tracks lease details:
  - `lessor`: Address of the ENS name owner.
  - `lessee`: Address of the current lessee (`address(0)` if none).
  - `unitCost`: Cost per day for the active lease.
  - `totalDuration`: Total leased days.
  - `token`: Payment token for the active lease.
  - `currentUnitCost`: Cost per day for new/renewed leases.
  - `currentToken`: Payment token for new/renewed leases.
  - `startTimestamp`: Lease start time.
- **EndLeaseData struct**: Internal struct for `endLease` calculations (`daysElapsed`, `daysLeft`, `refund`, `available`).
- **ensRegistry**: Configurable ENS registry address (owner-only).
- **owner**: Contract owner for administrative functions.
- **leases**: Maps ENS nodes (`bytes32`) to `Lease` details.
- **leaseNodes, lessorNodes, lesseeNodes**: Arrays for tracking active leases.
- **nodeToLeaseNodesIndex, nodeToLessorNodesIndex, nodeToLesseeNodesIndex**: Maps for O(1) array operations.
- **lessorLeases, lesseeLeases**: Maps for efficient lease lookups (`address => node => bool`).
- **withdrawable**: Lessor’s available funds (`address => uint256`).
- **withdrawnPerLease**: Tracks withdrawn amounts per lease (`address => node => uint256`).

### External Functions
- **createLease(node, unitCost, token)**: 
  - Transfers ENS name ownership to `Karah`, sets initial lease terms (`currentUnitCost`, `currentToken`, `lessor`).
  - Calls: `IENS.owner`, `IENS.setOwner`.
- **updateLeaseTerms(node, unitCost, token)**: Updates `currentUnitCost` and `currentToken` for future leases.
- **subscribe(node, durationDays)**: Initiates a lease, sets `lessee`, `totalDuration`, `unitCost`, `token`, `startTimestamp`. Updates arrays and mappings. Assumes `Karah` owns the name (set by `createLease`).
  - Calls: `IERC20.transferFrom`, `IERC20.balanceOf`.
- **renew(node, renewalDays)**: Extends lease duration, applies `currentUnitCost` and `currentToken`.
  - Calls: `IERC20.transferFrom`, `IERC20.balanceOf`.
- **endLease(node)**: Clears lease (`lessee = address(0)`, `totalDuration = 0`), refunds unused days, keeps ownership with `Karah`.
  - Calls: `_calculateRefund`, `_updateArrays`, `_updateLeaseState`, `IERC20.transfer`.
  - Helpers:
    - `_calculateRefund`: Computes `daysElapsed`, `daysLeft`, `refund`, `available`.
    - `_updateArrays`: O(1) swap-and-pop for `leaseNodes`, `lessorNodes`, `lesseeNodes`.
    - `_updateLeaseState`: Updates state, processes refund.
- **reclaimName(node)**: Terminates lease terms, refunds unused days, returns ownership to lessor.
  - Calls: `IERC20.transfer`, `IENS.setOwner`.
- **withdraw(node)**: Lessor withdraws earned funds, tracked via `withdrawnPerLease`.
  - Calls: `IERC20.transfer`.
- **modifyContent(node, label, subnodeOwner, resolver, ttl)**: Lessee modifies subnodes or records if lease is active.
  - Calls: `IENS.setSubnodeOwner`, `IENS.setRecord`.
- **setENSRegistry(newRegistry)**: Owner updates ENS registry address.
- **transferOwnership(newOwner)**: Owner transfers contract ownership.
- **View functions**:
  - `viewLeases(maxIterations)`: Returns active lease nodes (top-down).
  - `getAllLessorLeases(lessor, maxIterations)`: Returns lessor’s active leases.
  - `getAllLesseeLeases(lessee, maxIterations)`: Returns lessee’s active leases.
  - `getLeaseDetails(node)`: Returns lease details with dynamic `daysLeft`.
  - `getActiveLeasesCount`: Returns total active leases.

### Behavior Clarifications
- **Lease Lifecycle**:
  - Lessor calls `createLease` to transfer ENS name ownership to `Karah` and set terms (`currentUnitCost`, `currentToken`).
  - Lessee subscribes via `subscribe`, using current terms. `Karah` retains ownership (no transfer needed).
  - Lessee can renew (`renew`) or end the lease (`endLease`). `endLease` clears the lease but keeps ownership with `Karah`, allowing new subscriptions.
  - Lessor can update terms (`updateLeaseTerms`) for future leases or reclaim the name (`reclaimName`), which returns ownership to them, ending lease terms.

### Insights
- `totalDuration` and `startTimestamp` enable dynamic `daysLeft`, preventing refund exploits.
- `nodeTo*Index` mappings ensure O(1) array operations in `endLease` and `reclaimName`, mitigating gas-limit risks.
- `withdrawnPerLease` tracks withdrawals, avoiding double-dipping (fixed by not reducing `withdrawable` on withdrawal).
- `endLease` helper functions reduce stack usage, resolving compilation errors.
- Ownership retention in `endLease` ensures seamless re-leasing without external ownership risks.

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
- **executeAcquisition(id)**: Requires quorum + full funding. Transfers exact `totalNeeded` to `Karah`, calls `subscribe`. Pre/post check.
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