// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// File Version: 0.0.7 (02/11/2025)
// Changelog:
// - 02/11/2035: Added renewal functions.
// - 02/11/2025: Fixed proposeLease lease details fetch. 
// - 31/10/2025: Fixed scaling error in proposeLease 
// - 31/10/2025: Fixed _now() infinite recursion bug
// - 31/10/2025: Added time warp system: currentTime, isWarped, warp(), unWarp(), _now().
// - 27/10/2025: Initial implementation of DAO for collective ENS name management.
// - 28/10/2025: Added lease acquisition & termination via DAO proposals.
// - Added contribution tracking, capped funding, proportional refund logic.
// - Add ERC20 approval in acquisition . 


interface IKarah {
    function modifyContent(bytes32 node, bytes32 label, address owner, address resolver, uint64 ttl) external;
    function getLeaseDetails(bytes32 node) external view returns (address lessor, address lessee, uint256 unitCost, uint256 daysLeft, address token, uint256 currentUnitCost, address currentToken);
    function subscribe(bytes32 node, uint256 durationDays) external;
    function endLease(bytes32 node) external;
    function renew(bytes32 node, uint256 renewalDays) external;
}

interface IERC20b {
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint256); // Added for OMFAgent prepListing
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
}

contract Konna {
    struct Proposal {
    address proposer;
    bytes32 node;
    bytes32 label;
    address subnodeOwner; // Subnode owner for proposal
    address resolver;
    uint64 ttl;
    uint256 votesFor;
    uint256 expiry;
    bool executed;
}

struct LeaseProposal {
    uint256 totalNeeded;   // Full subscription cost
    uint256 collected;     // ERC20 collected so far
    address token;         // Lease payment token
    uint256 durationDays;  // Lease duration
}

    mapping(uint256 Index => Proposal) public proposals; // Proposal ID => Proposal
    mapping(uint256 Index => mapping(address => bool)) public voted; // Proposal ID => Voter => Voted
    uint256 public proposalCount; // Counter for proposals
    address[] public members; // DAO members
    uint256 public constant MIN_EXPIRY = 1 weeks;
    uint256 public constant MAX_EXPIRY = 26 weeks;

address public karah; // Karah contract address
address public owner; // Contract owner

mapping(uint256 => LeaseProposal) public leaseProps; // id => LeaseProposal
mapping(uint256 => mapping(address => uint256)) public contributions; // id => voter => amount

uint256 public currentTime;
bool public isWarped;

    event ProposalCreated(uint256 indexed id, address proposer, bytes32 node, uint256 expiry);
    event Voted(uint256 indexed id, address voter, bool inFavor);
    event ProposalExecuted(uint256 indexed id, bytes32 node);

    receive() external payable {} // Allow ETH receipt

constructor() {
    owner = msg.sender;
}

function warp(uint256 newTimestamp) external {
    require(msg.sender == owner, "Not owner");
    currentTime = newTimestamp;
    isWarped = true;
}

function unWarp() external {
    require(msg.sender == owner, "Not owner");
    isWarped = false;
    currentTime = _now();
}

function _now() internal view returns (uint256) {
    return isWarped ? currentTime : block.timestamp;
}

function setKarah(address newKarah) external {
    require(msg.sender == owner, "Not owner");
    require(newKarah != address(0), "Invalid address");
    karah = newKarah;
}

function transferOwnership(address newOwner) external {
    require(msg.sender == owner, "Not owner");
    require(newOwner != address(0), "Invalid address");
    owner = newOwner;
}

    // Add member to DAO
    function addMember(address member) external {
    require(msg.sender == owner, "Not owner");
    require(member != address(0), "Invalid member");
    members.push(member);
}

function removeMember(address member) external {
    require(msg.sender == owner, "Not owner");
    for (uint256 i = 0; i < members.length; i++) {
        if (members[i] == member) {
            members[i] = members[members.length - 1];
            members.pop();
            return;
        }
    }
    revert("Member not found");
}

    // Create proposal for name/subname change
    function proposeChange(bytes32 node, bytes32 label, address subnodeOwner, address resolver, uint64 ttl, uint256 expiry) external {
    require(expiry >= _now() + MIN_EXPIRY && expiry <= _now() + MAX_EXPIRY, "Invalid expiry");
    for (uint256 i = 0; i < members.length; i++) {
        if (members[i] == msg.sender) {
            proposals[proposalCount] = Proposal(msg.sender, node, label, subnodeOwner, resolver, ttl, 0, expiry, false);
            emit ProposalCreated(proposalCount, msg.sender, node, expiry);
            proposalCount++;
            return;
        }
    }
    revert("Not a member");
}

    // Vote on a proposal
    function vote(uint256 id, bool inFavor) external {
        require(!proposals[id].executed, "Already executed");
        require(_now() < proposals[id].expiry, "Proposal expired");
        require(!voted[id][msg.sender], "Already voted");
        for (uint256 i = 0; i < members.length; i++) {
            if (members[i] == msg.sender) {
                voted[id][msg.sender] = true;
                if (inFavor) proposals[id].votesFor++;
                emit Voted(id, msg.sender, inFavor);
                return;
            }
        }
        revert("Not a member");
    }

    // Execute approved proposal
    function executeChange(uint256 id) external {
    Proposal storage p = proposals[id];
    require(!p.executed, "Already executed");
    require(_now() < p.expiry, "Proposal expired");
    require(p.votesFor > members.length / 2, "Insufficient votes");
    p.executed = true;
    IKarah(karah).modifyContent(p.node, p.label, p.subnodeOwner, p.resolver, p.ttl);
    emit ProposalExecuted(id, p.node);
}

    // View proposals (top-down)
    function viewProposals(uint256 maxIterations) external view returns (uint256[] memory ids, uint256 count) {
        uint256 length = proposalCount < maxIterations ? proposalCount : maxIterations;
        ids = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            ids[i] = proposalCount - 1 - i;
        }
        count = proposalCount;
    }
    
    // New Helpers (0.0.2) 
    
    function isMember(address who) private view returns (bool) {
    for (uint256 i = 0; i < members.length; i++) if (members[i] == who) return true;
    return false;
}

