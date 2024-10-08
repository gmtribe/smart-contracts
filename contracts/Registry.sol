// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";


error CampaignNotFound();
error RewardAlreadyClaimed();
error CampaignNotSettled();
error InvalidSignature();
error InvalidMerkleProof();
error InsufficientRewards();
error CampaignStillActive();
error CampaignAlreadySettled();
error CampaignBudgetExceeded();
error TransferFailed();
error InvalidTimeRange();
error OnlyCampaignOwner();
error CampaignAlreadyExists();

struct Campaign {
    string name;
    string description;
    uint64 startTime;
    uint64 endTime;
    uint256 totalPointsAllocated;
    address rewardToken;
    uint256 campaignBudget;
    bytes32 merkleRoot;
    uint256 achievedMilestoneReward;
    uint256 totalAmountClaimed;
    address campaignOwner;
}


contract CampaignRegistry is Ownable, Pausable {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    mapping(uint256 => Campaign) public campaigns;
    mapping(uint256 => mapping(string => bool)) private claimedRewards;

    address public signerAddress;


    event RewardClaimed(uint256 indexed campaignId, address indexed recipient, string indexed twitterUserId, address rewardToken, uint256 amount);
    event SignerAddressUpdated(address newSignerAddress);
    event CampaignPublished(uint256 indexed campaignId, string name, string description, uint64 startTime, uint64 endTime, address token, uint256 campaignBudget, address indexed campaignOwner);
    event CampaignSettled(uint256 indexed campaignId, bytes32 merkleRoot, uint256 totalPointsAllocated, uint256 achievedMilestoneReward);
    event CampaignCancelled(uint256 indexed campaignId);
    event ExtraBudgetWithdrawn(uint256 indexed campaignId, address rewardToken, uint256 amount);

    constructor(address _initialOwner, address _signerAddress) Ownable(_initialOwner) {
        signerAddress = _signerAddress;
    }

    modifier onlyCampaignOwner(uint256 campaignId) {
        if (msg.sender != campaigns[campaignId].campaignOwner) revert OnlyCampaignOwner();
        _;
    }

    function updateSignerAddress(address _newSignerAddress) external onlyOwner {
        signerAddress = _newSignerAddress;
        emit SignerAddressUpdated(_newSignerAddress);
    }

    function publishCampaign(
        uint64 campaignId,
        string memory name,
        string memory description,
        uint64 startTime,
        uint64 endTime,
        address rewardToken,
        uint256 campaignBudget ) external whenNotPaused {
        if (campaigns[campaignId].startTime != 0) revert CampaignAlreadyExists();
        if (startTime >= endTime) revert InvalidTimeRange();
        if (startTime <= block.timestamp) revert InvalidTimeRange();

        campaigns[campaignId] = Campaign({
            name: name,
            description: description,
            startTime: startTime,
            endTime: endTime,
            totalPointsAllocated: 0,
            rewardToken: rewardToken,
            campaignBudget: campaignBudget,
            merkleRoot: bytes32(0),
            achievedMilestoneReward: 0,
            totalAmountClaimed: 0,
            campaignOwner: msg.sender
        });

        if (!IERC20(rewardToken).transferFrom(msg.sender, address(this), campaignBudget)) revert TransferFailed();
        emit CampaignPublished(campaignId, name, description, startTime, endTime, rewardToken, campaignBudget, msg.sender);
    }

    function claimReward(
        uint256 campaignId,
        string memory twitterUserId,
        address recipient,
        uint256 amount,
        bytes32[] calldata merkleProof,
        bytes memory signature
    ) external whenNotPaused{
        if (claimedRewards[campaignId][twitterUserId]) revert RewardAlreadyClaimed();
        if (campaigns[campaignId].merkleRoot == bytes32(0)) revert CampaignNotSettled();

        // Verify signature
        bytes32 message = keccak256(abi.encodePacked(campaignId, recipient, amount));
        bytes32 signedMessage = message.toEthSignedMessageHash();
        if (signedMessage.recover(signature) != signerAddress) revert InvalidSignature();

        // Verify Merkle proof
        bytes32 leaf = keccak256(abi.encodePacked(twitterUserId, amount));
        if (!MerkleProof.verify(merkleProof, campaigns[campaignId].merkleRoot, leaf)) revert InvalidMerkleProof();

        // Mark as claimed and transfer reward
        claimedRewards[campaignId][twitterUserId] = true;
        campaigns[campaignId].totalAmountClaimed += amount;
        if (campaigns[campaignId].totalAmountClaimed > campaigns[campaignId].achievedMilestoneReward) revert InsufficientRewards();
        if (!IERC20(campaigns[campaignId].rewardToken).transfer(recipient, amount)) revert TransferFailed();

        emit RewardClaimed(campaignId,recipient, twitterUserId, campaigns[campaignId].rewardToken, amount);
    }

    function settleCampaign(uint256 campaignId, bytes32 merkleRoot, uint256 totalPointsAllocated, uint256 achievedMilestoneReward, bytes memory signature) external onlyCampaignOwner(campaignId) whenNotPaused {
        if (campaigns[campaignId].endTime > block.timestamp) revert CampaignStillActive();
        if (campaigns[campaignId].totalPointsAllocated != 0) revert CampaignAlreadySettled();
        if (achievedMilestoneReward > campaigns[campaignId].campaignBudget) revert CampaignBudgetExceeded();

        // Verify signature (Allow reward allocation only from protocol Dapp )
        bytes32 message = keccak256(abi.encodePacked(campaignId, merkleRoot, totalPointsAllocated, achievedMilestoneReward));
        bytes32 signedMessage = message.toEthSignedMessageHash();
        if (signedMessage.recover(signature) != signerAddress) revert InvalidSignature();

        campaigns[campaignId].merkleRoot = merkleRoot;
        campaigns[campaignId].totalPointsAllocated = totalPointsAllocated;
        campaigns[campaignId].achievedMilestoneReward = achievedMilestoneReward;
        emit CampaignSettled(campaignId, merkleRoot, totalPointsAllocated, achievedMilestoneReward);
    }

    function cancelCampaign(uint256 campaignId, bytes memory signature) external onlyCampaignOwner(campaignId) whenNotPaused {
        if (campaigns[campaignId].startTime <= block.timestamp) revert CampaignStillActive();
        
        uint256 budget = campaigns[campaignId].campaignBudget;
        address token = campaigns[campaignId].rewardToken;
        address owner = campaigns[campaignId].campaignOwner;

        // Verify signature (Allow cancel campaaign only from protocol Dapp )
        bytes32 message = keccak256(abi.encodePacked(campaignId));
        bytes32 signedMessage = message.toEthSignedMessageHash();
        if (signedMessage.recover(signature) != signerAddress) revert InvalidSignature();

        delete campaigns[campaignId];
        
        if (!IERC20(token).transfer(owner, budget)) revert TransferFailed();
        
        emit CampaignCancelled(campaignId);
    }

    function getCampaign(uint256 campaignId) external view returns (Campaign memory) {
        return campaigns[campaignId];
    }   

    function withdrawExtraBudget(uint256 campaignId) external onlyCampaignOwner(campaignId) whenNotPaused {
        if (campaigns[campaignId].totalPointsAllocated == 0) revert CampaignNotSettled();
        uint256 extraBudget = campaigns[campaignId].campaignBudget - campaigns[campaignId].achievedMilestoneReward;
        if (!IERC20(campaigns[campaignId].rewardToken).transfer(campaigns[campaignId].campaignOwner, extraBudget)) revert TransferFailed();

        emit ExtraBudgetWithdrawn(campaignId, campaigns[campaignId].rewardToken, extraBudget);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}