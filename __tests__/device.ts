import { Blockchain, SandboxContract, TreasuryContract, internal } from "@ton/sandbox";
import { contractAddress, toNano } from "@ton/core";
import { Device } from "../output/Device_Device";

describe("Device contract", () => {
    let blockchain: Blockchain;
    let group: SandboxContract<TreasuryContract>;
    let outsider: SandboxContract<TreasuryContract>;
    let elector: SandboxContract<TreasuryContract>;
    let vendor: SandboxContract<TreasuryContract>;
    let node: SandboxContract<TreasuryContract>;

    const publicKey = 123n;

    async function deployDevice() {
        const init = await Device.init(publicKey);
        const address = contractAddress(0, init);

        await blockchain.sendMessage(
            internal({
                from: group.address,
                to: address,
                value: toNano("0.2"),
                stateInit: init,
            }),
        );

        return blockchain.openContract(new Device(address, init));
    }

    beforeEach(async () => {
        blockchain = await Blockchain.create();
        group = await blockchain.treasury("group");
        outsider = await blockchain.treasury("outsider");
        elector = await blockchain.treasury("elector");
        vendor = await blockchain.treasury("vendor");
        node = await blockchain.treasury("node");
    });

    it("should expose default storage right after deploy", async () => {
        const device = await deployDevice();

        const data = await device.getGet();

        expect(data.owners.get(publicKey)).toBe(true);
        expect(data.name).toBe("");
        expect(data.dtype).toBe("");
        expect(data.version).toBe("");
        expect(data.lastRegisterTime).toBe(0n);
        expect(data.group).toBeNull();
        expect(data.node).toBeNull();
        expect(data.elector).toBeNull();
        expect(data.vendor).toBeNull();
        expect(data.vendorData).toBe("");
        expect(data.lock).toBe(false);
        expect(data.stat).toBe(false);
        expect(data.events).toBe(false);
    });

    it("should accept DeviceInit only from the configured group and persist metadata", async () => {
        const device = await deployDevice();

        await device.send(
            outsider.getSender(),
            { value: toNano("0.1") },
            {
                $$type: "DeviceInit",
                group: group.address,
                name: "Weather Sensor",
                dtype: "sensor",
                version: "1.0.0",
                elector: elector.address,
                vendor: vendor.address,
                vendorData: '{"sku":"WS-1"}',
                stat: true,
                events: true,
            },
        );

        const dataAfterRejectedInit = await device.getGet();
        expect(dataAfterRejectedInit.group).toBeNull();
        expect(dataAfterRejectedInit.name).toBe("");

        await device.send(
            group.getSender(),
            { value: toNano("0.1") },
            {
                $$type: "DeviceInit",
                group: group.address,
                name: "Weather Sensor",
                dtype: "sensor",
                version: "1.0.0",
                elector: elector.address,
                vendor: vendor.address,
                vendorData: '{"sku":"WS-1"}',
                stat: true,
                events: true,
            },
        );

        const data = await device.getGet();

        expect(data.group?.toRawString()).toBe(group.address.toRawString());
        expect(data.elector?.toRawString()).toBe(elector.address.toRawString());
        expect(data.vendor?.toRawString()).toBe(vendor.address.toRawString());
        expect(data.name).toBe("Weather Sensor");
        expect(data.dtype).toBe("sensor");
        expect(data.version).toBe("1.0.0");
        expect(data.vendorData).toBe('{"sku":"WS-1"}');
        expect(data.stat).toBe(true);
        expect(data.events).toBe(true);
    });

    it("should allow only the group to update operational flags and node", async () => {
        const device = await deployDevice();

        await device.send(
            group.getSender(),
            { value: toNano("0.1") },
            {
                $$type: "DeviceInit",
                group: group.address,
                name: "Device A",
                dtype: "meter",
                version: "2.1.0",
                elector: elector.address,
                vendor: vendor.address,
                vendorData: "vendor-meta",
                stat: false,
                events: false,
            },
        );

        await device.send(outsider.getSender(), { value: toNano("0.1") }, { $$type: "SetLock", value: true });

        const dataAfterRejectedLock = await device.getGet();
        expect(dataAfterRejectedLock.lock).toBe(false);

        await device.send(group.getSender(), { value: toNano("0.2") }, { $$type: "SetLock", value: true });
        await device.send(group.getSender(), { value: toNano("0.2") }, { $$type: "SetStat", value: true });
        await device.send(group.getSender(), { value: toNano("0.2") }, { $$type: "SetEvents", value: true });
        await device.send(group.getSender(), { value: toNano("0.2") }, { $$type: "SetName", name: "Renamed Device" });
        await device.send(group.getSender(), { value: toNano("0.3") }, { $$type: "SetNode", node: node.address });

        const data = await device.getGet();

        expect(data.lock).toBe(true);
        expect(data.stat).toBe(true);
        expect(data.events).toBe(true);
        expect(data.name).toBe("Renamed Device");
        expect(data.node?.toRawString()).toBe(node.address.toRawString());
        expect(data.lastRegisterTime).toBeGreaterThan(0n);
    });
});
