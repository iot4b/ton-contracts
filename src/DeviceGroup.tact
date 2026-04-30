import "./Device";
import "./lib/Errors";
import "./lib/Messages";
import "./lib/SignedExternal";

message GroupInit {
    name: String;
}

message SetDevice {
    addr: Address;
}

message RemoveDevice {
    addr: Address;
}

message DeployDevice {
    devicePublicKey: Int as uint256;
    name: String;
    dtype: String;
    version: String;
    deviceAPI: Address;
    vendor: Address;
    vendorData: String;
    stat: Bool;
    events: Bool;
    amount: Int as uint128;
}

struct DeviceGroupData {
    walletPublicKey: Int;
    deploymentIndex: Int as uint32;
    name: String;
    elector: Address;
    devices: map<Address, Bool>;
}

contract DeviceGroup with SignedExternal {
    walletPublicKey: Int as uint256;
    seqno: Int as uint64;

    deploymentIndex: Int as uint32;
    name: String;
    elector: Address;
    devices: map<Address, Bool>;

    init(walletPublicKey: Int as uint256, elector: Address, deploymentIndex: Int) {
        self.walletPublicKey = walletPublicKey;
        self.seqno = 0;
        self.deploymentIndex = deploymentIndex;
        self.name = "";
        self.elector = elector;
        self.devices = emptyMap();
    }

    get fun data(): DeviceGroupData {
        return DeviceGroupData {
            walletPublicKey: self.walletPublicKey,
            deploymentIndex: self.deploymentIndex,
            name: self.name,
            elector: self.elector,
            devices: self.devices,
        };
    }

    get fun nextSeqno(): Int {
        return self.seqno + 1;
    }

    fun requireDevice() {
        throwUnless(TactExitCodeAccessDenied, self.devices.exists(sender()));
    }

    fun requireElector() {
        throwUnless(TactExitCodeAccessDenied, sender() == self.elector);
    }

    fun setName(name: String) {
        throwIf(ErrorEmptyName, name == "");
        self.name = name;
    }

    fun setDevice(addr: Address) {
        self.devices.set(addr, true);
    }

    fun removeDevice(addr: Address) {
        self.devices.del(addr);
    }

    fun sendTon(dest: Address, amount: Int) {
        send(SendParameters {
            to: dest,
            value: amount,
            bounce: true,
            mode: SendDefaultMode,
        });
    }

    fun deployDevice(
        devicePublicKey: Int,
        name: String,
        dtype: String,
        version: String,
        deviceAPI: Address,
        vendor: Address,
        vendorData: String,
        stat: Bool,
        events: Bool,
        amount: Int,
    ) {
        let init = initOf Device(devicePublicKey, self.walletPublicKey);
        let deviceAddress = contractAddress(init);

        deploy(DeployParameters {
            init,
            body: DeviceInit {
                group: myAddress(),
                name,
                dtype,
                version,
                elector: self.elector,
                vendor,
                vendorData,
                stat,
                events,
            }.toCell(),
            value: amount,
            bounce: false,
            mode: SendIgnoreErrors,
        });

        self.devices.set(deviceAddress, true);
    }

    override fun checkAuth(msg: SignedMessage) {
        throwUnless(self.ErrorCommandExpired, msg.validUntil >= now());
        throwUnless(TactExitCodeAccessDenied, msg.publicKey == self.walletPublicKey);
        throwUnless(self.ErrorInvalidSeqno, msg.seqno == self.nextSeqno());
    }

    override fun commitSeqno(msg: SignedMessage) {
        self.seqno = msg.seqno;
    }

    override fun dispatchSignedMessage(message: Cell) {
        let s = message.beginParse();
        let op = s.loadUint(32);

        if (op == SetName.opcode()) {
            let msg = SetName.fromCell(message);
            self.setName(msg.name);
            return;
        }
        if (op == SetDevice.opcode()) {
            let msg = SetDevice.fromCell(message);
            self.setDevice(msg.addr);
            return;
        }
        if (op == RemoveDevice.opcode()) {
            let msg = RemoveDevice.fromCell(message);
            self.removeDevice(msg.addr);
            return;
        }
        if (op == SendTon.opcode()) {
            let msg = SendTon.fromCell(message);
            self.sendTon(msg.dest, msg.amount);
            return;
        }
        if (op == DeployDevice.opcode()) {
            let msg = DeployDevice.fromCell(message);
            self.deployDevice(
                msg.devicePublicKey,
                msg.name,
                msg.dtype,
                msg.version,
                msg.deviceAPI,
                msg.vendor,
                msg.vendorData,
                msg.stat,
                msg.events,
                msg.amount,
            );
            return;
        }

        throw(self.ErrorUnsupportedSignedMessage);
    }

    receive(msg: GroupInit) {
        throwUnless(ErrorAlreadyConfigured, self.name == "");
        self.setName(msg.name);
    }

    receive(msg: GroupEvent) {
        self.requireDevice();
        emit(msg.toCell());
    }

    receive(msg: SendTonToDevice) {
        self.requireDevice();
        self.sendTon(msg.dest, msg.amount);
    }

    receive(msg: SendTonToElector) {
        self.requireElector();
        send(SendParameters {
            to: self.elector,
            value: msg.amount,
            bounce: true,
            mode: SendDefaultMode,
        });
    }

    receive(msg: Slice) {}
}
