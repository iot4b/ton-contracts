import { Blockchain, SandboxContract, TreasuryContract, internal } from "@ton/sandbox";
import { Address, beginCell, contractAddress, external, toNano } from "@ton/core";
import { keyPairFromSeed, sign } from "@ton/crypto";
import {
    Device,
    storeDeviceEvent,
    storeRemoveOwner,
    storeSetLock,
    storeSetName,
    storeSetOwner,
    storeSignedMessage,
} from "../output/Device_Device";

describe("Device contract", () => {
    let blockchain: Blockchain;
    let group: SandboxContract<TreasuryContract>;
    let outsider: SandboxContract<TreasuryContract>;
    let elector: SandboxContract<TreasuryContract>;
    let vendor: SandboxContract<TreasuryContract>;
    let deviceAPI: SandboxContract<TreasuryContract>;
    let node: SandboxContract<TreasuryContract>;

    const deviceKeyPair = keyPairFromSeed(Buffer.alloc(32, 1));
    const walletKeyPair = keyPairFromSeed(Buffer.alloc(32, 2));
    const ownerKeyPair = keyPairFromSeed(Buffer.alloc(32, 3));
    const outsiderKeyPair = keyPairFromSeed(Buffer.alloc(32, 4));
    const devicePublicKey = BigInt(`0x${deviceKeyPair.publicKey.toString("hex")}`);
    const walletPublicKey = BigInt(`0x${walletKeyPair.publicKey.toString("hex")}`);
    const ownerPublicKey = BigInt(`0x${ownerKeyPair.publicKey.toString("hex")}`);
    const outsiderPublicKey = BigInt(`0x${outsiderKeyPair.publicKey.toString("hex")}`);

    function label(value: any) {
        return value?.beginParse().loadStringTail();
    }

    function rawAddress(value: Address | null | undefined) {
        return value?.toRawString();
    }

    function signedMessage(
        deviceAddress: Address,
        publicKey: bigint,
        secretKey: Buffer,
        seqno: bigint,
        message: any,
        validUntil = 2_000n,
    ) {
        const hash = beginCell()
            .storeAddress(deviceAddress)
            .storeUint(publicKey, 256)
            .storeRef(
                beginCell()
                    .storeUint(seqno, 64)
                    .storeUint(validUntil, 32)
                    .storeUint(BigInt(`0x${message.hash().toString("hex")}`), 256)
                    .endCell(),
            )
            .endCell()
            .hash();

        return {
            $$type: "SignedMessage" as const,
            publicKey,
            seqno,
            validUntil,
            message,
            signature: sign(hash, secretKey),
        };
    }

    function signedExternalMessage(deviceAddress: Address, message: ReturnType<typeof signedMessage>) {
        return external({
            to: deviceAddress,
            body: beginCell().store(storeSignedMessage(message)).endCell(),
        });
    }

    async function sendIgnoringReject(message: ReturnType<typeof signedExternalMessage>) {
        try {
            await blockchain.sendMessage(message);
        } catch {
            // Pre-accept rejections surface as thrown errors in sandbox.
        }
    }

    async function deployDevice() {
        const init = await Device.init(devicePublicKey, walletPublicKey);
        const address = contractAddress(0, init);

        await blockchain.sendMessage(
            internal({
                from: group.address,
                to: address,
                value: toNano("1.5"),
                stateInit: init,
            }),
        );

        return blockchain.openContract(new Device(address, init));
    }

    async function initDevice(device: SandboxContract<Device>) {
        await device.send(
            group.getSender(),
            { value: toNano("0.5") },
            {
                $$type: "DeviceInit",
                group: group.address,
                name: "Weather Sensor",
                dtype: "sensor",
                version: "1.0.0",
                elector: elector.address,
                vendor: vendor.address,
                vendorData: '{"sku":"WS-1"}',
                stat: false,
                events: false,
            },
        );
    }

    beforeEach(async () => {
        blockchain = await Blockchain.create();
        blockchain.now = 1_000;
        group = await blockchain.treasury("group");
        outsider = await blockchain.treasury("outsider");
        elector = await blockchain.treasury("elector");
        vendor = await blockchain.treasury("vendor");
        deviceAPI = await blockchain.treasury("device-api");
        node = await blockchain.treasury("node");
    });

    it("should expose default key-only storage right after deploy", async () => {
        const device = await deployDevice();
        const data = await device.getData();

        expect(data.devicePublicKey).toBe(devicePublicKey);
        expect(data.walletPublicKey).toBe(walletPublicKey);
        expect(data.ownerPublicKeys.size).toBe(0);
        expect(data.group).toBeNull();
        expect(await device.getNode()).toBeNull();
        expect(await device.getNextSeqno(walletPublicKey)).toBe(1n);
        expect(await device.getNextSeqno(devicePublicKey)).toBe(1n);
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

        expect((await device.getData()).group).toBeNull();

        await initDevice(device);
        const data = await device.getData();

        expect(rawAddress(data.group)).toBe(group.address.toRawString());
        expect(data.name).toBe("Weather Sensor");
        expect(data.dtype).toBe("sensor");
        expect(data.version).toBe("1.0.0");
        expect(rawAddress(data.elector)).toBe(elector.address.toRawString());
        expect(rawAddress(data.vendor)).toBe(vendor.address.toRawString());
    });

    it("should execute runtime commands through the external signed path for wallet, extra owner, and device keys", async () => {
        const device = await deployDevice();
        await initDevice(device);

        const addOwner = beginCell()
            .store(storeSetOwner({ $$type: "SetOwner", publicKey: ownerPublicKey, name: "Alice" }))
            .endCell();
        await blockchain.sendMessage(
            signedExternalMessage(
                device.address,
                signedMessage(device.address, walletPublicKey, walletKeyPair.secretKey, 1n, addOwner),
            ),
        );

        let data = await device.getData();
        expect(label(data.ownerPublicKeys.get(ownerPublicKey))).toBe("Alice");
        expect(await device.getNextSeqno(walletPublicKey)).toBe(2n);

        const setName = beginCell()
            .store(storeSetName({ $$type: "SetName", name: "Signed Name" }))
            .endCell();
        await blockchain.sendMessage(
            signedExternalMessage(
                device.address,
                signedMessage(device.address, ownerPublicKey, ownerKeyPair.secretKey, 1n, setName),
            ),
        );

        const setDeviceApi = beginCell().storeUint(3335294981, 32).storeAddress(deviceAPI.address).endCell();
        await blockchain.sendMessage(
            signedExternalMessage(
                device.address,
                signedMessage(device.address, devicePublicKey, deviceKeyPair.secretKey, 1n, setDeviceApi),
            ),
        );

        const setLock = beginCell()
            .store(storeSetLock({ $$type: "SetLock", value: true }))
            .endCell();
        await blockchain.sendMessage(
            signedExternalMessage(
                device.address,
                signedMessage(device.address, ownerPublicKey, ownerKeyPair.secretKey, 2n, setLock),
            ),
        );

        const event = beginCell()
            .store(storeDeviceEvent({ $$type: "DeviceEvent", name: "temp", data: "21" }))
            .endCell();
        await blockchain.sendMessage(
            signedExternalMessage(
                device.address,
                signedMessage(device.address, devicePublicKey, deviceKeyPair.secretKey, 2n, event),
            ),
        );

        data = await device.getData();
        expect(data.name).toBe("Signed Name");
        expect(rawAddress(data.deviceAPI)).toBe(deviceAPI.address.toRawString());
        expect(data.lock).toBe(true);
        expect(await device.getNextSeqno(ownerPublicKey)).toBe(3n);
        expect(await device.getNextSeqno(devicePublicKey)).toBe(3n);
    });

    it("should reject removing walletPublicKey or devicePublicKey through owner management", async () => {
        const device = await deployDevice();
        await initDevice(device);

        const removeWallet = beginCell()
            .store(storeRemoveOwner({ $$type: "RemoveOwner", publicKey: walletPublicKey }))
            .endCell();
        await sendIgnoringReject(
            signedExternalMessage(
                device.address,
                signedMessage(device.address, walletPublicKey, walletKeyPair.secretKey, 1n, removeWallet),
            ),
        );

        const removeDevice = beginCell()
            .store(storeRemoveOwner({ $$type: "RemoveOwner", publicKey: devicePublicKey }))
            .endCell();
        await sendIgnoringReject(
            signedExternalMessage(
                device.address,
                signedMessage(device.address, walletPublicKey, walletKeyPair.secretKey, 2n, removeDevice),
            ),
        );

        const data = await device.getData();
        expect(data.devicePublicKey).toBe(devicePublicKey);
        expect(data.walletPublicKey).toBe(walletPublicKey);
        expect(data.ownerPublicKeys.size).toBe(0);
    });

    it("should reject invalid signature, expired command, replay, unknown signer, and unknown opcode", async () => {
        const device = await deployDevice();
        await initDevice(device);

        const setLock = beginCell()
            .store(storeSetLock({ $$type: "SetLock", value: true }))
            .endCell();

        await sendIgnoringReject(
            signedExternalMessage(
                device.address,
                signedMessage(device.address, walletPublicKey, outsiderKeyPair.secretKey, 1n, setLock),
            ),
        );
        await sendIgnoringReject(
            signedExternalMessage(
                device.address,
                signedMessage(device.address, walletPublicKey, walletKeyPair.secretKey, 1n, setLock, 900n),
            ),
        );
        await sendIgnoringReject(
            signedExternalMessage(
                device.address,
                signedMessage(device.address, outsiderPublicKey, outsiderKeyPair.secretKey, 1n, setLock),
            ),
        );

        const good = signedMessage(device.address, walletPublicKey, walletKeyPair.secretKey, 1n, setLock);
        await blockchain.sendMessage(signedExternalMessage(device.address, good));
        await sendIgnoringReject(signedExternalMessage(device.address, good));

        const unknown = beginCell().storeUint(0xffffffff, 32).endCell();
        await sendIgnoringReject(
            signedExternalMessage(
                device.address,
                signedMessage(device.address, walletPublicKey, walletKeyPair.secretKey, 2n, unknown),
            ),
        );

        const data = await device.getData();
        expect(data.lock).toBe(true);
        expect(await device.getNextSeqno(walletPublicKey)).toBe(2n);
    });

    it("should keep the direct SetNode receiver behavior unchanged", async () => {
        const device = await deployDevice();
        await initDevice(device);

        await device.send(outsider.getSender(), { value: toNano("0.3") }, { $$type: "SetNode", node: node.address });

        const data = await device.getData();
        expect(rawAddress(data.node)).toBe(node.address.toRawString());
        expect(rawAddress(await device.getNode())).toBe(node.address.toRawString());
        expect(data.lastRegisterTime).toBeGreaterThan(0n);
    });

    it("should reject empty device name", async () => {
        const device = await deployDevice();
        await initDevice(device);

        const setName = beginCell()
            .store(storeSetName({ $$type: "SetName", name: "" }))
            .endCell();

        await sendIgnoringReject(
            signedExternalMessage(
                device.address,
                signedMessage(device.address, walletPublicKey, walletKeyPair.secretKey, 1n, setName),
            ),
        );

        expect((await device.getData()).name).toBe("Weather Sensor");
        expect(await device.getNextSeqno(walletPublicKey)).toBe(1n);
    });
});
