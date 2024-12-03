// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";


/// @notice Invalid address provided for a required parameter
error InvalidAddress();
/// @notice Campaign with the specified ID does not exist
error CampaignNotFound();
/// @notice Invalid fee percentage provided
error InvalidFeePercentage();
/// @notice Reward has already been claimed for this user
error RewardAlreadyClaimed();
/// @notice Campaign has not been settled yet
error CampaignNotSettled();
/// @notice Provided signature is invalid or from unauthorized signer
error InvalidSignature();
/// @notice Provided Merkle proof is invalid
error InvalidMerkleProof();
/// @notice Insufficient rewards available for claiming
error InsufficientRewards();
/// @notice Campaign is still active and cannot be settled/cancelled
error CampaignStillActive();
/// @notice Campaign has already been settled
error CampaignAlreadySettled();
/// @notice Campaign achieved milestone reward exceeded total campaign budget
error CampaignBudgetExceeded();
/// @notice Invalid time range specified for campaign
error InvalidTimeRange();
/// @notice Only the campaign owner can perform this operation
error OnlyCampaignOwner();
/// @notice Campaign with this ID already exists
error CampaignAlreadyExists();
/// @notice Extra budget has already been withdrawn
error ExtraBudgetAlreadyWithdrawn();
/// @notice No unclaimed budget to withdraw
error NoUnclaimedBudget();
/// @notice Claim window has not ended yet
error ClaimWindowNotOver();

/// @notice Campaign struct containing all campaign details
/// @param name Name of the campaign
/// @param startTime Unix timestamp when the campaign starts
/// @param endTime Unix timestamp when the campaign ends
/// @param rewardToken Address of the ERC20 token used for rewards
/// @param campaignOwner Address of the campaign owner
/// @param extraBudgetWithdrawn Whether the extra budget has been withdrawn
/// @param campaignBudget Total budget allocated for the campaign
/// @param merkleRoot Merkle root of the reward distribution tree
/// @param achievedMilestoneReward Total rewards allocated based on achieved milestones
/// @param totalAmountClaimed Total amount of rewards claimed so far
/// @param totalPointsAllocated Total points allocated in the campaign
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

