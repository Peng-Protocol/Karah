## Overview
`Karah` enables ENS name owners (lessors) to lease names to lessees, who can modify subnodes and main name records (not ownership). `Konna` is a DAO allowing lessees to collectively propose and vote on name changes, acting as a single lessee in `Karah`.

**Version**: 0.0.1 (27/10/2025)  
**License**: BSL 1.1 - Peng Protocol 2025  
**Solidity**: ^0.8.2  

## Karah Contract
**Purpose**: Manages ENS name leasing, with the contract owning names during leases.  
**Key Parameters**:
- `Lease` struct: Tracks `lessor`, `lessee`, `unitCost` (cost/day), `totalDuration` (total leased days), `token`, `currentUnitCost`, `currentToken`, `startTimestamp`.
- `EndLeaseData` struct: Internal struct for `endLease` refund calculations (`daysElapsed`, `daysLeft`, `refund`, `available`).
- `ensRegistry`: Configurable ENS registry (owner-only).
- `owner`: Contract owner.
- `leases`: Maps nodes to `Lease` details.
- `leaseNodes`, `lessorNodes`, `lesseeNodes`: Arrays for tracking leases.
- `nodeToLeaseNodesIndex`, `nodeToLessorNodesIndex`, `nodeToLesseeNodesIndex`: Maps for O(1) array operations.
- `lessorLeases`, `lesseeLeases`: Maps for efficient lease lookups.
- `withdrawable`: Lessor funds.
- `withdrawnPerLease`: Lessor => node => withdrawn amount.
**External Functions** (Internal Call Trees):
- `createLease(node, unitCost, token)`: Transfers name to `Karah`, sets terms. Calls `IENS.owner`, `setOwner`.
- `updateLeaseTerms(node, unitCost, token)`: Updates terms.
- `subscribe(node, durationDays)`: Initiates lease, updates mappings/arrays, sets index mappings. Calls `IERC20.transferFrom`, `balanceOf`, `IENS.setOwner`.
- `renew(node, renewalDays)`: Extends lease. Calls `IERC20.transferFrom`, `balanceOf`.
- `endLease(node)`: Refunds unused days dynamically, removes node via O(1) swap-and-pop. Calls `_calculateRefund`, `_updateArrays`, `_updateLeaseState`, `IERC20.transfer`, `IENS.setOwner`.
  - `_calculateRefund`: Computes `daysElapsed`, `daysLeft`, `refund`, `available`.
  - `_updateArrays`: Performs O(1) swap-and-pop for `leaseNodes`, `lessorNodes`, `lesseeNodes`.
  - `_updateLeaseState`: Updates lease state, processes refund.
- `reclaimName(node)`: Ends lease, refunds, reclaims name. Calls `IERC20.transfer`, `IENS.setOwner`.
- `withdraw(node)`: Lessor withdraws earned funds per lease, tracks via `withdrawnPerLease`. Calls `IERC20.transfer`.
- `modifyContent(node, label, subnodeOwner, resolver, ttl)`: Lessee modifies subnodes/records. Calls `IENS.setSubnodeOwner`, `IENS.setRecord`.
- `setENSRegistry(newRegistry)`: Owner updates ENS registry.
- `transferOwnership(newOwner)`: Owner transfers ownership.
- View functions: `viewLeases`, `getAllLessorLeases`, `getAllLesseeLeases`, `getLeaseDetails` (dynamic `daysLeft`), `getActiveLeasesCount`.
**Insights**:
- `totalDuration` and `startTimestamp` enable dynamic `daysLeft`, preventing over-refunded exploits.
- `nodeTo*Index` mappings ensure O(1) array operations, mitigating gas-limit risks in `endLease` and `reclaimName`.
- `lessorLeases`, `lesseeLeases` reduce gas for view functions.
- `withdrawnPerLease` ensures precise withdrawal tracking, fixed to avoid double-dipping by not reducing `withdrawable` on withdrawal.
- `endLease` helper functions (`_calculateRefund`, `_updateArrays`, `_updateLeaseState`) reduce stack usage, fixing compilation errors.

## Konna Contract
**Purpose**: DAO template for lessees to collectively manage ENS name changes via proposals, acting as a lessee in `Karah`.  
**Key Parameters**:
- `Proposal` struct: Tracks `proposer`, `node`, `label`, `subnodeOwner` (subnode owner), `resolver`, `ttl`, `votesFor`, `expiry` (1–26 weeks), `executed`.
- `proposals`: Maps proposal IDs to `Proposal` details.
- `voted`: Maps proposal ID to voter status.
- `members`: Array of DAO members.
- `proposalCount`: Tracks total proposals.
- `karah`: `Karah` contract address (set by owner).
- `owner`: Contract owner for administrative functions.
- `MIN_EXPIRY` (1 week), `MAX_EXPIRY` (26 weeks): Proposal validity bounds.
**External Functions** (Internal Call Trees):
- `addMember(member)`: Owner adds DAO member. Updates `members`.
- `removeMember(member)`: Owner removes member via swap-and-pop. Updates `members`.
- `proposeChange(node, label, subnodeOwner, resolver, ttl, expiry)`: Member creates proposal. Updates `proposals`, `proposalCount`.
- `vote(id, inFavor)`: Member votes. Updates `voted`, `votesFor`.
- `executeChange(id)`: Executes approved proposal. Calls `IKarah.modifyContent`.
- `viewProposals(maxIterations)`: Returns proposal IDs (top-down).
- `setKarah(newKarah)`: Owner sets `Karah` address.
- `transferOwnership(newOwner)`: Owner transfers ownership.
**Insights**:
- Proposals require majority (`> members.length / 2`) and valid expiry.
- `removeMember` prevents quorum issues from inactive members.
- `owner` can be another DAO (DAOception!). 
- Gas-efficient `viewProposals` uses `maxIterations`.
- `voted` ensures no double-voting.