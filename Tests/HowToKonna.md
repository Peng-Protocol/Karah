# Running Konna Tests in Remix

## Prerequisites
- Ensure `Karah.sol`, `Konna.sol`, `MockENS.sol`, `MockERC20.sol`, `MockKarahTester.sol`, and `KonnaTests.sol` are in your workspace.
- Place `Karah.sol` in `./Karah`, `Konna.sol` in `./Konna`.
- Place mocks and `KonnaTests.sol` in `./Tests`.

## Steps
1. Open Remix.
2. Upload all contracts to correct directories.
3. Compile with `^0.8.2`.
4. Use **Remix VM**, default account (100 ETH).
5. Deploy `KonnaTests`.
6. Call `deployTesters()` with **5 ETH**..
7. Call `addParticipants()`.
8. Call `testMint()`.
9. Call `testTerms()`.
10. Call `testLease()`.
11. Call `testContentMod()`.
12. Call `testEarlyTermination()`.
    - **DEV NOTE**: Call `testLease` again to start new lease.
13. Call `testRenew()`:
    
## Objectives
6. `deployTesters()`:
   - **Objective**: Deploys 4 testers: `[0]` = lessor, `[1]` = Konna owner, `[2-3]` = DAO members. Each gets 1 ETH + 200k tokens.
   - **Looking For**: Successful setup.
7. `addParticipants()`:
   - **Objective**: Konna owner adds testers 2 & 3 as DAO members.
   - **Looking For**: Members array updated.
8. `testMint()`:
   - **Objective**: Lessor registers `peng.eth`.
   - **Looking For**: `ens.owner(NODE) == testers[0]`.
9. `testTerms()`:
   - **Objective**: Lessor sets lease terms (2 tokens/day).
   - **Looking For**: ENS transferred to `Karah`.
10. `testLease()`:
    - **Objective**: Member 2 proposes 7-day lease → both members vote + fund → execute → Konna becomes lessee.
    - **Looking For**: `lessee == konna`, `daysLeft == 7`, funds in `Karah`.
11. `testContentMod()`:
    - **Objective**: Member proposes ENS content change → vote → execute via `Karah`.
    - **Looking For**: Call succeeds.
12. `testEarlyTermination()`:
    - **Objective**: Fast-forward 3 days → member proposes termination → vote → execute → refund to contributors.
    - **Looking For**: Lease ended, `lessee == address(0)`, refund issued.
    - **DEV NOTE**: Call `testLease` again to start new lease.
13. `testRenew()`:
    - **Objective**: New lease proposal for 7 days → vote → execute → extends to 14 days.
    - **Looking For**: `daysLeft == 14`.

## Notes
- All DAO actions require **2/3 member votes** (quorum).
- Funding via `voteLease` pulls tokens from members.
- Refunds on termination are **proportional**.
- Uses `konna.warp` for time control.
- Monitor console for `ProposalExecuted`, reverts.
- Gas limit ≥ 10M.