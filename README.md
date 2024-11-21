# gm tribe Smart Contracts (Hardhat)

## Overview
A decentralized solution for managing reward distribution campaigns on the Ethereum blockchain. The contract enables campaign owners to create, manage, and distribute rewards to participants using a Merkle tree-based verification system.

## Features
- 🚀 Create and manage reward distribution campaigns
- 🔒 Secure reward claiming with Merkle proofs and digital signatures
- 💰 Flexible budget management with add more budget capabilities by new sponsors
- ⏱️ Time-bound campaigns with configurable durations
- 🛡️ Built-in security features (pausable, reentrancy protection)
- 🎯 Support for milestone-based reward distribution
- 📝 Events for tracking campaign lifecycle and reward distribution

## Tech Stack
- Solidity Version: ^0.8.24
- License: MIT
- OpenZeppelin Dependencies:
  - Ownable
  - IERC20
  - ECDSA
  - MessageHashUtils
  - MerkleProof
  - SafeERC20
  - Pausable
  - ReentrancyGuard

## Contract Overview

### Constants
```solidity
MIN_CAMPAIGN_DURATION = 1 days
MAX_CAMPAIGN_DURATION = 365 days
```

### Campaign Structure
```solidity
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
```

## Core Functions

### Campaign Management
- `publishCampaign`: Create a new reward distribution campaign and locks funds.
- `settleCampaign`: Finalize campaign rewards (achieved milestones based rewards) and set Merkle root (only campaign owner can settle with a signature genreated from protocol Dapp UI)
- `cancelCampaign`: Cancel a campaign before it starts and refund the locked funds (only campaign owner can cancel with a signature genreated from protocol Dapp UI)
- `addBudget`: Add additional budget to an active campaign (any sponsor can add budget)

#### Reward Distribution
- `claimReward`: Claim rewards with Merkle proof verification and signature to verify reward recipient.
- `withdrawExtraBudget`: Withdraw unused campaign budget. ( campaignBudget - achievedMilestoneReward)

#### Administrative (only registry owner perform)
- `updateSignerAddress`: Update the authorized signer 
- `pause`/`unpause`: Emergency pause controls

## Usage Guide

### 1. Creating a Campaign
```solidity
function publishCampaign(
    uint256 campaignId,
    string memory name,
    string memory description,
    uint64 startTime,
    uint64 endTime,
    address rewardToken,
    uint256 campaignBudget
) external
```
- Ensure the campaign duration is between 1 and 365 days
- Approve token transfer before calling
- Campaign ID must be unique

### 2. Settling a Campaign
```solidity
function settleCampaign(
    uint256 campaignId,
    bytes32 merkleRoot,
    uint256 totalPointsAllocated,
    uint256 achievedMilestoneReward,
    bytes memory signature
) external
```
- Can only be called after campaign end time
- Requires authorized signature
- Sets final reward distribution parameters

### 3. Claiming Rewards
```solidity
function claimReward(
    uint256 campaignId,
    string memory twitterUserId,
    address recipient,
    uint256 amount,
    bytes32[] calldata merkleProof,
    bytes memory signature
) external
```
- Requires valid Merkle proof
- Requires authorized signature
- Each Twitter user ID can claim only once per campaign

### 4. Withdrawing Extra Budget
```solidity
function withdrawExtraBudget(uint256 campaignId) external
```
- Withdraws unused campaign budget after settlement (only campaign owner can withdraw)


## Security Features

### Access Control
- Campaign owner-specific functions
- Registry owner administrative functions
- Authorized signer for critical operations

### Safety Mechanisms
- ReentrancyGuard for external calls
- Pausable for emergency situations
- SafeERC20 for token transfers
- Signature verification for critical operations
- Merkle proof verification for claims

## Events
- `RewardClaimed`: Emitted when rewards are claimed
- `SignerAddressUpdated`: Emitted when signer address is updated
- `CampaignPublished`: Emitted when new campaign is created
- `CampaignSettled`: Emitted when campaign is settled
- `CampaignCancelled`: Emitted when campaign is cancelled
- `ExtraBudgetWithdrawn`: Emitted when extra budget is withdrawn
- `BudgetAdded`: Emitted when budget is increased

## Usage Examples

### Creating a Campaign
```javascript
// Approve token transfer first
await rewardToken.approve(campaignRegistry.address, campaignBudget);

// Create campaign
await campaignRegistry.publishCampaign(
    1, // campaignId
    "My Campaign",
    "Campaign Description",
    startTime,
    endTime,
    rewardToken.address,
    campaignBudget
);
```

### Claiming Rewards
```javascript
await campaignRegistry.claimReward(
    campaignId,
    twitterUserId,
    recipientAddress,
    rewardAmount,
    merkleProof,
    signature
);
```


## Installation

```bash
git clone https://github.com/gmtribe/smart-contracts.git
cd smart-contracts
npm install
```

## Testing

```bash
npx hardhat test
```

## Deployment

1. Configure environment
```bash
cp .env.example .env
# Edit .env with your values
```

2. Deploy contract && verify on chain
```bash
npx hardhat ignition deploy ./ignition/modules/deploy.ts --network <network>
npx hardhat ignition verify chain-<chainId> // chainId is the chain id of the network you are deploying to
```

3. Wipe Future Deployments
```shell
npx hardhat ignition wipe chain-<chainId> DeployModule#CampaignRegistry
```
## Security Considerations
- Always verify signatures and Merkle proofs
- Ensure reward token approvals are precise
- Monitor campaign budgets and claims
- Use appropriate time buffers for campaign durations
- Verify recipient addresses before claims

## License
This project is licensed under the MIT License - see the LICENSE file for details.

## Contributing
Contributions are welcome! Please feel free to submit a Pull Request.

## Support
For support, please open an issue in the GitHub repository.