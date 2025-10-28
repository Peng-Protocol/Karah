// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// File Version: 0.0.5 (28/10/2025)
// Changelog:
// - 27/10/2025: Initial implementation.
// - 28/10/2025: Per-lease-agreement refactor.
// - 28/10/2025: Removed global withdrawable. Added per-agreement withdrawableAmount.
//   withdraw(node, leaseId) now safe, accurate, and isolated.
// - 28/10/2025: Fixed underflow in modifyContent; added getAgreementDetails.
// - Documented: withdraw at startTimestamp returns 0 (correct); renewal uses current terms.

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
    function approve(address spender, uint256 amount) external returns (bool);
}

contract Karah {
    struct Lease {
        address lessor;
        uint256 currentUnitCost;
        address currentToken;
        uint256 agreementCount;
        bool active;
    }

    struct LeaseAgreement {
        address lessee;
        uint256 unitCost;
        address token;
        uint256 totalDuration;
        uint256 startTimestamp;
        uint256 daysWithdrawn;
        uint256 withdrawableAmount;
        bool ended;
    }

    struct EndLeaseData {
        uint256 daysElapsed;
        uint256 daysLeft;
        uint256 refund;
        uint256 available;
    }

    address public ensRegistry;
    address public owner;
    mapping(bytes32 => Lease) public leases;
    mapping(bytes32 => mapping(uint256 => LeaseAgreement)) public agreements;
    uint256 public leaseCount;
    bytes32[] public leaseNodes;
    mapping(address => mapping(bytes32 => bool)) public lessorLeases;
    mapping(address => mapping(bytes32 => bool)) public lesseeLeases;
    bytes32[] public lessorNodes;
    bytes32[] public lesseeNodes;
    mapping(bytes32 => uint256) public nodeToLeaseNodesIndex;
    mapping(bytes32 => uint256) public nodeToLessorNodesIndex;
    mapping(bytes32 => uint256) public nodeToLesseeNodesIndex;

    event Subscribed(bytes32 indexed node, address lessee, uint256 dayDuration, uint256 leaseId);
    event Renewed(bytes32 indexed node, uint256 daysRenewed, uint256 leaseId);
    event Ended(bytes32 indexed node, uint256 refunded, uint256 leaseId);
    event TermsSet(bytes32 indexed node, uint256 unitCost, address token);
    event Withdrawn(bytes32 indexed node, uint256 leaseId, uint256 amount);

    receive() external payable {}

    constructor() {
        owner = msg.sender;
        ensRegistry = 0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e;
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
        require(IENS(ensRegistry).owner(node) == msg.sender, "Not ENS owner");
        require(leases[node].lessor == address(0), "Lease exists");
        require(unitCost > 0, "Invalid cost");
        require(token != address(0), "Invalid token");
        leases[node] = Lease(msg.sender, unitCost, token, 0, false);
        IENS(ensRegistry).setOwner(node, address(this));
        emit TermsSet(node, unitCost, token);
    }

// Lessor should not change token during active lease, withdraw will use latest token only.
    function updateLeaseTerms(bytes32 node, uint256 unitCost, address token) external {
        require(leases[node].lessor == msg.sender, "Not lessor");
        require(unitCost > 0, "Invalid cost");
        require(token != address(0), "Invalid token");
        leases[node].currentUnitCost = unitCost;
        leases[node].currentToken = token;
        emit TermsSet(node, unitCost, token);
    }

    function subscribe(bytes32 node, uint256 durationDays) external {
        Lease storage l = leases[node];
        require(l.currentToken != address(0), "No terms set");
        require(!l.active, "Already leased");
        require(durationDays > 0, "Invalid days");

        uint256 cost = durationDays * l.currentUnitCost;
        uint8 dec = IERC20(l.currentToken).decimals();
        cost = cost * (10 ** uint256(dec));

        uint256 balBefore = IERC20(l.currentToken).balanceOf(address(this));
        require(IERC20(l.currentToken).transferFrom(msg.sender, address(this), cost), "Transfer failed");
        require(IERC20(l.currentToken).balanceOf(address(this)) - balBefore >= cost, "Insufficient transfer");

        uint256 leaseId = l.agreementCount++;
        agreements[node][leaseId] = LeaseAgreement(
            msg.sender,
            l.currentUnitCost,
            l.currentToken,
            durationDays,
            block.timestamp,
            0,
            cost,
            false
        );

        l.active = true;
        _updateActiveArrays(node, true);

        emit Subscribed(node, msg.sender, durationDays, leaseId);
    }

    function renew(bytes32 node, uint256 renewalDays) external {
        Lease storage l = leases[node];
        uint256 leaseId = l.agreementCount - 1;
        LeaseAgreement storage a = agreements[node][leaseId];
        require(a.lessee == msg.sender, "Not lessee");
        require(renewalDays > 0, "Invalid days");

        uint256 cost = renewalDays * l.currentUnitCost;
        uint8 dec = IERC20(l.currentToken).decimals();
        cost = cost * (10 ** uint256(dec));

        uint256 balBefore = IERC20(l.currentToken).balanceOf(address(this));
        require(IERC20(l.currentToken).transferFrom(msg.sender, address(this), cost), "Transfer failed");
        require(IERC20(l.currentToken).balanceOf(address(this)) - balBefore >= cost, "Insufficient transfer");

        a.withdrawableAmount += cost;
        a.totalDuration += renewalDays;
        a.unitCost = l.currentUnitCost;
        a.token = l.currentToken;

        emit Renewed(node, renewalDays, leaseId);
    }

    function _calculateRefund(bytes32 node, uint256 leaseId) private view returns (EndLeaseData memory) {
        LeaseAgreement storage a = agreements[node][leaseId];
        uint256 daysElapsed = (block.timestamp - a.startTimestamp) / 1 days;
        uint256 daysLeft = a.totalDuration > daysElapsed ? a.totalDuration - daysElapsed : 0;
        uint256 refund = daysLeft * a.unitCost;
        uint8 dec = IERC20(a.token).decimals();
        refund = refund * (10 ** uint256(dec));
        return EndLeaseData(daysElapsed, daysLeft, refund, a.withdrawableAmount);
    }

    function endLease(bytes32 node) external {
        Lease storage l = leases[node];
        uint256 leaseId = l.agreementCount - 1;
        LeaseAgreement storage a = agreements[node][leaseId];
        require(a.lessee == msg.sender, "Not lessee");

        EndLeaseData memory d = _calculateRefund(node, leaseId);
        require(d.refund <= d.available, "Insufficient funds");

        a.withdrawableAmount -= d.refund;
        a.ended = true;
        l.active = false;
        _updateActiveArrays(node, false);
        leaseCount--;

        if (d.refund > 0) {
            require(IERC20(a.token).transfer(msg.sender, d.refund), "Refund failed");
        }
        emit Ended(node, d.refund, leaseId);
    }

    function reclaimName(bytes32 node) external {
        Lease storage l = leases[node];
        require(l.lessor == msg.sender, "Not lessor");
        if (l.active) {
            uint256 leaseId = l.agreementCount - 1;
            LeaseAgreement storage a = agreements[node][leaseId];
            EndLeaseData memory d = _calculateRefund(node, leaseId);
            require(d.refund <= d.available, "Insufficient funds");
            a.withdrawableAmount -= d.refund;
            a.ended = true;
            l.active = false;
            _updateActiveArrays(node, false);
            leaseCount--;
            if (d.refund > 0) {
                require(IERC20(a.token).transfer(a.lessee, d.refund), "Refund failed");
            }
            emit Ended(node, d.refund, leaseId);
        }
        IENS(ensRegistry).setOwner(node, msg.sender);
    }

    function withdraw(bytes32 node, uint256 leaseId) external {
        Lease storage l = leases[node];
        require(l.lessor == msg.sender, "Not lessor");
        require(leaseId < l.agreementCount, "Invalid leaseId");
        LeaseAgreement storage a = agreements[node][leaseId];

        uint256 daysElapsed = a.ended ? a.totalDuration : (block.timestamp - a.startTimestamp) / 1 days;
        uint256 newDays = daysElapsed > a.daysWithdrawn ? daysElapsed - a.daysWithdrawn : 0;
        require(newDays > 0, "Nothing to withdraw"); // 0 if called at startTimestamp

        uint256 amount = newDays * a.unitCost * (10 ** uint256(IERC20(a.token).decimals()));
        require(amount <= a.withdrawableAmount, "Insufficient funds");

        a.daysWithdrawn += newDays;
        a.withdrawableAmount -= amount;
        require(IERC20(a.token).transfer(msg.sender, amount), "Transfer failed");
        emit Withdrawn(node, leaseId, amount);
    }

    function modifyContent(bytes32 node, bytes32 label, address subnodeOwner, address resolver, uint64 ttl) external {
        Lease storage l = leases[node];
        require(l.active, "No active lease");
        uint256 leaseId = l.agreementCount - 1;
        LeaseAgreement storage a = agreements[node][leaseId];
        require(a.lessee == msg.sender, "Not lessee");

        uint256 daysElapsed = (block.timestamp - a.startTimestamp) / 1 days;
        require(daysElapsed < a.totalDuration, "Lease expired");

        if (label != bytes32(0)) {
            IENS(ensRegistry).setSubnodeOwner(node, label, subnodeOwner);
        }
        IENS(ensRegistry).setRecord(node, address(this), resolver, ttl);
    }

    function _updateActiveArrays(bytes32 node, bool add) private {
        if (add) {
            leaseNodes.push(node);
            nodeToLeaseNodesIndex[node] = leaseNodes.length - 1;
            lessorLeases[leases[node].lessor][node] = true;
            lesseeLeases[agreements[node][leases[node].agreementCount - 1].lessee][node] = true;
            lessorNodes.push(node);
            nodeToLessorNodesIndex[node] = lessorNodes.length - 1;
            lesseeNodes.push(node);
            nodeToLesseeNodesIndex[node] = lesseeNodes.length - 1;
            leaseCount++;
        } else {
            uint256 idx = nodeToLeaseNodesIndex[node];
            bytes32 last = leaseNodes[leaseNodes.length - 1];
            leaseNodes[idx] = last;
            nodeToLeaseNodesIndex[last] = idx;
            leaseNodes.pop();
            delete nodeToLeaseNodesIndex[node];

            idx = nodeToLessorNodesIndex[node];
            last = lessorNodes[lessorNodes.length - 1];
            lessorNodes[idx] = last;
            nodeToLessorNodesIndex[last] = idx;
            lessorNodes.pop();
            delete nodeToLessorNodesIndex[node];

            idx = nodeToLesseeNodesIndex[node];
            last = lesseeNodes[lesseeNodes.length - 1];
            lesseeNodes[idx] = last;
            nodeToLesseeNodesIndex[last] = idx;
            lesseeNodes.pop();
            delete nodeToLesseeNodesIndex[node];

            lessorLeases[leases[node].lessor][node] = false;
            lesseeLeases[agreements[node][leases[node].agreementCount - 1].lessee][node] = false;
        }
    }

    // --- Views ---
    function viewLeases(uint256 maxIterations) external view returns (bytes32[] memory nodes, uint256 count) {
        uint256 len = leaseCount < maxIterations ? leaseCount : maxIterations;
        nodes = new bytes32[](len);
        for (uint256 i = 0; i < len; i++) nodes[i] = leaseNodes[leaseCount - 1 - i];
        count = leaseCount;
    }

    function getAllLessorLeases(address lessor, uint256 maxIterations) external view returns (bytes32[] memory nodes, uint256 count) {
        uint256 len = lessorNodes.length < maxIterations ? lessorNodes.length : maxIterations;
        bytes32[] memory temp = new bytes32[](len);
        uint256 idx = 0;
        for (uint256 i = 0; i < len; i++) {
            bytes32 n = lessorNodes[lessorNodes.length - 1 - i];
            if (lessorLeases[lessor][n] && leases[n].active) temp[idx++] = n;
        }
        nodes = new bytes32[](idx);
        for (uint256 i = 0; i < idx; i++) nodes[i] = temp[i];
        count = idx;
    }

    function getAllLesseeLeases(address lessee, uint256 maxIterations) external view returns (bytes32[] memory nodes, uint256 count) {
        uint256 len = lesseeNodes.length < maxIterations ? lesseeNodes.length : maxIterations;
        bytes32[] memory temp = new bytes32[](len);
        uint256 idx = 0;
        for (uint256 i = 0; i < len; i++) {
            bytes32 n = lesseeNodes[lesseeNodes.length - 1 - i];
            if (lesseeLeases[lessee][n]) temp[idx++] = n;
        }
        nodes = new bytes32[](idx);
        for (uint256 i = 0; i < idx; i++) nodes[i] = temp[i];
        count = idx;
    }

    function getLeaseDetails(bytes32 node) external view returns (
        address lessor, address lessee, uint256 unitCost, uint256 daysLeft,
        address token, uint256 currentUnitCost, address currentToken, uint256 leaseId
    ) {
        Lease storage l = leases[node];
        uint256 id = l.active ? l.agreementCount - 1 : type(uint256).max;
        LeaseAgreement memory a;
        if (l.active) a = agreements[node][id];
        uint256 elapsed = l.active ? (block.timestamp - a.startTimestamp) / 1 days : 0;
        daysLeft = l.active && a.totalDuration > elapsed ? a.totalDuration - elapsed : 0;
        return (
            l.lessor,
            l.active ? a.lessee : address(0),
            l.active ? a.unitCost : 0,
            daysLeft,
            l.active ? a.token : address(0),
            l.currentUnitCost,
            l.currentToken,
            l.active ? id : 0
        );
    }

    function getAgreementDetails(bytes32 node, uint256 leaseId) external view returns (LeaseAgreement memory) {
        require(leaseId < leases[node].agreementCount, "Invalid leaseId");
        return agreements[node][leaseId];
    }

    function getAgreementCount(bytes32 node) external view returns (uint256) {
        return leases[node].agreementCount;
    }

    function getActiveLeasesCount() external view returns (uint256) {
        return leaseCount;
    }
}