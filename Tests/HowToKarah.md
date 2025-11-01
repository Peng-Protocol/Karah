# Running Karah Tests in Remix

## Prerequisites
- Ensure `Karah.sol`, `MockENS.sol`, `MockERC20.sol`, `MockKarahTester.sol`, and `KarahTests.sol` are in your Remix workspace.
- Place `Karah.sol` in `./Karah`.
- Place mock contracts and `KarahTests.sol` in `./Tests`.

## Steps
1. Open Remix[](https://remix.ethereum.org).
2. Upload all contracts to the specified directories.
3. In "Solidity Compiler", select `^0.8.2` and compile all.
4. In "Deploy & Run Transactions", select **Remix VM**.
5. Ensure default account has 100 ETH.
6. Deploy `KarahTests` using the default account.
7. Call `initiateTesters()` with **5 ETH** (value field).
8. Call `testMint()`.
9. Call `testTerms()`.
10. Call `testLease()`.
11. Call `testContentMod()`.
12. Call `p1TestWithdraw()`.
13. Call `p1TestEarlyTermination()`.
14. Call `p2TestLease()`.
15. Call `p2TestNextLease()`.
16. Call `p2TestRenew()`.
17. Call `p2TestWithdraw1()`.
18. Call `p2TestWithdraw2()`.
19. Call `testUpdateTerms()`.
    - **DEV NOTE**: Call `testLease` again to verify new rate.
20. Call `testReclamation()`.
    
## Objectives
7. `initiateTesters()`:
   - **Objective**: Deploys 4 `MockKarahTester` contracts: `[0]` = lessor, `[1-3]` = lessees. Each gets 1 ETH + 200,000 mock tokens.
   - **Looking For**: Successful deployment, ETH/token distribution.
   - **Avoid**: Wrong ETH value, failed transfers.
   
 8. `testMint()`:
  - **Objective**: Lessor registers `peng.eth` via `MockENS.register` (0.0001 ETH).
   - **Looking For**: `ens.owner(NODE) == testers[0]`.
   
9. `testTerms()`:
   - **Objective**: Lessor creates lease: 2 tokens/day. ENS transfers to `Karah`.
   - **Looking For**: `ens.owner(NODE) == karah`, correct lease terms.
  
10. `testLease()`:
    - **Objective**: Tester 2 subscribes for 7 days (14 tokens total). Funds pulled to `Karah`.
    - **Looking For**: `lessee == testers[2]`, `daysLeft == 7`, `karah.token.balance == 14e18`.
    
11. `testContentMod()`:
    - **Objective**: Tester 2 modifies ENS subnode/resolver via `Karah`.
    - **Looking For**: Call succeeds (mock ENS allows).
    
12. `p1TestWithdraw()`:
    - **Objective**: Fast-forward 3 days → lessor withdraws 6 tokens (3 × 2).
    - **Looking For**: Correct withdrawal, no over-withdraw.
    
13. `p1TestEarlyTermination()`:
    - **Objective**: Tester 2 ends lease early → refunds 8 tokens (4 days left).
    - **Looking For**: Refund correct, lease cleared (`lessee == address(0)`).
    
14. `p2TestLease()`:
    - **Objective**: Tester 3 subscribes for 7 days (new lease #1).
    - **Looking For**: New lease active.
    
15. `p2TestNextLease()`:
    - **Objective**: Fast-forward past current lease → Tester 4 subscribes.
    - **Looking For**: Lease #2 active.
    
16. `p2TestRenew()`:
    - **Objective**: Tester 4 renews for 7 days → total 14 days.
    - **Looking For**: `daysLeft == 14`.
    
17. `p2TestWithdraw1()`:
    - **Objective**: Fast-forward to end → lessor withdraws full 14 tokens from lease #2.
    - **Looking For**: Full claim.
    
18. `p2TestWithdraw2()`:
    - **Objective**: Lessor withdraws full 14 tokens from lease #3 (even with no active lease).
    - **Looking For**: Historical withdrawals work.
    
19. `testUpdateTerms()`:
    - **Objective**: Lessor updates rate to 4 tokens/day.
    - **Looking For**: `currentUnitCost == 4e18`.
    - **DEV NOTE**: Call `testLease` again to verify new rate.
    
20. `testReclamation()`:
    - **Objective**: Fast-forward → lessor reclaims ENS name.
    - **Looking For**: `ens.owner(NODE) == testers[0]`, lease data cleared.
    - **DEV NOTE**: Any unwithdrawn revenue is **lost** on reclaim.
    
## Notes
- All calls use default account.
- Set gas limit ≥ 10M.
- Verify paths in imports.
- Time skips via `karah.warp`, custom time testing function.
- Monitor console for reverts.