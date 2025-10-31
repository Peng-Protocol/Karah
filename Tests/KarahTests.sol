// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
// File Version: 0.0.5 (31/10/2025)
// Changelog Summary:
// - 31/10/2025: Removed vm_warp cheatcodes; use Karah.warp() instead.
// - 31/10/2025: Warp to exact timestamps before time-sensitive calls.
// - 29/10/2025: Fixed destructuring, replaced tstore/tload with vm.warp.
// - 29/10/2025: Explicit return variable names.

pragma solidity ^0.8.2;

import "../Karah.sol";
import "./MockENS.sol";
import "./MockERC20.sol";
import "./MockKarahTester.sol";

contract KarahTests {
    Karah public karah;
    MockENS public ens;
    MockERC20 public token;
    MockKarahTester[4] public testers;   // [0]=lessor, [1-3]=lessees
    address public tester;
    bytes32 public constant NODE = keccak256("peng.eth");
    uint256 public constant UNIT_COST = 2e18;   // 2 token / day

    constructor() {
        ens = new MockENS();
        token = new MockERC20();
        karah = new Karah();
        karah.setENSRegistry(address(ens));
        tester = msg.sender;

        for (uint i = 0; i < 4; i++) {
            token.mint(address(this), 200_000 * 1e18);
        }
    }

    function initiateTesters() public payable {
        require(msg.sender == tester, "Only tester");
        require(msg.value == 5 ether, "Send exactly 5 ETH");
        for (uint i = 0; i < 4; i++) {
            MockKarahTester t = new MockKarahTester(address(this));
            (bool s,) = address(t).call{value: 1 ether}("");
            require(s, "Fund failed");
            testers[i] = t;
            token.transfer(address(t), 200_000 * 1e18);
        }
    }

    function testMint() public {
        require(msg.sender == tester);
        ens.register{value: 0.0001 ether}(NODE, address(testers[0]));
        require(ens.owner(NODE) == address(testers[0]), "Mint failed");
    }

    function testTerms() public {
    testers[0].proxyCall(
        address(karah),
        abi.encodeWithSignature("createLease(bytes32,uint256,address)", NODE, UNIT_COST, address(token))
    );
    (address lessor, , , , , , , ) = _getLeaseDetails();
    require(lessor == address(testers[0]), "Terms: wrong lessor");
    require(ens.owner(NODE) == address(karah), "ENS not transferred");
}

// Helper: explicit 8-value return
function _getLeaseDetails() internal view returns (
    address lessor, address lessee, uint256 unitCost, uint256 daysLeft,
    address tokenAddr, uint256 currentUnitCost, address currentToken, uint256 leaseId
) {
    return karah.getLeaseDetails(NODE);
}

    function testLease() public {
        _approveTester(1);
        testers[1].proxyCall(
            address(karah),
            abi.encodeWithSignature("subscribe(bytes32,uint256)", NODE, 7)
        );
        (
            , address lessee, , uint256 daysLeft, , , ,
        ) = karah.getLeaseDetails(NODE);
        require(lessee == address(testers[1]) && daysLeft == 7, "Lease failed");
        require(token.balanceOf(address(karah)) == 14e18, "Funds not in Karah");
    }

    function testContentMod() public {
        bytes32 label = keccak256("sub");
        testers[1].proxyCall(
            address(karah),
            abi.encodeWithSignature(
                "modifyContent(bytes32,bytes32,address,address,uint64)",
                NODE, label, address(0xBEEF), address(0xCAFE), uint64(3600)
            )
        );
    }

    function p1TestWithdraw() public {
    // Warp 3 days forward from subscription
    karah.warp(block.timestamp + 3 days);
    uint256 balBefore = token.balanceOf(address(testers[0]));
    testers[0].proxyCall(
        address(karah),
        abi.encodeWithSignature("withdraw(bytes32,uint256)", NODE, 0)
    );
    uint256 withdrawn = token.balanceOf(address(testers[0])) - balBefore;
    require(withdrawn == 6e18, "Wrong withdraw amount");
}

    function p1TestEarlyTermination() public {
    uint256 balBefore = token.balanceOf(address(testers[1]));
    testers[1].proxyCall(
        address(karah),
        abi.encodeWithSignature("endLease(bytes32)", NODE)
    );
    uint256 refunded = token.balanceOf(address(testers[1])) - balBefore;
    require(refunded == 8e18, "Wrong refund");
    (, address lesseeAfter, , , , , , ) = karah.getLeaseDetails(NODE);
    require(lesseeAfter == address(0), "Lease not cleared");
}

    function p2TestLease() public {
        _approveTester(2);
        testers[2].proxyCall(
            address(karah),
            abi.encodeWithSignature("subscribe(bytes32,uint256)", NODE, 7)
        );
        (
            , address lessee, , uint256 daysLeft, , , ,
        ) = karah.getLeaseDetails(NODE);
        require(lessee == address(testers[2]) && daysLeft == 7, "p2 lease failed");
    }

    function p2TestNextLease() public {
    // Warp past first lease expiry
    karah.warp(block.timestamp + 7 days + 1);
    _approveTester(3);
    testers[3].proxyCall(
        address(karah),
        abi.encodeWithSignature("subscribe(bytes32,uint256)", NODE, 7)
    );
    (, address lessee, , uint256 daysLeft, , , , ) = karah.getLeaseDetails(NODE);
    require(lessee == address(testers[3]) && daysLeft == 7, "next lease failed");
}

    function p2TestRenew() public {
        testers[3].proxyCall(
            address(karah),
            abi.encodeWithSignature("renew(bytes32,uint256)", NODE, 7)
        );
        (
            , , , uint256 daysLeft, , , ,
        ) = karah.getLeaseDetails(NODE);
        require(daysLeft == 14, "renew failed");
    }

    function p2TestWithdraw1() public {
    karah.warp(block.timestamp + 14 days + 1);
    uint256 balBefore = token.balanceOf(address(testers[0]));
    testers[0].proxyCall(
        address(karah),
        abi.encodeWithSignature("withdraw(bytes32,uint256)", NODE, 1)
    );
    uint256 withdrawn = token.balanceOf(address(testers[0])) - balBefore;
    require(withdrawn == 14e18, "withdraw lease2 failed");
}

    function p2TestWithdraw2() public {
    uint256 balBefore = token.balanceOf(address(testers[0]));
    testers[0].proxyCall(
        address(karah),
        abi.encodeWithSignature("withdraw(bytes32,uint256)", NODE, 2)
    );
    uint256 withdrawn = token.balanceOf(address(testers[0])) - balBefore;
    require(withdrawn == 14e18, "withdraw lease3 failed");
}

    function testUpdateTerms() public {
        testers[0].proxyCall(
            address(karah),
            abi.encodeWithSignature("updateLeaseTerms(bytes32,uint256,address)", NODE, 4e18, address(token))
        );
        (
            , , , , , uint256 curCost, ,
        ) = karah.getLeaseDetails(NODE);
        require(curCost == 4e18, "terms update failed");
    }

    // **DEV NOTE**: Call `testLease` again to verify 4-token/day rate.

    function testReclamation() public {
    karah.warp(block.timestamp + 30 days);
    testers[0].proxyCall(
        address(karah),
        abi.encodeWithSignature("reclaimName(bytes32)", NODE)
    );
    require(ens.owner(NODE) == address(testers[0]), "reclaim failed");
}

    // **DEV NOTE**: Unwithdrawn revenue is lost on reclaim.

    function _approveTester(uint idx) internal {
        testers[idx].proxyCall(
            address(token),
            abi.encodeWithSignature("approve(address,uint256)", address(karah), type(uint256).max)
        );
    }
}