import { Blockchain, SandboxContract, TreasuryContract, internal } from "@ton/sandbox";
import { beginCell, contractAddress, external, toNano } from "@ton/core";
import { keyPairFromSeed, sign } from "@ton/crypto";
import { Device } from "../output/Device_Device";
import {
    DeviceGroup,
    storeDeployDevice,
    storeSendTon,
    storeSetName,
    storeSignedMessage,
} from "../output/DeviceGroup_DeviceGroup";

describe("DeviceGroup contract", () => {
    let blockchain: Blockchain;
    let elector: SandboxContract<TreasuryContract>;
    let vendor: SandboxContract<TreasuryContract>;
    let deviceAPI: SandboxContract<TreasuryContract>;

    const walletKeyPair = keyPairFromSeed(Buffer.alloc(32, 7));
    const outsiderKeyPair = keyPairFromSeed(Buffer.alloc(32, 8));
    const walletPublicKey = BigInt(`0x${walletKeyPair.publicKey.toString("hex")}`);
    const outsiderPublicKey = BigInt(`0x${outsiderKeyPair.publicKey.toString("hex")}`);

    function signedMessage(
        groupAddress: any,
        publicKey: bigint,
        secretKey: Buffer,
        seqno: bigint,
        message: any,
        validUntil = 2_000n,
    ) {
        const hash = beginCell()
            .storeAddress(groupAddress)
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

    function signedExternalMessage(groupAddress: any, message: ReturnType<typeof signedMessage>) {
        return external({
            to: groupAddress,
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

    async function deployGroup(deploymentIndex: bigint) {
        const init = await DeviceGroup.init(walletPublicKey, elector.address, deploymentIndex);
        const address = contractAddress(0, init);

        await blockchain.sendMessage(
            internal({
                from: elector.address,
                to: address,
                value: toNano("2"),
                stateInit: init,
                body: beginCell()
                    .storeUint(2645384235, 32)
                    .storeRef(beginCell().storeStringTail("Test Device Group").endCell())
                    .endCell(),
            }),
        );

        return blockchain.openContract(new DeviceGroup(address, init));
    }

    beforeEach(async () => {
        blockchain = await Blockchain.create();
        blockchain.now = 1_000;
        elector = await blockchain.treasury("elector");
        vendor = await blockchain.treasury("vendor");
        deviceAPI = await blockchain.treasury("device-api");
    });

    it("should derive different addresses for different deployment indexes", async () => {
        const init0 = await DeviceGroup.init(walletPublicKey, elector.address, 0n);
        const init1 = await DeviceGroup.init(walletPublicKey, elector.address, 1n);
        expect(contractAddress(0, init0).toRawString()).not.toBe(contractAddress(0, init1).toRawString());
    });

    it("should expose walletPublicKey, deployment index, name and elector from get()", async () => {
        const group = await deployGroup(7n);
        const data = await group.getData();
        expect(data.walletPublicKey).toBe(walletPublicKey);
        expect(data.deploymentIndex).toBe(7n);
        expect(data.name).toBe("Test Device Group");
        expect(data.elector.toRawString()).toBe(elector.address.toRawString());
        expect(data.devices.size).toBe(0);
        expect(await group.getNextSeqno()).toBe(1n);
    });

    it("should execute signed external group commands and deploy a configured Device", async () => {
        const group = await deployGroup(0n);
        const devicePublicKey = 777n;

        const setName = beginCell()
            .store(storeSetName({ $$type: "SetName", name: "Renamed Group" }))
            .endCell();
        await blockchain.sendMessage(
            signedExternalMessage(
                group.address,
                signedMessage(group.address, walletPublicKey, walletKeyPair.secretKey, 1n, setName),
            ),
        );

        const deployDevice = beginCell()
            .store(
                storeDeployDevice({
                    $$type: "DeployDevice",
                    devicePublicKey,
                    name: "Thermostat",
                    dtype: "sensor",
                    version: "3.2.1",
                    deviceAPI: deviceAPI.address,
                    vendor: vendor.address,
                    vendorData: '{"batch":"A-17"}',
                    stat: true,
                    events: false,
                    amount: toNano("0.7"),
                }),
            )
            .endCell();
        await blockchain.sendMessage(
            signedExternalMessage(
                group.address,
                signedMessage(group.address, walletPublicKey, walletKeyPair.secretKey, 2n, deployDevice),
            ),
        );

        const expectedDeviceInit = await Device.init(devicePublicKey, walletPublicKey);
        const expectedDeviceAddress = contractAddress(0, expectedDeviceInit);

        const groupData = await group.getData();
        expect(groupData.name).toBe("Renamed Group");
        expect(
            [...groupData.devices.keys()].some((addr) => addr.toRawString() === expectedDeviceAddress.toRawString()),
        ).toBe(true);
        expect(await group.getNextSeqno()).toBe(3n);

        const device = blockchain.openContract(new Device(expectedDeviceAddress, expectedDeviceInit));
        const deviceData = await device.getData();
        expect(deviceData.devicePublicKey).toBe(devicePublicKey);
        expect(deviceData.walletPublicKey).toBe(walletPublicKey);
        expect(deviceData.group?.toRawString()).toBe(group.address.toRawString());
        expect(deviceData.name).toBe("Thermostat");
        expect(deviceData.dtype).toBe("sensor");
    });

    it("should allow walletPublicKey to send TON through signed external SendTon", async () => {
        const group = await deployGroup(0n);
        const recipient = await blockchain.treasury("send-ton-recipient");
        const before = (await recipient.getBalance()).toString();

        const sendTon = beginCell()
            .store(
                storeSendTon({
                    $$type: "SendTon",
                    dest: recipient.address,
                    amount: toNano("0.2"),
                }),
            )
            .endCell();

        await blockchain.sendMessage(
            signedExternalMessage(
                group.address,
                signedMessage(group.address, walletPublicKey, walletKeyPair.secretKey, 1n, sendTon),
            ),
        );

        const after = (await recipient.getBalance()).toString();
        expect(BigInt(after)).toBeGreaterThan(BigInt(before));
        expect(await group.getNextSeqno()).toBe(2n);
    });

    it("should reject invalid group signatures, replays, and unknown signers", async () => {
        const group = await deployGroup(0n);
        const setName = beginCell()
            .store(storeSetName({ $$type: "SetName", name: "Renamed Group" }))
            .endCell();

        await sendIgnoringReject(
            signedExternalMessage(
                group.address,
                signedMessage(group.address, walletPublicKey, outsiderKeyPair.secretKey, 1n, setName),
            ),
        );
        await sendIgnoringReject(
            signedExternalMessage(
                group.address,
                signedMessage(group.address, outsiderPublicKey, outsiderKeyPair.secretKey, 1n, setName),
            ),
        );

        const good = signedMessage(group.address, walletPublicKey, walletKeyPair.secretKey, 1n, setName);
        await sendIgnoringReject(signedExternalMessage(group.address, good));
        await sendIgnoringReject(signedExternalMessage(group.address, good));

        const data = await group.getData();
        expect(data.name).toBe("Renamed Group");
        expect(await group.getNextSeqno()).toBe(2n);
    });

    it("should reject empty group name", async () => {
        const group = await deployGroup(0n);
        const setName = beginCell()
            .store(storeSetName({ $$type: "SetName", name: "" }))
            .endCell();

        await sendIgnoringReject(
            signedExternalMessage(
                group.address,
                signedMessage(group.address, walletPublicKey, walletKeyPair.secretKey, 1n, setName),
            ),
        );

        expect((await group.getData()).name).toBe("Test Device Group");
        expect(await group.getNextSeqno()).toBe(1n);
    });
});
