// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// File Version: 0.0.2 (31/10/2025)
// Changelog:
// - 31/10/2025: Added revert data capture + ProxyError event.

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
    
    event ProxyError(string reason);

    function proxyCall(address target, bytes memory data) external {
        require(msg.sender == owner, "Not owner");
        (bool success, bytes memory returnData) = target.call(data);

        // If the call failed, bubble up the revert reason
        if (!success) {
            if (returnData.length > 0) {
                // Generically forward the revert message using assembly.
                // This will work for Error(string), CustomError(string), or any other revert.
                assembly {
                    revert(add(returnData, 0x20), mload(returnData))
                }
            } else {
                revert("Proxy failed (no revert data)"); // Fallback
            }
        }
    }
}