/**
 * Elector contract tests — TON network (using @ton/sandbox and Tact-generated wrappers).
 * Adapted from Everscale Locklift tests.
 */
import { Blockchain, internal } from "@ton/sandbox";
import { Address, contractAddress, Dictionary, toNano } from "@ton/core";
import { Elector } from "../output/Elector_Elector";

describe("Elector contract", () => {
    let blockchain: Blockchain;
    let deployer: Awaited<ReturnType<Blockchain["treasury"]>>;
    let electorContract: ReturnType<typeof blockchain.openContract<Elector>>;
    let electorAddress: Address;

    beforeAll(async () => {
        blockchain = await Blockchain.create();
        deployer = await blockchain.treasury("deployer");
    });

    it("should deploy contract", async () => {
        const defaultNodes = Dictionary.empty(Dictionary.Keys.Address(), Dictionary.Values.Bool());
        const init = await Elector.init(deployer.address, defaultNodes);
        electorAddress = contractAddress(0, init);
        await blockchain.sendMessage(
            internal({
                from: deployer.address,
                to: electorAddress,
                value: toNano("2"),
                stateInit: init,
            }),
        );
        electorContract = blockchain.openContract(new Elector(electorAddress, init));
        const nodesCurrent = await electorContract.getGetNodesCurrent();
        expect(nodesCurrent.size).toBe(0);
    });

    it("should set nodes for elector", async () => {
        const nodes = Dictionary.empty(Dictionary.Keys.Address(), Dictionary.Values.Bool());
        nodes.set(Address.parse("0:4a2158bd934f0f199224b89dd58f8b20ad73a160ef06ca67d55a63fc8d4b0a26"), true);
        nodes.set(Address.parse("0:86429800dd5b8ddc9a1283341b106cdb7acb2807c4e5f91e523c2803e6c76ddd"), true);
        nodes.set(Address.parse("0:e986b8305e5d46cc221cc9e14785bfe361b8558104396bdc082fa4c6321ffc68"), true);

        await electorContract.send(deployer.getSender(), { value: toNano("0.01") }, { $$type: "SetNodes", nodes });

        const responseCheck = await electorContract.getGetNodesCurrent();
        expect(responseCheck.size).toBeGreaterThan(0);
    });

    it("should set participantList for elector (takeNextRound)", async () => {
        const nodeAddr = Address.parse("0:4a2158bd934f0f199224b89dd58f8b20ad73a160ef06ca67d55a63fc8d4b0a26");
        await electorContract.send(
            deployer.getSender(),
            { value: toNano("0.01") },
            { $$type: "TakeNextRound", addr: nodeAddr },
        );

        const responseCheck = await electorContract.getGetNodesParticipants();
        expect(responseCheck.size).toBeGreaterThan(0);
    });

    it("should run election and clear participants", async () => {
        const nodeAddr = Address.parse("0:4a2158bd934f0f199224b89dd58f8b20ad73a160ef06ca67d55a63fc8d4b0a26");
        await electorContract.send(
            deployer.getSender(),
            { value: toNano("0.01") },
            { $$type: "TakeNextRound", addr: nodeAddr },
        );
        await electorContract.send(deployer.getSender(), { value: toNano("0.01") }, { $$type: "Election" });

        const responseAfter = await electorContract.getGetNodesParticipants();
        expect(responseAfter.size).toBe(0);
    });
});
