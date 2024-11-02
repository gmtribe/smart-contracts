import { MerkleTree } from "merkletreejs";
import keccak256 from 'keccak256';
import { ethers } from "ethers";

const ONE_GWEI = 1000000000;
export const winners = [
    { twitterId: "1234567890", amount: 20 * ONE_GWEI },
    { twitterId: "1234567891", amount: 30 * ONE_GWEI },
    { twitterId: "1234567892", amount: 40 * ONE_GWEI },
];


function hashLeaf(twitterId: string, amount: string | number | bigint): Buffer {
    return Buffer.from(
        ethers.solidityPackedKeccak256(
            ['string', 'string', 'uint256'],
            [twitterId, ':', amount]
        ).slice(2),
        'hex'
    );
}

export function getMerkleProof(twitterId: string, amount: number) {
    const leaves = winners.map((winner) => hashLeaf(winner.twitterId, winner.amount));
    const merkleTree = new MerkleTree(leaves, keccak256, { sortPairs: true });
    const leaf = hashLeaf(twitterId, amount);
    return merkleTree.getHexProof(leaf);
}

export async function getClaimSignature(signerAddress: any, campaignId: number, twitterId: string, amount: number, recipient: string, proof: string[]) {
    const message = ethers.solidityPackedKeccak256(
        ['uint256', 'address', 'uint256', 'bytes32[]'],
        [campaignId, recipient, amount, proof]
    );

    const messageBytes = ethers.getBytes(message);
    const signature = await signerAddress.signMessage(messageBytes);
    return signature;
}

export async function getMerkleRoot() {
    const leaves = winners.map((winner) => hashLeaf(winner.twitterId, winner.amount));
    const merkleTree = new MerkleTree(leaves, keccak256, { sortPairs: true });
    return merkleTree.getHexRoot();
}

export async function getSettleSignature(signerAddress: any, campaignId: number, merkleRoot: bytes32, totalPoints: number, totalBudget: number) {
    // Generate signature
    const message = ethers.solidityPackedKeccak256(
        ['uint256', 'bytes32', 'uint256', 'uint256'],
        [
            campaignId,
            merkleRoot,
            totalPoints,
            totalBudget,
        ]
    );

    const messageBytes = ethers.getBytes(message);
    const signature = await signerAddress.signMessage(messageBytes);
    return signature;
}

export async function getCancelSignature(signerAddress: any, campaignId: number) {
    const message = ethers.solidityPackedKeccak256(
        ['uint256'],
        [campaignId]
    );

    const messageBytes = ethers.getBytes(message);
    const signature = await signerAddress.signMessage(messageBytes);
    return signature;
}