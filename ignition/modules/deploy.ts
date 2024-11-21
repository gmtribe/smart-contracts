import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const DeployModule = buildModule("DeployModule", (m) => {
    const owner = m.getAccount(0);
    const signerAddress = m.getAccount(1);
    const tUSDC = m.contract("tUSDC");
    const campaignRegistry = m.contract("CampaignRegistry",[owner, signerAddress]);
    return { campaignRegistry, owner, signerAddress, tUSDC };
});

export default DeployModule;