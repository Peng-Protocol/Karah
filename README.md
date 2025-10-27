## Overview
`Karah` enables ENS name owners (lessors) to lease names to lessees. Lessees can modify nane and subname records during their lease period without owning the name. While `Konna` is a DAO template allowing lessees to collectively propose and vote on name changes, acting as a single lessee in `Karah`.

**Version**: 0.0.2 (27/10/2025)  
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
DAO template for lessees to collectively manage ENS name changes via proposals, acting as a single lessee in `Karah`.

### Key Parameters
- **Proposal struct**: Tracks `proposer`, `node`, `label`, `subnodeOwner`, `resolver`, `ttl`, `votesFor`, `expiry` (1–26 weeks), `executed`.
- **proposals**: Maps proposal IDs to `Proposal` details.
- **voted**: Maps proposal ID to voter status (`id => address => bool`).
- **members**: Array of DAO members.
- **proposalCount**: Tracks total proposals.
- **karah**: `Karah` contract address (set by owner).
- **owner**: Contract owner.
- **MIN_EXPIRY (1 week), MAX_EXPIRY (26 weeks)**: Proposal validity bounds.

### External Functions
- **addMember(member)**: Owner adds DAO member. Updates `members`.
- **removeMember(member)**: Owner removes member via swap-and-pop. Updates `members`.
- **proposeChange(node, label, subnodeOwner, resolver, ttl, expiry)**: Member creates proposal. Updates `proposals`, `proposalCount`.
- **vote(id, inFavor)**: Member votes. Updates `voted`, `votesFor`.
- **executeChange(id)**: Executes approved proposal. Calls `IKarah.modifyContent`.
- **viewProposals(maxIterations)**: Returns proposal IDs (top-down).
- **setKarah(newKarah)**: Owner sets `Karah` address.
- **transferOwnership(newOwner)**: Owner transfers ownership.

### Insights
- Proposals require majority (`> members.length / 2`) and valid expiry.
- `removeMember` prevents quorum issues from inactive members.
- `viewProposals` uses `maxIterations` for gas efficiency.
- `owner` can be another DAO (DAOception!).
- `voted` ensures no double-voting.