/// @title Campaign Registry for managing reward distribution campaigns
/// @notice This contract manages the lifecycle of reward distribution campaigns including creation,
/// reward claims, settlement, and budget management
/// @dev Implements OpenZeppelin's Ownable, Pausable, and ReentrancyGuard for security
contract CampaignRegistry is Ownable, Pausable, ReentrancyGuard {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;
    using SafeERC20 for IERC20;

    /// @notice Mapping of campaign IDs to Campaign structs
    mapping(uint256 => Campaign) public campaigns;
    /// @notice Mapping to track claimed rewards per campaign and Twitter user ID
    mapping(uint256 => mapping(string => bool)) public claimedRewards;

    /// @notice Address of the signer used to verify signatures
    address public signerAddress;
    /// @notice Claim window in seconds
    uint256 public claimWindow = 90 days; // 3 months

    /// @notice Fee percentage (100 = 100%)
    uint256 public feePercentage = 5; 
    /// @notice Address of the recipient for collected fees (address(0) means fees disabled)
    address public feeRecipient = address(0);

    /// @notice Emitted when a reward is claimed from a campaign
    /// @param campaignId ID of the campaign
    /// @param recipient Address receiving the reward
    /// @param twitterUserId Twitter user ID of the recipient
    /// @param rewardToken Address of the reward token
    /// @param amount Amount of tokens claimed
    event RewardClaimed(uint256 indexed campaignId, address indexed recipient, string indexed twitterUserId, address rewardToken, uint256 amount);
    
    /// @notice Emitted when the signer address is updated
    /// @param newSignerAddress New address authorized to sign operations
    event SignerAddressUpdated(address newSignerAddress);

    /// @notice Emitted when the fee recipient is updated
    /// @param newFeeRecipient New fee recipient address
    event FeeRecipientUpdated(address newFeeRecipient);

    /// @notice Emitted when the fee percentage is updated
    /// @param newFeePercentage New fee percentage in basis points (1/100th of a percent)
    event FeePercentageUpdated(uint256 newFeePercentage);

    /// @notice Emitted when the claim window is updated
    /// @param newClaimWindow New claim window in seconds
    event ClaimWindowUpdated(uint256 newClaimWindow);

    /// @notice Emitted when a campaign ownership is transferred
    /// @param campaignId ID of the campaign
    /// @param newOwner Address of the new campaign owner
    event CampaignOwnershipTransferred(uint256 indexed campaignId, address indexed newOwner);
    
    /// @notice Emitted when a new campaign is published
    /// @param campaignId ID of the campaign
    /// @param name Name of the campaign
    /// @param description Description of the campaign
    /// @param startTime Start time of the campaign (Unix timestamp)
    /// @param endTime End time of the campaign (Unix timestamp)
    /// @param token Address of the reward token
    /// @param campaignBudget Total budget allocated for the campaign
    /// @param campaignOwner Address of the campaign owner
    event CampaignPublished(uint256 indexed campaignId, string name, string description, uint64 startTime, uint64 endTime, address token, uint256 campaignBudget, address indexed campaignOwner);
    
    /// @notice Emitted when a campaign is settled
    /// @param campaignId ID of the campaign
    /// @param merkleRoot Merkle root of the reward distribution tree
    /// @param totalPointsAllocated Total points allocated in the campaign
    /// @param achievedMilestoneReward Total rewards to be distributed based on achieved milestones
    event CampaignSettled(uint256 indexed campaignId, bytes32 merkleRoot, uint256 totalPointsAllocated, uint256 achievedMilestoneReward);
    
    /// @notice Emitted when fee is collected from a campaign
    /// @param campaignId ID of the campaign
    /// @param feeRecipient Address of the fee recipient
    /// @param feeAmount Amount of fee collected
    event FeeCollected(uint256 indexed campaignId, address indexed feeRecipient, uint256 feeAmount);

    /// @notice Emitted when unclaimed budget is withdrawn
    /// @param campaignId ID of the campaign
    /// @param rewardToken Address of the reward token
    /// @param amount Amount of tokens withdrawn
    event UnclaimedBudgetWithdrawn(uint256 indexed campaignId, address rewardToken, uint256 amount);

    /// @notice Emitted when a campaign is cancelled
    /// @param campaignId ID of the cancelled campaign
    /// @param campaignOwner Address of the campaign owner
    /// @param campaignBudget Total budget allocated for the campaign (returned to owner)
    event CampaignCancelled(uint256 indexed campaignId, address indexed campaignOwner, uint256 campaignBudget);
    
    /// @notice Emitted when extra budget is withdrawn
    /// @param campaignId ID of the campaign
    /// @param rewardToken Address of the reward token
    /// @param amount Amount of tokens withdrawn
    event ExtraBudgetWithdrawn(uint256 indexed campaignId, address rewardToken, uint256 amount);
    
    /// @notice Emitted when additional budget is added to a campaign
    /// @param campaignId ID of the campaign
    /// @param sponsor Address of the sponsor adding the budget
    /// @param rewardToken Address of the reward token
    /// @param extraBudget Amount of extra budget added
    /// @param newBudget New total budget after addition
    event BudgetAdded(uint256 indexed campaignId, address indexed sponsor, address rewardToken, uint256 extraBudget, uint256 newBudget);

    /// @notice Initializes the contract with an owner and signer address
    /// @param _initialOwner Address of the contract owner
    /// @param _signerAddress Address authorized to sign operations
    constructor(address _initialOwner, address _signerAddress) Ownable(_initialOwner) {
        if (_initialOwner == address(0) || _signerAddress == address(0)) revert InvalidAddress();
        signerAddress = _signerAddress;
    }

    /// @notice Modifier to check if a campaign exists
    /// @param campaignId ID of the campaign to check
    modifier campaignExists(uint256 campaignId) {
        if (campaigns[campaignId].startTime == 0) revert CampaignNotFound();
        _;
    }

    /// @notice Modifier to restrict access to campaign owner
    /// @param campaignId ID of the campaign
    modifier onlyCampaignOwner(uint256 campaignId) {
        if (msg.sender != campaigns[campaignId].campaignOwner) revert OnlyCampaignOwner();
        _;
    }

    /// @notice Retrieves campaign details
    /// @param campaignId ID of the campaign
    /// @return Campaign struct containing campaign details
    function getCampaign(uint256 campaignId) external view returns (Campaign memory) {
        return campaigns[campaignId];
    }   

    /// @notice Updates the address authorized to sign operations
    /// @param _newSignerAddress New signer address
    /// @dev Only the registry owner can update the signer address
    function updateSignerAddress(address _newSignerAddress) external onlyOwner {
        if (_newSignerAddress == address(0)) revert InvalidAddress();
        signerAddress = _newSignerAddress;
        emit SignerAddressUpdated(_newSignerAddress);
    }

    /// @notice Updates the address of the recipient for collected fees
    /// @param _newFeeRecipient New fee recipient address
    /// @dev Only the registry owner can update the fee recipient
    function updateFeeRecipient(address _newFeeRecipient) external onlyOwner {
        feeRecipient = _newFeeRecipient;
        emit FeeRecipientUpdated(_newFeeRecipient);
    }

    /// @notice Updates the fee percentage
    /// @param _newFeePercentage New fee percentage in basis points (1/100th of a percent)
    /// @dev Only the registry owner can update the fee percentage (Max: 10%)
    function updateFeePercentage(uint256 _newFeePercentage) external onlyOwner {
        if (_newFeePercentage > 10) revert InvalidFeePercentage();
        feePercentage = _newFeePercentage;
        emit FeePercentageUpdated(_newFeePercentage);
    }

    /// @notice Updates the claim window
    /// @param _newClaimWindow New claim window in seconds
    function updateClaimWindow(uint256 _newClaimWindow) external onlyOwner {
        claimWindow = _newClaimWindow;
        emit ClaimWindowUpdated(_newClaimWindow);
    }

    /// @notice Transfers campaign ownership to a new address
    /// @param campaignId ID of the campaign
    /// @param newOwner Address of the new campaign owner
    /// @dev Only the current campaign owner can transfer ownership
    function transferCampaignOwnership(uint256 campaignId, address newOwner) external onlyCampaignOwner(campaignId) {
        campaigns[campaignId].campaignOwner = newOwner;

        emit CampaignOwnershipTransferred(campaignId, newOwner);
    }

    /// @notice Publishes a new campaign
    /// @param campaignId ID for the new campaign
    /// @param name Name of the campaign
    /// @param description Description of the campaign (only to be logged in events)
    /// @param startTime Start time of the campaign (Unix timestamp)
    /// @param endTime End time of the campaign (Unix timestamp)
    /// @param rewardToken Address of the reward token
    /// @param campaignBudget Total budget for the campaign (in reward token decimals)
    function publishCampaign(
        uint256 campaignId,
        string memory name,
        string memory description,
        uint64 startTime,
        uint64 endTime,
        address rewardToken,
        uint256 campaignBudget ) external whenNotPaused {
        if (campaigns[campaignId].startTime != 0) revert CampaignAlreadyExists();
        if (startTime <= block.timestamp || endTime <= startTime) revert InvalidTimeRange();

        IERC20(rewardToken).safeTransferFrom(msg.sender, address(this), campaignBudget);

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

    /// @notice Claims rewards for a participant using a Merkle proof and signature
    /// @param campaignId ID of the campaign
    /// @param twitterUserId Twitter user ID of the participant
    /// @param recipient Address to receive the reward
    /// @param amount Amount of tokens to claim (in reward token decimals)
    /// @param merkleProof Merkle proof verifying the claim
    /// @param signature Signature from authorized signer
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
        IERC20(campaign.rewardToken).safeTransfer(recipient, amount);   
        emit RewardClaimed(campaignId,recipient, twitterUserId, campaign.rewardToken, amount);
    }

    /// @notice Settles a campaign by setting the reward distribution parameters
    /// @param campaignId ID of the campaign
    /// @param merkleRoot Merkle root of the reward distribution tree
    /// @param totalPointsAllocated Total points allocated in the campaign
    /// @param achievedMilestoneReward Total rewards to be distributed based on achieved milestones
    /// @param signature Signature from authorized signer
    function settleCampaign(uint256 campaignId, bytes32 merkleRoot, uint256 totalPointsAllocated, uint256 achievedMilestoneReward, bytes memory signature) external onlyCampaignOwner(campaignId) whenNotPaused nonReentrant {
        Campaign storage campaign = campaigns[campaignId];
        if (campaign.endTime > block.timestamp) revert CampaignStillActive();
        if (campaign.merkleRoot != bytes32(0)) revert CampaignAlreadySettled();
        if (achievedMilestoneReward > campaign.campaignBudget) revert CampaignBudgetExceeded();

        // Verify signature (Allow reward allocation only from protocol Dapp UI )
        bytes32 message = keccak256(abi.encodePacked(campaignId, merkleRoot, totalPointsAllocated, achievedMilestoneReward));
        bytes32 signedMessage = message.toEthSignedMessageHash();
        if (signedMessage.recover(signature) != signerAddress) revert InvalidSignature();

        // reverting unused budget to campaign owner
        uint256 extraBudget = campaign.campaignBudget - campaign.achievedMilestoneReward;
        if (extraBudget > 0) {
            IERC20(campaign.rewardToken).safeTransfer(campaign.campaignOwner, extraBudget);
            emit ExtraBudgetWithdrawn(campaignId, campaign.rewardToken, extraBudget);
        }

        // Collecting fee from campaign (if enabled)
        if (feeRecipient != address(0)) {
            uint256 feeAmount = (achievedMilestoneReward * feePercentage) / 100;
            IERC20(campaign.rewardToken).safeTransferFrom(msg.sender, feeRecipient, feeAmount);
            achievedMilestoneReward -= feeAmount;
            emit FeeCollected(campaignId, feeRecipient, feeAmount);
        }

        campaign.merkleRoot = merkleRoot;
        campaign.totalPointsAllocated = totalPointsAllocated;
        campaign.achievedMilestoneReward = achievedMilestoneReward;
        emit CampaignSettled(campaignId, merkleRoot, totalPointsAllocated, achievedMilestoneReward);
    }

    /// @notice Cancels a campaign before it starts
    /// @param campaignId ID of the campaign to cancel
    /// @param signature Signature from authorized signer
    function cancelCampaign(uint256 campaignId, bytes memory signature) external onlyCampaignOwner(campaignId) whenNotPaused nonReentrant{
        Campaign memory campaign = campaigns[campaignId];
        if (campaign.startTime <= block.timestamp) revert CampaignStillActive();
        
        uint256 budget = campaign.campaignBudget;
        address token = campaign.rewardToken;
        address owner = campaign.campaignOwner;

        // Verify signature (Allow cancel campaign only from protocol Dapp UI )
        bytes32 message = keccak256(abi.encodePacked(campaignId));
        bytes32 signedMessage = message.toEthSignedMessageHash();
        if (signedMessage.recover(signature) != signerAddress) revert InvalidSignature();

        delete campaigns[campaignId];
        
        IERC20(token).safeTransfer(owner, budget);
        
        emit CampaignCancelled(campaignId, owner, budget);
    }

    /// @notice Withdraws unclaimed budget after campaign claim window ends
    /// @param campaignId ID of the campaign
    function withdrawUnclaimedBudget(uint256 campaignId) external onlyCampaignOwner(campaignId) whenNotPaused nonReentrant{
        Campaign storage campaign = campaigns[campaignId];
        if (campaign.merkleRoot == bytes32(0)) revert CampaignNotSettled();
        if (campaign.totalAmountClaimed == campaign.achievedMilestoneReward) revert NoUnclaimedBudget();
        if (block.timestamp < campaign.endTime + claimWindow) revert ClaimWindowNotOver();

        uint256 unclaimedBudget = campaign.achievedMilestoneReward - campaign.totalAmountClaimed;

        campaign.totalAmountClaimed += unclaimedBudget;
        IERC20(campaign.rewardToken).safeTransfer(campaign.campaignOwner, unclaimedBudget);
        
        emit UnclaimedBudgetWithdrawn(campaignId, campaign.rewardToken, unclaimedBudget);
    }

    /// @notice Adds additional budget to a campaign before settlement (any sponsor can add budget)
    /// @param campaignId ID of the campaign
    /// @param extraBudget Amount of additional budget to add (in reward token decimals)
    function addBudget(uint256 campaignId, uint256 extraBudget) external onlyCampaignOwner(campaignId) whenNotPaused {
        Campaign storage campaign = campaigns[campaignId];
        if (campaign.merkleRoot != bytes32(0)) revert CampaignAlreadySettled();

        IERC20(campaign.rewardToken).safeTransferFrom(msg.sender, address(this), extraBudget);
        campaign.campaignBudget += extraBudget;

        emit BudgetAdded(campaignId, msg.sender, campaign.rewardToken, extraBudget, campaign.campaignBudget);
    }

    /// @notice Pauses the contract
    /// @dev Only callable by registry owner
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpauses the contract
    /// @dev Only callable by registry owner
    function unpause() external onlyOwner {
        _unpause();
    }
}