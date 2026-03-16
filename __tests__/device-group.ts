import { Blockchain, internal } from "@ton/sandbox";
import { beginCell, contractAddress, toNano } from "@ton/core";
import { DeviceGroup, storeDeployConfig } from "../output/DeviceGroup_DeviceGroup";

describe("DeviceGroup contract", () => {
    let blockchain: Blockchain;
    let deployer: Awaited<ReturnType<Blockchain["treasury"]>>;

    beforeAll(async () => {
        blockchain = await Blockchain.create();
        deployer = await blockchain.treasury("deployer");
    });

    it("should derive different addresses for different deployment indexes", async () => {
        const init0 = await DeviceGroup.init(deployer.address, 0n);
        const init1 = await DeviceGroup.init(deployer.address, 1n);

        expect(contractAddress(0, init0).toRawString()).not.toBe(contractAddress(0, init1).toRawString());
    });

    it("should apply name and elector from deploy payload", async () => {
        const init = await DeviceGroup.init(deployer.address, 0n);
        const groupAddress = contractAddress(0, init);

        await blockchain.sendMessage(
            internal({
                from: deployer.address,
                to: groupAddress,
                value: toNano("2"),
                stateInit: init,
                body: beginCell()
                    .store(
                        storeDeployConfig({
                            $$type: "DeployConfig",
                            name: "Test Device Group",
                            elector: deployer.address,
                        }),
                    )
                    .endCell(),
            }),
        );

        const group = blockchain.openContract(new DeviceGroup(groupAddress, init));
        expect((await group.getOwner()).toRawString()).toBe(deployer.address.toRawString());
        expect(await group.getGetName()).toBe("Test Device Group");
    });
});
