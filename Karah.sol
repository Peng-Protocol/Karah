// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// File Version: 0.0.1 (27/10/2025)
// Changelog:
// - 27/10/2025: Initial implementation of Karah lease contract with subscription, manual renewal, and refund logic.

interface IENS {
    function setOwner(bytes32 node, address owner) external;
    function setSubnodeOwner(bytes32 node, bytes32 label, address owner) external;
    function setRecord(bytes32 node, address owner, address resolver, uint64 ttl) external;
    function owner(bytes32 node) external view returns (address);
}

interface IERC20 {
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function decimals() external view returns (uint8);
    function balanceOf(address account) external view returns (uint256);
}

contract Karah {
    struct Lease {
        address lessor;
        address lessee;
        uint256 unitCost; // Cost per day in token (for this lease)
        uint256 totalDuration; // Total leased days
        address token; // Payment token (for this lease)
        uint256 currentUnitCost; // Updated cost for new/renewed leases
        address currentToken; // Updated token for new/renewed leases
        uint256 startTimestamp; // Lease start time
    }
    
    struct EndLeaseData {
    uint256 daysElapsed;
    uint256 daysLeft;
    uint256 refund;
    uint256 available;
}

    address public ensRegistry; // ENS registry address
    address public owner; // Contract owner
    mapping(bytes32 => Lease) public leases; // node => Lease
    uint256 public leaseCount; // Counter for active leases
    bytes32[] public leaseNodes; // Array for top-down view
    mapping(address => uint256) public withdrawable; // Lessor => withdrawable amount in tokens
    mapping(address => mapping(bytes32 => bool)) public lessorLeases; // Lessor => node => isActive
    mapping(address => mapping(bytes32 => bool)) public lesseeLeases; // Lessee => node => isActive
    bytes32[] public lessorNodes; // Lessor nodes array
    bytes32[] public lesseeNodes; // Lessee nodes array
    mapping(address => mapping(bytes32 => uint256)) public withdrawnPerLease; // Lessor => node => withdrawn amount
    mapping(bytes32 => uint256) public nodeToLeaseNodesIndex; // node => index in leaseNodes
    mapping(bytes32 => uint256) public nodeToLessorNodesIndex; // node => index in lessorNodes
    mapping(bytes32 => uint256) public nodeToLesseeNodesIndex; // node => index in lesseeNodes

    event Subscribed(bytes32 indexed node, address lessee, uint256 dayDuration);
    event Renewed(bytes32 indexed node, uint256 daysRenewed);
    event Ended(bytes32 indexed node, uint256 refunded);
    event TermsSet(bytes32 indexed node, uint256 unitCost, address token);

    receive() external payable {} // Allow ETH receipt for flexibility

    constructor() {
        owner = msg.sender;
        ensRegistry = 0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e; // Default ENS registry
    }

    function setENSRegistry(address newRegistry) external {
        require(msg.sender == owner, "Not owner");
        require(newRegistry != address(0), "Invalid address");
        ensRegistry = newRegistry;
    }

    function transferOwnership(address newOwner) external {
        require(msg.sender == owner, "Not owner");
        require(newOwner != address(0), "Invalid address");
        owner = newOwner;
    }

    function createLease(bytes32 node, uint256 unitCost, address token) external {
        // Creates a new lease for an ENS node
        require(IENS(ensRegistry).owner(node) == msg.sender, "Not ENS owner");
        require(leases[node].lessor == address(0), "Lease exists");
        require(unitCost > 0, "Invalid cost");
        require(token != address(0), "Invalid token");
        leases[node].lessor = msg.sender;
        leases[node].currentUnitCost = unitCost;
        leases[node].currentToken = token;
        IENS(ensRegistry).setOwner(node, address(this));
        emit TermsSet(node, unitCost, token);
    }

    function updateLeaseTerms(bytes32 node, uint256 unitCost, address token) external {
        // Updates lease terms for future subscriptions/renewals
        require(leases[node].lessor == msg.sender, "Not lessor");
        require(unitCost > 0, "Invalid cost");
        require(token != address(0), "Invalid token");
        leases[node].currentUnitCost = unitCost;
        leases[node].currentToken = token;
        emit TermsSet(node, unitCost, token);
    }

    function subscribe(bytes32 node, uint256 durationDays) external {
        // Subscribes to a lease, transferring tokens and setting lessee
        require(leases[node].currentToken != address(0), "No terms set");
        require(leases[node].lessee == address(0), "Already leased");
        require(durationDays > 0, "Invalid days");
        uint256 cost = durationDays * leases[node].currentUnitCost;
        uint8 decimals = IERC20(leases[node].currentToken).decimals();
        cost = cost * (10 ** uint256(decimals));
        uint256 balanceBefore = IERC20(leases[node].currentToken).balanceOf(address(this));
        require(IERC20(leases[node].currentToken).transferFrom(msg.sender, address(this), cost), "Transfer failed");
        uint256 balanceAfter = IERC20(leases[node].currentToken).balanceOf(address(this));
        require(balanceAfter - balanceBefore >= cost, "Insufficient transfer");
        withdrawable[leases[node].lessor] += cost;
        leases[node].lessee = msg.sender;
        leases[node].totalDuration = durationDays;
        leases[node].unitCost = leases[node].currentUnitCost;
        leases[node].token = leases[node].currentToken;
        leases[node].startTimestamp = block.timestamp;
        leaseNodes.push(node);
        nodeToLeaseNodesIndex[node] = leaseNodes.length - 1;
        lessorLeases[leases[node].lessor][node] = true;
        lesseeLeases[msg.sender][node] = true;
        lessorNodes.push(node);
        nodeToLessorNodesIndex[node] = lessorNodes.length - 1;
        lesseeNodes.push(node);
        nodeToLesseeNodesIndex[node] = lesseeNodes.length - 1;
        leaseCount++;
        IENS(ensRegistry).setOwner(node, address(this));
        emit Subscribed(node, msg.sender, durationDays);
    }

    function renew(bytes32 node, uint256 renewalDays) external {
        // Renews an existing lease, extending duration
        require(leases[node].lessee == msg.sender, "Not lessee");
        require(renewalDays > 0, "Invalid days");
        uint256 cost = renewalDays * leases[node].currentUnitCost;
        uint8 decimals = IERC20(leases[node].currentToken).decimals();
        cost = cost * (10 ** uint256(decimals));
        uint256 balanceBefore = IERC20(leases[node].currentToken).balanceOf(address(this));
        require(IERC20(leases[node].currentToken).transferFrom(msg.sender, address(this), cost), "Transfer failed");
        uint256 balanceAfter = IERC20(leases[node].currentToken).balanceOf(address(this));
        require(balanceAfter - balanceBefore >= cost, "Insufficient transfer");
        withdrawable[leases[node].lessor] += cost;
        leases[node].totalDuration += renewalDays;
        leases[node].unitCost = leases[node].currentUnitCost;
        leases[node].token = leases[node].currentToken;
        emit Renewed(node, renewalDays);
    }

//Helpers for endLease to reduce stack usage.
    function _calculateRefund(bytes32 node) private view returns (EndLeaseData memory) {
    // Calculates refund data for lease termination
    uint256 daysElapsed = (block.timestamp - leases[node].startTimestamp) / 1 days;
    uint256 daysLeft = leases[node].totalDuration > daysElapsed ? leases[node].totalDuration - daysElapsed : 0;
    uint256 refund = daysLeft * leases[node].unitCost;
    uint8 decimals = IERC20(leases[node].token).decimals();
    refund = refund * (10 ** uint256(decimals));
    uint256 available = withdrawable[leases[node].lessor] - withdrawnPerLease[leases[node].lessor][node];
    return EndLeaseData(daysElapsed, daysLeft, refund, available);
}

function _updateArrays(bytes32 node) private {
    // Performs O(1) swap-and-pop for all arrays
    uint256 leaseIndex = nodeToLeaseNodesIndex[node];
    bytes32 lastLeaseNode = leaseNodes[leaseNodes.length - 1];
    leaseNodes[leaseIndex] = lastLeaseNode;
    nodeToLeaseNodesIndex[lastLeaseNode] = leaseIndex;
    leaseNodes.pop();
    delete nodeToLeaseNodesIndex[node];

    uint256 lessorIndex = nodeToLessorNodesIndex[node];
    bytes32 lastLessorNode = lessorNodes[lessorNodes.length - 1];
    lessorNodes[lessorIndex] = lastLessorNode;
    nodeToLessorNodesIndex[lastLessorNode] = lessorIndex;
    lessorNodes.pop();
    delete nodeToLessorNodesIndex[node];

    uint256 lesseeIndex = nodeToLesseeNodesIndex[node];
    bytes32 lastLesseeNode = lesseeNodes[lesseeNodes.length - 1];
    lesseeNodes[lesseeIndex] = lastLesseeNode;
    nodeToLesseeNodesIndex[lastLesseeNode] = lesseeIndex;
    lesseeNodes.pop();
    delete nodeToLesseeNodesIndex[node];
}

function _updateLeaseState(bytes32 node, uint256 refund) private {
    // Updates lease state and processes refund
    withdrawable[leases[node].lessor] -= refund;
    leases[node].lessee = address(0);
    leases[node].totalDuration = 0;
    lessorLeases[leases[node].lessor][node] = false;
    lesseeLeases[msg.sender][node] = false;
    leaseCount--;
    IENS(ensRegistry).setOwner(node, leases[node].lessor);
    if (refund > 0) {
        require(IERC20(leases[node].token).transfer(msg.sender, refund), "Refund failed");
    }
}

function endLease(bytes32 node) external {
    // Changelog: 27/10/2025: Refactored into helpers to fix stack-too-deep error.
    // Ends a lease, refunds unused days, and returns ENS ownership
    require(leases[node].lessee == msg.sender, "Not lessee");
    EndLeaseData memory data = _calculateRefund(node);
    require(data.refund <= data.available, "Insufficient withdrawable");
    _updateArrays(node);
    _updateLeaseState(node, data.refund);
    emit Ended(node, data.refund);
}

    function reclaimName(bytes32 node) external {
        // Changelog: 27/10/2025: Replaced O(n) loop with O(1) swap-and-pop using index mappings.
        // Allows lessor to reclaim ENS name, ending lease if active
        require(leases[node].lessor == msg.sender, "Not lessor");
        if (leases[node].lessee != address(0)) {
            uint256 daysElapsed = (block.timestamp - leases[node].startTimestamp) / 1 days;
            uint256 daysLeft = leases[node].totalDuration > daysElapsed ? leases[node].totalDuration - daysElapsed : 0;
            uint256 refund = daysLeft * leases[node].unitCost;
            uint8 decimals = IERC20(leases[node].token).decimals();
            refund = refund * (10 ** uint256(decimals));
            uint256 available = withdrawable[leases[node].lessor] - withdrawnPerLease[leases[node].lessor][node];
            require(refund <= available, "Insufficient withdrawable");
            withdrawable[leases[node].lessor] -= refund;
            leases[node].lessee = address(0);
            leases[node].totalDuration = 0;
            lessorLeases[leases[node].lessor][node] = false;
            lesseeLeases[leases[node].lessee][node] = false;
            // Swap-and-pop for leaseNodes
            uint256 leaseIndex = nodeToLeaseNodesIndex[node];
            bytes32 lastLeaseNode = leaseNodes[leaseNodes.length - 1];
            leaseNodes[leaseIndex] = lastLeaseNode;
            nodeToLeaseNodesIndex[lastLeaseNode] = leaseIndex;
            leaseNodes.pop();
            delete nodeToLeaseNodesIndex[node];
            // Swap-and-pop for lessorNodes
            uint256 lessorIndex = nodeToLessorNodesIndex[node];
            bytes32 lastLessorNode = lessorNodes[lessorNodes.length - 1];
            lessorNodes[lessorIndex] = lastLessorNode;
            nodeToLessorNodesIndex[lastLessorNode] = lessorIndex;
            lessorNodes.pop();
            delete nodeToLessorNodesIndex[node];
            // Swap-and-pop for lesseeNodes
            uint256 lesseeIndex = nodeToLesseeNodesIndex[node];
            bytes32 lastLesseeNode = lesseeNodes[lesseeNodes.length - 1];
            lesseeNodes[lesseeIndex] = lastLesseeNode;
            nodeToLesseeNodesIndex[lastLesseeNode] = lesseeIndex;
            lesseeNodes.pop();
            delete nodeToLesseeNodesIndex[node];
            leaseCount--;
            emit Ended(node, refund);
            if (refund > 0) {
                require(IERC20(leases[node].token).transfer(leases[node].lessee, refund), "Refund failed");
            }
        }
        IENS(ensRegistry).setOwner(node, msg.sender);
    }

    function withdraw(bytes32 node) external {
        // Changelog: 27/10/2025: Removed withdrawable subtraction to fix accounting flaw.
        // Allows lessor to withdraw earned tokens
        require(leases[node].lessor == msg.sender, "Not lessor");
        require(leases[node].lessee != address(0), "No active lease");
        uint256 daysElapsed = (block.timestamp - leases[node].startTimestamp) / 1 days;
        uint256 amount = daysElapsed * leases[node].unitCost;
        uint8 decimals = IERC20(leases[node].token).decimals();
        amount = amount * (10 ** uint256(decimals));
        uint256 available = withdrawable[msg.sender] - withdrawnPerLease[msg.sender][node];
        require(amount <= available, "Insufficient withdrawable");
        withdrawnPerLease[msg.sender][node] += amount;
        require(IERC20(leases[node].token).transfer(msg.sender, amount), "Transfer failed");
    }

    function modifyContent(bytes32 node, bytes32 label, address subnodeOwner, address resolver, uint64 ttl) external {
        // Allows lessee to modify ENS records if lease is active
        require(leases[node].lessee == msg.sender, "Not lessee");
        uint256 daysElapsed = (block.timestamp - leases[node].startTimestamp) / 1 days;
        uint256 daysLeft = leases[node].totalDuration > daysElapsed ? leases[node].totalDuration - daysElapsed : 0;
        require(daysLeft > 0, "Lease expired");
        if (label != bytes32(0)) {
            IENS(ensRegistry).setSubnodeOwner(node, label, subnodeOwner);
        }
        IENS(ensRegistry).setRecord(node, address(this), resolver, ttl);
    }

    function viewLeases(uint256 maxIterations) external view returns (bytes32[] memory nodes, uint256 count) {
        // Returns active lease nodes in top-down order
        uint256 length = leaseCount < maxIterations ? leaseCount : maxIterations;
        nodes = new bytes32[](length);
        for (uint256 i = 0; i < length; i++) {
            nodes[i] = leaseNodes[leaseCount - 1 - i];
        }
        count = leaseCount;
    }

    function getAllLessorLeases(address lessor, uint256 maxIterations) external view returns (bytes32[] memory nodes, uint256 count) {
        // Returns active leases for a lessor
        uint256 length = lessorNodes.length < maxIterations ? lessorNodes.length : maxIterations;
        bytes32[] memory temp = new bytes32[](length);
        uint256 index = 0;
        for (uint256 i = 0; i < length; i++) {
            bytes32 node = lessorNodes[lessorNodes.length - 1 - i];
            if (lessorLeases[lessor][node] && leases[node].lessee != address(0)) {
                temp[index] = node;
                index++;
            }
        }
        nodes = new bytes32[](index);
        for (uint256 i = 0; i < index; i++) nodes[i] = temp[i];
        count = index;
    }

    function getAllLesseeLeases(address lessee, uint256 maxIterations) external view returns (bytes32[] memory nodes, uint256 count) {
        // Returns active leases for a lessee
        uint256 length = lesseeNodes.length < maxIterations ? lesseeNodes.length : maxIterations;
        bytes32[] memory temp = new bytes32[](length);
        uint256 index = 0;
        for (uint256 i = 0; i < length; i++) {
            bytes32 node = lesseeNodes[lesseeNodes.length - 1 - i];
            if (lesseeLeases[lessee][node]) {
                temp[index] = node;
                index++;
            }
        }
        nodes = new bytes32[](index);
        for (uint256 i = 0; i < index; i++) nodes[i] = temp[i];
        count = index;
    }

    function getLeaseDetails(bytes32 node) external view returns (address lessor, address lessee, uint256 unitCost, uint256 daysLeft, address token, uint256 currentUnitCost, address currentToken) {
        // Returns details of a specific lease
        Lease memory lease = leases[node];
        uint256 daysElapsed = lease.startTimestamp == 0 ? 0 : (block.timestamp - lease.startTimestamp) / 1 days;
        daysLeft = lease.totalDuration > daysElapsed ? lease.totalDuration - daysElapsed : 0;
        return (lease.lessor, lease.lessee, lease.unitCost, daysLeft, lease.token, lease.currentUnitCost, lease.currentToken);
    }

    function getActiveLeasesCount() external view returns (uint256 count) {
        // Returns total active leases
        return leaseCount;
    }
}