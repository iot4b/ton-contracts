import { Blockchain, SandboxContract, TreasuryContract, internal } from "@ton/sandbox";
import { beginCell, contractAddress, toNano } from "@ton/core";
import { Device } from "../output/Device_Device";
import { DeviceGroup, storeGroupInit } from "../output/DeviceGroup_DeviceGroup";

describe("DeviceGroup contract", () => {
    let blockchain: Blockchain;
    let owner: SandboxContract<TreasuryContract>;
    let elector: SandboxContract<TreasuryContract>;
    let vendor: SandboxContract<TreasuryContract>;
    let deviceAPI: SandboxContract<TreasuryContract>;

    async function deployGroup(deploymentIndex: bigint) {
        const init = await DeviceGroup.init(owner.address, deploymentIndex);
        const address = contractAddress(0, init);

        await blockchain.sendMessage(
            internal({
                from: owner.address,
                to: address,
                value: toNano("2"),
                stateInit: init,
                body: beginCell()
                    .store(
                        storeGroupInit({
                            $$type: "GroupInit",
                            name: "Test Device Group",
                            elector: elector.address,
                        }),
                    )
                    .endCell(),
            }),
        );

        return blockchain.openContract(new DeviceGroup(address, init));
    }

    beforeEach(async () => {
        blockchain = await Blockchain.create();
        owner = await blockchain.treasury("owner");
        elector = await blockchain.treasury("elector");
        vendor = await blockchain.treasury("vendor");
        deviceAPI = await blockchain.treasury("device-api");
    });

    it("should derive different addresses for different deployment indexes", async () => {
        const init0 = await DeviceGroup.init(owner.address, 0n);
        const init1 = await DeviceGroup.init(owner.address, 1n);

        expect(contractAddress(0, init0).toRawString()).not.toBe(contractAddress(0, init1).toRawString());
    });

    it("should expose owner, deployment index, name and elector from get()", async () => {
        const group = await deployGroup(7n);

        expect((await group.getOwner()).toRawString()).toBe(owner.address.toRawString());

        const data = await group.getGet();
        expect(data.owner.toRawString()).toBe(owner.address.toRawString());
        expect(data.deploymentIndex).toBe(7n);
        expect(data.name).toBe("Test Device Group");
        expect(data.elector?.toRawString()).toBe(elector.address.toRawString());
        expect(data.devices.size).toBe(0);
    });

    it("should deploy a configured Device and register it in the devices map", async () => {
        const group = await deployGroup(0n);
        const publicKey = 777n;

        const expectedDeviceInit = await Device.init(publicKey);
        const expectedDeviceAddress = contractAddress(0, expectedDeviceInit);

        await group.send(
            owner.getSender(),
            { value: toNano("1.5") },
            {
                $$type: "DeployDevice",
                publicKey,
                name: "Thermostat",
                dtype: "sensor",
                version: "3.2.1",
                deviceAPI: deviceAPI.address,
                vendor: vendor.address,
                vendorData: '{"batch":"A-17"}',
                stat: true,
                events: false,
                amount: toNano("0.7"),
            },
        );

        const groupData = await group.getGet();
        expect(groupData.devices.get(expectedDeviceAddress)).toBe(true);

        const device = blockchain.openContract(new Device(expectedDeviceAddress, expectedDeviceInit));
        const deviceData = await device.getGet();

        expect(deviceData.group?.toRawString()).toBe(group.address.toRawString());
        expect(deviceData.name).toBe("Thermostat");
        expect(deviceData.dtype).toBe("sensor");
        expect(deviceData.version).toBe("3.2.1");
        expect(deviceData.elector?.toRawString()).toBe(elector.address.toRawString());
        expect(deviceData.vendor?.toRawString()).toBe(vendor.address.toRawString());
        expect(deviceData.vendorData).toBe('{"batch":"A-17"}');
        expect(deviceData.stat).toBe(true);
        expect(deviceData.events).toBe(false);
        expect(deviceData.owners.get(publicKey)).toBe(true);
    });
});
