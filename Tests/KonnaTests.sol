// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
// File Version: 0.0.2 (29/10/2025)
// Changelog:
// - 29/10/2025: Fixed parser errors (days → durationDays, missing commas).
// - 29/10/2025: Corrected proposeLease signature.

pragma solidity ^0.8.2;

import "../Karah.sol";
import "../Konna.sol";
import "./MockENS.sol";
import "./MockERC20.sol";
import "./MockKarahTester.sol";

contract KonnaTests {
    Karah public karah;
    Konna public konna;
    MockENS public ens;
    MockERC20 public token;
    MockKarahTester[4] public testers; // [0]=lessor, [1]=konna owner, [2-3]=members
    address public tester;
    bytes32 public constant NODE = keccak256("peng.eth");
    uint256 public constant UNIT_COST = 2e18;

    constructor() {
        ens = new MockENS();
        token = new MockERC20();
        karah = new Karah();
        konna = new Konna();
        karah.setENSRegistry(address(ens));
        konna.setKarah(address(karah));
        tester = msg.sender;
        for (uint i = 0; i < 4; i++) token.mint(address(this), 200_000 * 1e18);
    }

    function deployTesters() public payable {
        require(msg.sender == tester);
        require(msg.value == 5 ether);
        for (uint i = 0; i < 4; i++) {
            MockKarahTester t = new MockKarahTester(address(this));
            (bool s,) = address(t).call{value: 1 ether}("");
            require(s);
            testers[i] = t;
            token.transfer(address(t), 200_000 * 1e18);
        }
    }

    function addParticipants() public {
        require(msg.sender == tester);
        konna.transferOwnership(address(testers[1]));
        testers[1].proxyCall(address(konna), abi.encodeWithSignature("addMember(address)", address(testers[2])));
        testers[1].proxyCall(address(konna), abi.encodeWithSignature("addMember(address)", address(testers[3])));
    }

    function testMint() public {
        ens.register{value: 0.0001 ether}(NODE, address(testers[0]));
        require(ens.owner(NODE) == address(testers[0]));
    }

    function testTerms() public {
        testers[0].proxyCall(address(karah), abi.encodeWithSignature("createLease(bytes32,uint256,address)", NODE, UNIT_COST, address(token)));
        require(ens.owner(NODE) == address(karah));
    }

    function testLease() public {
        _approveAll();
        uint256 id = _proposeLease(7);
        _voteLease(id, true, 7e18);
        testers[2].proxyCall(address(konna), abi.encodeWithSignature("executeAcquisition(uint256)", id));
        (,address lessee,,uint256 daysLeft,,,,) = karah.getLeaseDetails(NODE);
        require(lessee == address(konna) && daysLeft == 7);
    }

    function testContentMod() public {
        uint256 id = _proposeChange(keccak256("sub"), address(0xBEEF), address(0xCAFE), 3600);
        _vote(id, true);
        testers[2].proxyCall(address(konna), abi.encodeWithSignature("executeChange(uint256)", id));
    }

    function testEarlyTermination() public {
        vm_warp(block.timestamp + 3 days);
        uint256 id = _proposeTermination();
        _vote(id, true);
        testers[2].proxyCall(address(konna), abi.encodeWithSignature("executeTermination(uint256)", id));
        (,address lessee,,,,,,) = karah.getLeaseDetails(NODE);
        require(lessee == address(0));
    }

    // **DEV NOTE**: Call `testLease` again to verify new lease after termination.

    function testRenew() public {
        uint256 id = _proposeLease(7);
        _voteLease(id, true, 7e18);
        testers[2].proxyCall(address(konna), abi.encodeWithSignature("executeAcquisition(uint256)", id));
        (, , , uint256 daysLeft, , , , ) = karah.getLeaseDetails(NODE);
        require(daysLeft == 14);
    }

    // Helpers
    function _approveAll() internal {
        for (uint i = 1; i < 4; i++) {
            testers[i].proxyCall(address(token), abi.encodeWithSignature("approve(address,uint256)", address(konna), type(uint256).max));
        }
    }

    function _proposeLease(uint256 durationDays) internal returns (uint256 id) {
        testers[2].proxyCall(
            address(konna),
            abi.encodeWithSignature(
                "proposeLease(bytes32,uint256,uint256)",
                NODE, durationDays, block.timestamp + 3 days
            )
        );
        return konna.proposalCount() - 1;
    }

    function _voteLease(uint256 id, bool favor, uint256 amt) internal {
        testers[2].proxyCall(address(konna), abi.encodeWithSignature("voteLease(uint256,bool,uint256)", id, favor, amt));
        testers[3].proxyCall(address(konna), abi.encodeWithSignature("voteLease(uint256,bool,uint256)", id, favor, amt));
    }

    function _proposeChange(bytes32 label, address sub, address res, uint64 ttl) internal returns (uint256 id) {
        testers[2].proxyCall(
            address(konna),
            abi.encodeWithSignature(
                "proposeChange(bytes32,bytes32,address,address,uint64,uint256)",
                NODE, label, sub, res, ttl, block.timestamp + 3 days
            )
        );
        return konna.proposalCount() - 1;
    }

    function _vote(uint256 id, bool favor) internal {
        testers[2].proxyCall(address(konna), abi.encodeWithSignature("vote(uint256,bool)", id, favor));
        testers[3].proxyCall(address(konna), abi.encodeWithSignature("vote(uint256,bool)", id, favor));
    }

    function _proposeTermination() internal returns (uint256 id) {
        testers[2].proxyCall(
            address(konna),
            abi.encodeWithSignature("proposeTermination(bytes32,uint256)", NODE, block.timestamp + 3 days)
        );
        return konna.proposalCount() - 1;
    }

    function vm_warp(uint256 ts) public {
        (bool s,) = address(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D).call(abi.encodeWithSignature("warp(uint256)", ts));
        require(s);
    }
}