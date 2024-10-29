// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

error InvalidAddress();
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
error ExtraBudgetAlreadyWithdrawn();


struct Campaign {
    string name;
    uint64 startTime;
    uint64 endTime;
    address rewardToken;
    address campaignOwner;
    bool extraBudgetWithdrawn;
    uint256 campaignBudget;
    bytes32 merkleRoot;
    uint256 achievedMilestoneReward;
    uint256 totalAmountClaimed;
    uint256 totalPointsAllocated;
}

contract CampaignRegistryUpgradeable is Initializable, OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    mapping(uint256 => Campaign) public campaigns;
    mapping(uint256 => mapping(string => bool)) public claimedRewards;
    address public signerAddress;

    uint256 public constant MIN_CAMPAIGN_DURATION = 1 days;
    uint256 public constant MAX_CAMPAIGN_DURATION = 365 days;

    event RewardClaimed(uint256 indexed campaignId, address indexed recipient, string indexed twitterUserId, address rewardToken, uint256 amount);
    event SignerAddressUpdated(address newSignerAddress);
    event CampaignPublished(uint256 indexed campaignId, string name, string description, uint64 startTime, uint64 endTime, address token, uint256 campaignBudget, address indexed campaignOwner);
    event CampaignSettled(uint256 indexed campaignId, bytes32 merkleRoot, uint256 totalPointsAllocated, uint256 achievedMilestoneReward);
    event CampaignCancelled(uint256 indexed campaignId);
    event ExtraBudgetWithdrawn(uint256 indexed campaignId, address rewardToken, uint256 amount);
    event BudgetAdded(uint256 indexed campaignId, address rewardToken, uint256 newBudget);


    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _initialOwner, address _signerAddress) initializer public {
        if (_initialOwner == address(0) || _signerAddress == address(0)) revert InvalidAddress();

        __Ownable_init(_initialOwner);
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        signerAddress = _signerAddress;
    }

    // Upgrade authorization
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}


    modifier campaignExists(uint256 campaignId) {
        if (campaigns[campaignId].startTime == 0) revert CampaignNotFound();
        _;
    }

    modifier onlyCampaignOwner(uint256 campaignId) {
        if (msg.sender != campaigns[campaignId].campaignOwner) revert OnlyCampaignOwner();
        _;
    }

    function getCampaign(uint256 campaignId) external view returns (Campaign memory) {
        return campaigns[campaignId];
    }   

    function updateSignerAddress(address _newSignerAddress) external onlyOwner {
        if (_newSignerAddress == address(0)) revert InvalidAddress();
        signerAddress = _newSignerAddress;
        emit SignerAddressUpdated(_newSignerAddress);
    }

    function publishCampaign(
        uint256 campaignId,
        string memory name,
        string memory description,
        uint64 startTime,
        uint64 endTime,
        address rewardToken,
        uint256 campaignBudget ) external whenNotPaused {
        if (campaigns[campaignId].startTime != 0) revert CampaignAlreadyExists();
        if (startTime <= block.timestamp) revert InvalidTimeRange();
        if (endTime - startTime < MIN_CAMPAIGN_DURATION || endTime - startTime > MAX_CAMPAIGN_DURATION) revert InvalidTimeRange();

        if (!IERC20(rewardToken).transferFrom(msg.sender, address(this), campaignBudget)) revert TransferFailed();

        campaigns[campaignId] = Campaign({
            name: name,
            startTime: startTime,
            endTime: endTime,
            totalPointsAllocated: 0,
            rewardToken: rewardToken,
            campaignBudget: campaignBudget,
            merkleRoot: bytes32(0),
            achievedMilestoneReward: 0,
            totalAmountClaimed: 0,
            campaignOwner: msg.sender,
            extraBudgetWithdrawn: false
        });

        emit CampaignPublished(campaignId, name, description, startTime, endTime, rewardToken, campaignBudget, msg.sender);
    }

    function claimReward(
        uint256 campaignId,
        string memory twitterUserId,
        address recipient,
        uint256 amount,
        bytes32[] calldata merkleProof,
        bytes memory signature
    ) external whenNotPaused campaignExists(campaignId) nonReentrant{
        Campaign storage campaign = campaigns[campaignId];
        if (claimedRewards[campaignId][twitterUserId]) revert RewardAlreadyClaimed();
        if (campaign.merkleRoot == bytes32(0)) revert CampaignNotSettled();

        // Verify Merkle proof
        bytes32 leaf = keccak256(abi.encodePacked(twitterUserId,":", amount));
        if (!MerkleProof.verify(merkleProof, campaign.merkleRoot, leaf)) revert InvalidMerkleProof();

        // Verify signature
        bytes32 message = keccak256(abi.encodePacked(campaignId, recipient, amount, merkleProof));
        bytes32 signedMessage = message.toEthSignedMessageHash();
        if (signedMessage.recover(signature) != signerAddress) revert InvalidSignature();

        // Mark as claimed and transfer reward
        claimedRewards[campaignId][twitterUserId] = true;
        campaign.totalAmountClaimed += amount;
        if (campaign.totalAmountClaimed > campaign.achievedMilestoneReward) revert InsufficientRewards();
        if (!IERC20(campaign.rewardToken).transfer(recipient, amount)) revert TransferFailed();

        emit RewardClaimed(campaignId,recipient, twitterUserId, campaign.rewardToken, amount);
    }

    function settleCampaign(uint256 campaignId, bytes32 merkleRoot, uint256 totalPointsAllocated, uint256 achievedMilestoneReward, bytes memory signature) external onlyCampaignOwner(campaignId)  whenNotPaused {
        Campaign storage campaign = campaigns[campaignId];
        if (campaign.endTime > block.timestamp) revert CampaignStillActive();
        if (campaign.merkleRoot != bytes32(0)) revert CampaignAlreadySettled();
        if (achievedMilestoneReward > campaign.campaignBudget) revert CampaignBudgetExceeded();

        // Verify signature (Allow reward allocation only from protocol Dapp UI )
        bytes32 message = keccak256(abi.encodePacked(campaignId, merkleRoot, totalPointsAllocated, achievedMilestoneReward));
        bytes32 signedMessage = message.toEthSignedMessageHash();
        if (signedMessage.recover(signature) != signerAddress) revert InvalidSignature();

        campaign.merkleRoot = merkleRoot;
        campaign.totalPointsAllocated = totalPointsAllocated;
        campaign.achievedMilestoneReward = achievedMilestoneReward;
        emit CampaignSettled(campaignId, merkleRoot, totalPointsAllocated, achievedMilestoneReward);
    }

    function cancelCampaign(uint256 campaignId, bytes memory signature) external onlyCampaignOwner(campaignId) whenNotPaused nonReentrant{
        Campaign memory campaign = campaigns[campaignId];
        if (campaign.startTime <= block.timestamp) revert CampaignStillActive();
        
        uint256 budget = campaign.campaignBudget;
        address token = campaign.rewardToken;
        address owner = campaign.campaignOwner;

        // Verify signature (Allow cancel campaaign only from protocol Dapp UI )
        bytes32 message = keccak256(abi.encodePacked(campaignId));
        bytes32 signedMessage = message.toEthSignedMessageHash();
        if (signedMessage.recover(signature) != signerAddress) revert InvalidSignature();

        delete campaigns[campaignId];
        
        if (!IERC20(token).transfer(owner, budget)) revert TransferFailed();
        
        emit CampaignCancelled(campaignId);
    }


    function withdrawExtraBudget(uint256 campaignId) external onlyCampaignOwner(campaignId) whenNotPaused nonReentrant{
        Campaign storage campaign = campaigns[campaignId];
        if (campaign.merkleRoot == bytes32(0)) revert CampaignNotSettled();
        if (campaign.extraBudgetWithdrawn) revert ExtraBudgetAlreadyWithdrawn();
        uint256 extraBudget = campaign.campaignBudget - campaign.achievedMilestoneReward;

        campaign.extraBudgetWithdrawn = true;
        if (!IERC20(campaign.rewardToken).transfer(campaign.campaignOwner, extraBudget)) revert TransferFailed();

        emit ExtraBudgetWithdrawn(campaignId, campaign.rewardToken, extraBudget);
    }

    function addBudget(uint256 campaignId, uint256 extraBudget) external onlyCampaignOwner(campaignId) whenNotPaused {
        Campaign storage campaign = campaigns[campaignId];
        if (campaign.merkleRoot != bytes32(0)) revert CampaignAlreadySettled();

        if (!IERC20(campaign.rewardToken).transferFrom(msg.sender, address(this), extraBudget)) revert TransferFailed();
        campaign.campaignBudget += extraBudget;

        emit BudgetAdded(campaignId, campaign.rewardToken, campaign.campaignBudget);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
