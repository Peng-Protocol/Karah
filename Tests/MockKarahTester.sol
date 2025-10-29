// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

interface IIKarah {
    function createLease(bytes32 node, uint256 unitCost, address token) external;
    function updateLeaseTerms(bytes32 node, uint256 unitCost, address token) external;
    function subscribe(bytes32 node, uint256 durationDays) external;
    function renew(bytes32 node, uint256 renewalDays) external;
    function endLease(bytes32 node) external;
    function withdraw(bytes32 node, uint256 leaseId) external;
    function reclaimName(bytes32 node) external;
    function modifyContent(bytes32 node, bytes32 label, address subnodeOwner, address resolver, uint64 ttl) external;
}

contract MockKarahTester {
    address public owner;
    constructor(address _owner) { owner = _owner; }
    receive() external payable {}

    function proxyCall(address target, bytes memory data) external {
        require(msg.sender == owner, "Not owner");
        (bool s,) = target.call(data);
        require(s, "Proxy failed");
    }
}