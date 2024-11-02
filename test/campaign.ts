import {
    time,
    loadFixture,
  } from "@nomicfoundation/hardhat-toolbox/network-helpers";
  import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
  import { expect } from "chai";
  import hre from "hardhat";
  import { MerkleTree } from "merkletreejs";
import { getCancelSignature, getClaimSignature, getMerkleProof, getMerkleRoot, getSettleSignature, winners } from "./utils";

const ONE_WEEK_IN_SECS = 7 * 24 * 60 * 60;
const ONE_GWEI = 1_000_000_000;


  describe("Campaign", function () {
    async function deployCampaignRegistryFixture() {
      
      const [owner, signerAddress, user1, user2, creator1, creator2, creator3] = await hre.ethers.getSigners();
      const CampaignRegistry = await hre.ethers.getContractFactory("CampaignRegistry");
      const campaignRegistry = await CampaignRegistry.deploy(owner.address, signerAddress.address);

      const Token = await hre.ethers.getContractFactory("tUSDC");
      const token = await Token.deploy();

      await token.mint(user1.address, 100 *ONE_GWEI);
      await token.mint(user2.address, 100 *ONE_GWEI);

      await token.connect(user1).approve(campaignRegistry, 100 *ONE_GWEI);
      await token.connect(user2).approve(campaignRegistry, 100 *ONE_GWEI);

      return { campaignRegistry, owner, signerAddress, user1, user2, token, creator1, creator2, creator3 };
    }

    async function publishAndSettleCampaign(campaignId: number, campaignRegistry: any, signerAddress: any, campaignOwner: any, token: any) {
      let currentTime = await time.latest();
      await campaignRegistry.connect(campaignOwner).publishCampaign(campaignId, "Test Campaign", "This is a test campaign", currentTime +100, currentTime + ONE_WEEK_IN_SECS, token, 100 *ONE_GWEI);
      await time.increaseTo(currentTime + ONE_WEEK_IN_SECS + 100);
      let merkleRoot = await getMerkleRoot();
      let signature = await getSettleSignature(signerAddress, campaignId, merkleRoot, 100, 90 * ONE_GWEI);
      await campaignRegistry.connect(campaignOwner).settleCampaign(campaignId, merkleRoot, 100, 90 * ONE_GWEI, signature);
    }

    describe("Deployment", function () {
        it("Should set the right owner", async function () {
            const { campaignRegistry, owner } = await loadFixture(deployCampaignRegistryFixture);
            expect(await campaignRegistry.owner()).to.equal(owner.address);
        });

        it("Should set the right signer address", async function () {
            const { campaignRegistry, signerAddress } = await loadFixture(deployCampaignRegistryFixture);
            expect(await campaignRegistry.signerAddress()).to.equal(signerAddress.address);
        });
    });

    describe("Campaigns Publish", function () {

      it("Should create a campaign", async function () {
        const { campaignRegistry, owner, token, user1 } = await loadFixture(deployCampaignRegistryFixture);
        let currentTime = await time.latest();
        let campaignId = 1;
        
        await expect(campaignRegistry.connect(user1).publishCampaign(campaignId, "Test Campaign", "This is a test campaign", currentTime +100, currentTime + ONE_WEEK_IN_SECS, token, 100 *ONE_GWEI)).to.emit(campaignRegistry, "CampaignPublished").withArgs(campaignId, "Test Campaign", "This is a test campaign", currentTime +100, currentTime + ONE_WEEK_IN_SECS, token, 100 *ONE_GWEI, user1.address);
        expect(await campaignRegistry.getCampaign(campaignId)).to.exist;
        expect(await token.balanceOf(campaignRegistry)).to.equal(100 *ONE_GWEI);
        // verify campaign details
        const campaign = await campaignRegistry.getCampaign(campaignId);
        expect(campaign.name).to.equal("Test Campaign");
        expect(campaign.startTime).to.equal(currentTime + 100);
        expect(campaign.endTime).to.equal(currentTime + ONE_WEEK_IN_SECS);
        expect(campaign.campaignBudget).to.equal(100 * ONE_GWEI);
        expect(campaign.campaignOwner).to.equal(user1.address);
      });

      it("Should fail with funds transfer failure (not approved)", async function () {
        const { campaignRegistry, owner, token, user1 } = await loadFixture(deployCampaignRegistryFixture);
        let currentTime = await time.latest();
        let campaignId = 1;
        let newBudget = 1000 * ONE_GWEI;
        await expect(campaignRegistry.connect(user1).publishCampaign(campaignId, "Test Campaign", "This is a test campaign", currentTime +100, currentTime + ONE_WEEK_IN_SECS, token, newBudget)).to.revertedWithCustomError(token, "ERC20InsufficientAllowance");
      })
      it("Should fail with funds transfer failure (transfer failed)", async function () {
        const { campaignRegistry, owner, token, user1 } = await loadFixture(deployCampaignRegistryFixture);
        let currentTime = await time.latest();
        let campaignId = 1;
        let newBudget = 1000 * ONE_GWEI;
        await token.connect(user1).approve(campaignRegistry, newBudget);
        await expect(campaignRegistry.connect(user1).publishCampaign(campaignId, "Test Campaign", "This is a test campaign", currentTime +100, currentTime + ONE_WEEK_IN_SECS, token, newBudget)).to.revertedWithCustomError(token, "ERC20InsufficientBalance");
      })
    });

    describe("Campaigns Settle", function () {
      it("Should settle a campaign", async function () {
        const { campaignRegistry, owner, token, signerAddress, user1 } = await loadFixture(deployCampaignRegistryFixture);
        let currentTime = await time.latest();
        let campaignId = 1;

        await campaignRegistry.connect(user1).publishCampaign(campaignId, "Test Campaign", "This is a test campaign", currentTime +100, currentTime + ONE_WEEK_IN_SECS, token, 100 *ONE_GWEI);
        await time.increaseTo(currentTime + ONE_WEEK_IN_SECS + 100);
        let merkleRoot = await getMerkleRoot();
        let signature = await getSettleSignature(signerAddress, campaignId, merkleRoot, 100, 100 * ONE_GWEI);
        await expect(campaignRegistry.connect(user1).settleCampaign(campaignId, merkleRoot, 100, 100 * ONE_GWEI, signature)).to.emit(campaignRegistry, "CampaignSettled");
      })

      it("Should not settle a campaign if the campaign is not ended", async function () {
        const { campaignRegistry, owner, token, signerAddress, user1 } = await loadFixture(deployCampaignRegistryFixture);
        let currentTime = await time.latest();
        let campaignId = 1;
        await campaignRegistry.connect(user1).publishCampaign(campaignId, "Test Campaign", "This is a test campaign", currentTime +100, currentTime + ONE_WEEK_IN_SECS, token, 100 *ONE_GWEI);
        let merkleRoot = await getMerkleRoot();
        let signature = await getSettleSignature(signerAddress, campaignId, merkleRoot, 100, 100 * ONE_GWEI);

        await expect(campaignRegistry.connect(user1).settleCampaign(campaignId, merkleRoot, 100, 100 * ONE_GWEI, signature)).to.be.revertedWithCustomError(campaignRegistry,"CampaignStillActive");
      })

      it("Should not settle a campaign if the campaign is not owned by the user", async function () {
        const { campaignRegistry, owner, token, signerAddress, user1, user2 } = await loadFixture(deployCampaignRegistryFixture);
        let currentTime = await time.latest();
        let campaignId = 1;
        await campaignRegistry.connect(user1).publishCampaign(campaignId, "Test Campaign", "This is a test campaign", currentTime +100, currentTime + ONE_WEEK_IN_SECS, token, 100 *ONE_GWEI);
        await time.increaseTo(currentTime + ONE_WEEK_IN_SECS + 100);

        let merkleRoot = await getMerkleRoot();
        let signature = await getSettleSignature(signerAddress, campaignId, merkleRoot, 100, 100 * ONE_GWEI);

        await expect(campaignRegistry.connect(user2).settleCampaign(campaignId, merkleRoot, 100, 100 * ONE_GWEI, signature)).to.be.revertedWithCustomError(campaignRegistry,"OnlyCampaignOwner");
      })
      it("Should fail if achieved milestone reward is greater than campaign budget", async function () {
        const { campaignRegistry, owner, token, signerAddress, user1 } = await loadFixture(deployCampaignRegistryFixture);
        let currentTime = await time.latest();
        let campaignId = 1;
        await campaignRegistry.connect(user1).publishCampaign(campaignId, "Test Campaign", "This is a test campaign", currentTime +100, currentTime + ONE_WEEK_IN_SECS, token, 100 *ONE_GWEI);
        await time.increaseTo(currentTime + ONE_WEEK_IN_SECS + 100);

        let merkleRoot = await getMerkleRoot();
        let signature = await getSettleSignature(signerAddress, campaignId, merkleRoot, 100, 100 * ONE_GWEI);
        await expect(campaignRegistry.connect(user1).settleCampaign(campaignId, merkleRoot, 100, 1000 * ONE_GWEI, signature)).to.be.revertedWithCustomError(campaignRegistry, "CampaignBudgetExceeded");
      })
    });

    describe("Campaigns Cancel", function () {

      it("Should cancel a campaign", async function () {
        const { campaignRegistry, owner, token, signerAddress, user1 } = await loadFixture(deployCampaignRegistryFixture);
        let currentTime = await time.latest();
        let campaignId = 1;
        await campaignRegistry.connect(user1).publishCampaign(campaignId, "Test Campaign", "This is a test campaign", currentTime +100, currentTime + ONE_WEEK_IN_SECS, token, 100 *ONE_GWEI);
        let signature = await getCancelSignature(signerAddress, campaignId);
        await expect(campaignRegistry.connect(user1).cancelCampaign(campaignId, signature)).to.changeTokenBalances(token, [user1.address, campaignRegistry], [ 100 *ONE_GWEI, -100 *ONE_GWEI]);
      })
      it("Should not cancel a campaign if the campaign is not owned by the user", async function () {
        const { campaignRegistry, owner, token, signerAddress, user1, user2 } = await loadFixture(deployCampaignRegistryFixture);
        let currentTime = await time.latest();
        let campaignId = 1;
        await campaignRegistry.connect(user1).publishCampaign(campaignId, "Test Campaign", "This is a test campaign", currentTime +100, currentTime + ONE_WEEK_IN_SECS, token, 100 *ONE_GWEI);
        let signature = await getCancelSignature(signerAddress, campaignId);
        await expect(campaignRegistry.connect(user2).cancelCampaign(campaignId, signature)).to.be.revertedWithCustomError(campaignRegistry, "OnlyCampaignOwner");
      })
      it("Should not cancel a campaign if the campaign is active", async function () {
        const { campaignRegistry, owner, token, signerAddress, user1 } = await loadFixture(deployCampaignRegistryFixture);
        let currentTime = await time.latest();
        let campaignId = 1;
        await campaignRegistry.connect(user1).publishCampaign(campaignId, "Test Campaign", "This is a test campaign", currentTime +100, currentTime + ONE_WEEK_IN_SECS, token, 100 *ONE_GWEI);
        await time.increaseTo(currentTime + 100);
        let signature = await getCancelSignature(signerAddress, campaignId);
        await expect(campaignRegistry.connect(user1).cancelCampaign(campaignId, signature)).to.be.revertedWithCustomError(campaignRegistry, "CampaignStillActive");
      })
      it("Should fail if campaign already cancelled", async function () {
        const { campaignRegistry, owner, token, signerAddress, user1 } = await loadFixture(deployCampaignRegistryFixture);
        let currentTime = await time.latest();
        let campaignId = 1;
        await campaignRegistry.connect(user1).publishCampaign(campaignId, "Test Campaign", "This is a test campaign", currentTime +100, currentTime + ONE_WEEK_IN_SECS, token, 100 *ONE_GWEI);
        let signature = await getCancelSignature(signerAddress, campaignId);
        await campaignRegistry.connect(user1).cancelCampaign(campaignId, signature);
        await expect(campaignRegistry.connect(user1).cancelCampaign(campaignId, signature)).to.be.reverted;
      })
    })

    describe("Campagins claim rewards", function () {

      it("Should claim rewards", async function () {
        const { campaignRegistry, token, signerAddress, user1, creator1, creator2, creator3 } = await loadFixture(deployCampaignRegistryFixture);
        let campaignId = 1;
        await publishAndSettleCampaign(campaignId, campaignRegistry, signerAddress, user1, token);
        let index = 0;
        let proof = getMerkleProof(winners[index].twitterId, winners[index].amount);
        let claimSignature = await getClaimSignature(signerAddress, campaignId, winners[index].twitterId, winners[index].amount, creator1.address, proof);
        await expect(campaignRegistry.connect(creator1).claimReward(campaignId, winners[index].twitterId, creator1.address, winners[index].amount, proof, claimSignature)).to.changeTokenBalances(token, [creator1.address, campaignRegistry], [winners[index].amount, -winners[index].amount]);  

        index++;
        proof = getMerkleProof(winners[index].twitterId, winners[index].amount);
        claimSignature = await getClaimSignature(signerAddress, campaignId, winners[index].twitterId, winners[index].amount, creator2.address, proof);
        await expect(campaignRegistry.connect(creator2).claimReward(campaignId, winners[index].twitterId, creator2.address, winners[index].amount, proof, claimSignature)).to.changeTokenBalances(token, [creator2.address, campaignRegistry], [winners[index].amount, -winners[index].amount]);  

        index++;
        proof = getMerkleProof(winners[index].twitterId, winners[index].amount);
        claimSignature = await getClaimSignature(signerAddress, campaignId, winners[index].twitterId, winners[index].amount, creator3.address, proof);
        await expect(campaignRegistry.connect(creator3).claimReward(campaignId, winners[index].twitterId, creator3.address, winners[index].amount, proof, claimSignature)).to.changeTokenBalances(token, [creator3.address, campaignRegistry], [winners[index].amount, -winners[index].amount]);  
      })

      it("should not claim if merkle proof is invalid", async function () {
        const { campaignRegistry, token, signerAddress, user1, creator1, creator2, creator3 } = await loadFixture(deployCampaignRegistryFixture);
        let campaignId = 1;
        await publishAndSettleCampaign(campaignId, campaignRegistry, signerAddress, user1, token);
        let index = 0;
        // incorrect amount for twitterId
        let proof = getMerkleProof(winners[index].twitterId, winners[index].amount + 1);
        let claimSignature = await getClaimSignature(signerAddress, campaignId, winners[index].twitterId, winners[index].amount + 1, creator1.address, proof);
        await expect(campaignRegistry.connect(creator1).claimReward(campaignId, winners[index].twitterId, creator1.address, winners[index].amount + 1, proof, claimSignature)).to.be.revertedWithCustomError(campaignRegistry, "InvalidMerkleProof");

        // incorrect twitterId
        proof = getMerkleProof(winners[index].twitterId + "x", winners[index].amount);
        claimSignature = await getClaimSignature(signerAddress, campaignId, winners[index].twitterId + "x", winners[index].amount, creator1.address, proof);
        await expect(campaignRegistry.connect(creator1).claimReward(campaignId, winners[index].twitterId + "x", creator1.address, winners[index].amount, proof, claimSignature)).to.be.revertedWithCustomError(campaignRegistry, "InvalidMerkleProof");
      })

      it("should not claim if signature is invalid", async function () {
        const { campaignRegistry, token, signerAddress, user1, user2, creator1, creator2, creator3 } = await loadFixture(deployCampaignRegistryFixture);
        let campaignId = 1;
        await publishAndSettleCampaign(campaignId, campaignRegistry, signerAddress, user1, token);
        let index = 0;
        let proof = getMerkleProof(winners[index].twitterId, winners[index].amount);
        let claimSignature = await getClaimSignature(signerAddress, campaignId, winners[index].twitterId, winners[index].amount, creator1.address, proof);
        // incorrect signer address
        claimSignature = await getClaimSignature(user1, campaignId, winners[index].twitterId, winners[index].amount, creator2.address, proof);
        await expect(campaignRegistry.connect(creator1).claimReward(campaignId, winners[index].twitterId, creator2.address, winners[index].amount, proof, claimSignature)).to.be.revertedWithCustomError(campaignRegistry, "InvalidSignature");
        // incorrect imput params (recipient)
        claimSignature = await getClaimSignature(signerAddress, campaignId, winners[index].twitterId, winners[index].amount, creator1.address, proof);
        await expect(campaignRegistry.connect(creator1).claimReward(campaignId, winners[index].twitterId, creator2.address, winners[index].amount, proof, claimSignature)).to.be.revertedWithCustomError(campaignRegistry, "InvalidSignature");
        
      })
      it("Should fail if already claimed", async function () {
        const { campaignRegistry, token, signerAddress, user1, creator1 } = await loadFixture(deployCampaignRegistryFixture);
        let campaignId = 1;
        await publishAndSettleCampaign(campaignId, campaignRegistry, signerAddress, user1, token);
        let index = 0;
        let proof = getMerkleProof(winners[index].twitterId, winners[index].amount);
        let claimSignature = await getClaimSignature(signerAddress, campaignId, winners[index].twitterId, winners[index].amount, creator1.address, proof);
        await campaignRegistry.connect(creator1).claimReward(campaignId, winners[index].twitterId, creator1.address, winners[index].amount, proof, claimSignature);
        await expect(campaignRegistry.connect(creator1).claimReward(campaignId, winners[index].twitterId, creator1.address, winners[index].amount, proof, claimSignature)).to.be.revertedWithCustomError(campaignRegistry, "RewardAlreadyClaimed");
      })
    })

    describe("Campaigns withdraw extra budget", function () {
      it("Should withdraw extra budget", async function () {
        const { campaignRegistry, owner, token, signerAddress, user1 } = await loadFixture(deployCampaignRegistryFixture);
        let campaignId = 1;
        await publishAndSettleCampaign(campaignId, campaignRegistry, signerAddress, user1, token);
        let extraBudget = 10 * ONE_GWEI;
        await expect(campaignRegistry.connect(user1).withdrawExtraBudget(campaignId)).to.changeTokenBalances(token, [user1.address, campaignRegistry], [ extraBudget, -extraBudget]);
      })
      it("Should fail if extra budget is already withdrawn", async function () {
        const { campaignRegistry, owner, token, signerAddress, user1 } = await loadFixture(deployCampaignRegistryFixture);
        let campaignId = 1;
        await publishAndSettleCampaign(campaignId, campaignRegistry, signerAddress, user1, token);
        await campaignRegistry.connect(user1).withdrawExtraBudget(campaignId);
        await expect(campaignRegistry.connect(user1).withdrawExtraBudget(campaignId)).to.be.revertedWithCustomError(campaignRegistry, "ExtraBudgetAlreadyWithdrawn");
      })
      it("Should fail if campaign is not settled", async function () {
        const { campaignRegistry, owner, token, signerAddress, user1 } = await loadFixture(deployCampaignRegistryFixture);
        let campaignId = 1;
        let currentTime = await time.latest();
        await campaignRegistry.connect(user1).publishCampaign(campaignId, "Test Campaign", "This is a test campaign", currentTime +100, currentTime + ONE_WEEK_IN_SECS, token, 100 *ONE_GWEI);
        await time.increaseTo(currentTime + ONE_WEEK_IN_SECS + 100);
        await expect(campaignRegistry.connect(user1).withdrawExtraBudget(campaignId)).to.be.revertedWithCustomError(campaignRegistry, "CampaignNotSettled");
      })
    })
    describe("Campaigns add budget", function () {
      it("Should add budget", async function () {
        const { campaignRegistry, owner, token, signerAddress, user1 } = await loadFixture(deployCampaignRegistryFixture);
        let campaignId = 1;
        let currentTime = await time.latest();
        await campaignRegistry.connect(user1).publishCampaign(campaignId, "Test Campaign", "This is a test campaign", currentTime +100, currentTime + ONE_WEEK_IN_SECS, token, 100 *ONE_GWEI);
        let extraBudget = 50 * ONE_GWEI;

        // minting tokens to user1
        await token.connect(owner).mint(user1.address, extraBudget);
        // adding approval
        await token.connect(user1).approve(campaignRegistry, extraBudget);
        await expect(campaignRegistry.connect(user1).addBudget(campaignId, extraBudget)).to.changeTokenBalances(token, [user1.address, campaignRegistry], [ -extraBudget, extraBudget]);

        // checking if the budget is added
        const campaign = await campaignRegistry.getCampaign(campaignId);
        expect(campaign.campaignBudget).to.equal(150 * ONE_GWEI);
      })
    })
});
