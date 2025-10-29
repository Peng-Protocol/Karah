// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

/**
 * @dev Minimal ENS registry – just enough for the test suite.
 *      Names can be “registered” for 0.0001 ETH.
 */
contract MockENS {
    mapping(bytes32 => address) public owners;
    uint256 public constant REGISTRATION_COST = 0.0001 ether;

    function register(bytes32 node, address registrant) external payable {
        require(msg.value >= REGISTRATION_COST, "Insufficient ETH");
        owners[node] = registrant;
    }
    function setOwner(bytes32 node, address owner) external { owners[node] = owner; }
    function setSubnodeOwner(bytes32, bytes32, address) external {}
    function setRecord(bytes32, address, address, uint64) external {}
    function owner(bytes32 node) external view returns (address) { return owners[node]; }
}