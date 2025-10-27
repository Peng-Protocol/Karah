// SPDX-License-Identifier: BSL 1.1 - Peng Protocol 2025
pragma solidity ^0.8.2;

// File Version: 0.0.1 (27/10/2025)
// Changelog:
// - 27/10/2025: Initial implementation of DAO for collective ENS name management.

interface IKarah {
    function modifyContent(bytes32 node, bytes32 label, address owner, address resolver, uint64 ttl) external;
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

    mapping(uint256 Index => Proposal) public proposals; // Proposal ID => Proposal
    mapping(uint256 Index => mapping(address => bool)) public voted; // Proposal ID => Voter => Voted
    uint256 public proposalCount; // Counter for proposals
    address[] public members; // DAO members
    uint256 public constant MIN_EXPIRY = 1 weeks;
    uint256 public constant MAX_EXPIRY = 26 weeks;

address public karah; // Karah contract address
address public owner; // Contract owner

    event ProposalCreated(uint256 indexed id, address proposer, bytes32 node, uint256 expiry);
    event Voted(uint256 indexed id, address voter, bool inFavor);
    event ProposalExecuted(uint256 indexed id, bytes32 node);

    receive() external payable {} // Allow ETH receipt

constructor() {
    owner = msg.sender;
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
    require(expiry >= block.timestamp + MIN_EXPIRY && expiry <= block.timestamp + MAX_EXPIRY, "Invalid expiry");
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
        require(block.timestamp < proposals[id].expiry, "Proposal expired");
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
    require(block.timestamp < p.expiry, "Proposal expired");
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
}