function _voteBasic(uint256 id, bool inFavor) private {
    Proposal storage p = proposals[id];
    require(!p.executed && _now() < p.expiry, "Invalid");
    require(isMember(msg.sender), "Not member");
    require(!voted[id][msg.sender], "Voted");
    voted[id][msg.sender] = true;
    if (inFavor) p.votesFor++;
    emit Voted(id, msg.sender, inFavor);
}

function _refundContributions(uint256 id, uint256 totalRefund) private {
    LeaseProposal memory lp = leaseProps[id];
    if (totalRefund == 0 || lp.collected == 0) return;
    for (uint256 i = 0; i < members.length; i++) {
        address v = members[i];
        uint256 contrib = contributions[id][v];
        if (contrib > 0) {
            uint256 share = contrib * totalRefund / lp.collected;
            if (share > 0) IERC20b(lp.token).transfer(v, share);
            delete contributions[id][v];
        }
    }
}
   
  // --- Acquisition ---
  function proposeLease(bytes32 node, uint256 durationDays, uint256 expiry) external {
        require(isMember(msg.sender), "Not member");
        require(expiry >= _now() + MIN_EXPIRY && expiry <= _now() + MAX_EXPIRY, "Bad expiry");
        ( , , , , , uint256 currentUnitCost, address token) = IKarah(karah).getLeaseDetails(node);
        require(token != address(0), "No terms");
        uint256 total = durationDays * currentUnitCost;  // unitCost is pre-scaled, no decimals multiplication

        uint256 id = proposalCount++;
        proposals[id] = Proposal(msg.sender, node, bytes32(0), address(0), address(0), 0, 0, expiry, false);
        leaseProps[id] = LeaseProposal(total, 0, token, durationDays);
        emit ProposalCreated(id, msg.sender, node, expiry);
    }

function voteLease(uint256 id, bool inFavor, uint256 amount) external {
    Proposal storage p = proposals[id];
    require(!p.executed && _now() < p.expiry, "Invalid state");
    require(isMember(msg.sender), "Not member");
    require(!voted[id][msg.sender], "Voted");

    LeaseProposal storage lp = leaseProps[id];
    uint256 stillNeeded = lp.totalNeeded > lp.collected ? lp.totalNeeded - lp.collected : 0;
    uint256 pull = amount > stillNeeded ? stillNeeded : amount;
    if (pull > 0) {
        uint256 balBefore = IERC20b(lp.token).balanceOf(address(this));
        require(IERC20b(lp.token).transferFrom(msg.sender, address(this), pull), "Xfer fail");
        require(IERC20b(lp.token).balanceOf(address(this)) - balBefore >= pull, "Low xfer");
        lp.collected += pull;
        contributions[id][msg.sender] = pull;
    }
    voted[id][msg.sender] = true;
    if (inFavor) p.votesFor++;
    emit Voted(id, msg.sender, inFavor);
}

function executeAcquisition(uint256 id) external {
    Proposal storage p = proposals[id];
    require(!p.executed && _now() < p.expiry, "Invalid");
    require(p.votesFor > members.length / 2, "No quorum");
    LeaseProposal memory lp = leaseProps[id];
    require(lp.collected >= lp.totalNeeded, "Underfunded");
    p.executed = true;

    // Approve Karah to pull funds
    require(IERC20b(lp.token).approve(karah, lp.totalNeeded), "Approve fail");

    // Karah pulls via transferFrom
    IKarah(karah).subscribe(p.node, lp.durationDays);

    emit ProposalExecuted(id, p.node);
}

function cancelStaleAcquisition(uint256 id) external {
    Proposal storage p = proposals[id];
    require(!p.executed && _now() >= p.expiry, "Not stale");
    p.executed = true;
    _refundContributions(id, leaseProps[id].collected);
    emit ProposalExecuted(id, p.node); // reuse event
}

// --- Termination ---

function proposeTermination(bytes32 node, uint256 expiry) external {
    require(isMember(msg.sender), "Not member");
    ( , address lessee, , , , , ) = IKarah(karah).getLeaseDetails(node);
    require(lessee == address(this), "Not leased");
    uint256 id = proposalCount++;
    proposals[id] = Proposal(msg.sender, node, bytes32(0), address(0), address(0), 0, 0, expiry, false);
    emit ProposalCreated(id, msg.sender, node, expiry);
}

function voteTermination(uint256 id, bool inFavor) external {
    _voteBasic(id, inFavor); // reuses vote logic, no extra funds
}

function executeTermination(uint256 id) external {
    Proposal storage p = proposals[id];
    require(!p.executed && _now() < p.expiry, "Invalid");
    require(p.votesFor > members.length / 2, "No quorum");

    ( , , , , address token, , ) = IKarah(karah).getLeaseDetails(p.node);
    uint256 balBefore = IERC20b(token).balanceOf(address(this));

    p.executed = true;
    IKarah(karah).endLease(p.node);

    uint256 balAfter = IERC20b(token).balanceOf(address(this));
    uint256 refund = balAfter - balBefore;

    _refundContributions(id, refund);
    emit ProposalExecuted(id, p.node);
}

// --- Renewal ---

function proposeRenewal(bytes32 node, uint256 durationDays, uint256 expiry) external {
    require(isMember(msg.sender), "Not member");
    require(expiry >= _now() + MIN_EXPIRY && expiry <= _now() + MAX_EXPIRY, "Bad expiry");
    
    // Verify we currently lease this node
    (, address lessee, , , , , ) = IKarah(karah).getLeaseDetails(node);
    require(lessee == address(this), "Not current lessee");
    
    // Get current token for payment
    (, , , , address token, , ) = IKarah(karah).getLeaseDetails(node);
    (, , , , , uint256 currentUnitCost, ) = IKarah(karah).getLeaseDetails(node);
    require(token != address(0), "No active lease");
    
    uint256 total = durationDays * currentUnitCost;

    uint256 id = proposalCount++;
    proposals[id] = Proposal(msg.sender, node, bytes32(0), address(0), address(0), 0, 0, expiry, false);
    leaseProps[id] = LeaseProposal(total, 0, token, durationDays);
    emit ProposalCreated(id, msg.sender, node, expiry);
}

function voteRenewal(uint256 id, bool inFavor, uint256 amount) external {
    Proposal storage p = proposals[id];
    require(!p.executed && _now() < p.expiry, "Invalid state");
    require(isMember(msg.sender), "Not member");
    require(!voted[id][msg.sender], "Voted");

    LeaseProposal storage lp = leaseProps[id];
    uint256 stillNeeded = lp.totalNeeded > lp.collected ? lp.totalNeeded - lp.collected : 0;
    uint256 pull = amount > stillNeeded ? stillNeeded : amount;
    
    if (pull > 0) {
        uint256 balBefore = IERC20b(lp.token).balanceOf(address(this));
        require(IERC20b(lp.token).transferFrom(msg.sender, address(this), pull), "Xfer fail");
        require(IERC20b(lp.token).balanceOf(address(this)) - balBefore >= pull, "Low xfer");
        lp.collected += pull;
        contributions[id][msg.sender] += pull; // Add to existing contributions
    }
    
    voted[id][msg.sender] = true;
    if (inFavor) p.votesFor++;
    emit Voted(id, msg.sender, inFavor);
}

function executeRenewal(uint256 id) external {
    Proposal storage p = proposals[id];
    require(!p.executed && _now() < p.expiry, "Invalid");
    require(p.votesFor > members.length / 2, "No quorum");
    
    LeaseProposal memory lp = leaseProps[id];
    require(lp.collected >= lp.totalNeeded, "Underfunded");
    
    // Verify we still have the lease
    (, address lessee, , , , , ) = IKarah(karah).getLeaseDetails(p.node);
    require(lessee == address(this), "Lost lease");
    
    p.executed = true;

    // Approve Karah to pull renewal funds
    require(IERC20b(lp.token).approve(karah, lp.totalNeeded), "Approve fail");

    // Karah pulls via transferFrom
    IKarah(karah).renew(p.node, lp.durationDays);

    emit ProposalExecuted(id, p.node);
}
}