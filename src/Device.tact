import "./lib/Errors";
import "./lib/Messages";
import "./lib/SignedExternal";

message SetNode {
    node: Address;
}

message SetOwner {
    publicKey: Int as uint256;
    name: String;
}

message RemoveOwner {
    publicKey: Int as uint256;
}

message SetLock {
    value: Bool;
}

message SetStat {
    value: Bool;
}

message SetEvents {
    value: Bool;
}

message SetDeviceAPI {
    deviceAPI: Address;
}

message SetVendor {
    vendor: Address;
}

message DeviceEvent {
    name: String;
    data: String;
}

// Keep DeviceInit root cell within the 1023-bit / 4-ref limits when extending
// this message, otherwise device deploys will fail with cell overflow / underflow.
// The current root cell budget is about 835/1023 bits and has 4/4 refs
message DeviceInit {
    // + 32-bit opcode in root cell
    group: Address; // ~= 267 bits in root cell
    name: String; // stored in ref in current Tact layout
    dtype: String; // stored in ref in current Tact layout
    version: String; // stored in ref in current Tact layout
    elector: Address; // ~= 267 bits in root cell
    vendor: Address; // ~= 267 bits in root cell
    vendorData: String; // stored in ref in current Tact layout
    stat: Bool; // 1 bit in root cell
    events: Bool; // 1 bit in root cell
}

// NodeChange log is emitted when the node address is updated.
struct NodeChangeLog {
    contractAddress: Address;
    oldNode: Address?;
    newNode: Address;
}

// DeviceUpdate log is emitted when metadata changes.
struct DeviceUpdateLog {
    contractAddress: Address;
    newNode: Address?;
}

struct DeviceData {
    devicePublicKey: Int;
    walletPublicKey: Int;
    ownerPublicKeys: map<Int as uint256, Cell>;
    name: String;
    dtype: String;
    version: String;
    lastRegisterTime: Int;
    group: Address?;
    node: Address?;
    elector: Address?;
    deviceAPI: Address?;
    vendor: Address?;
    vendorData: String;
    lock: Bool;
    stat: Bool;
    events: Bool;
}

contract Device with SignedExternal {
    const ErrorOwnerNotFound: Int = 3001;
    const ErrorElectorNotConfigured: Int = 3002;
    const ErrorGroupNotConfigured: Int = 3003;
    const ErrorInvalidGroup: Int = 3004;
    const ErrorImmutableOwnerKey: Int = 3005;

    devicePublicKey: Int as uint256;
    walletPublicKey: Int as uint256;
    ownerPublicKeys: map<Int as uint256, Cell>;
    seqnos: map<Int as uint256, Int as uint64>;

    name: String;
    dtype: String;
    version: String;
    lastRegisterTime: Int as uint32;

    group: Address?;
    node: Address?;
    elector: Address?;
    deviceAPI: Address?;
    vendor: Address?;
    vendorData: String;

    lock: Bool;
    stat: Bool;
    events: Bool;

    init(devicePublicKey: Int as uint256, walletPublicKey: Int as uint256) {
        self.devicePublicKey = devicePublicKey;
        self.walletPublicKey = walletPublicKey;
        self.ownerPublicKeys = emptyMap();
        self.seqnos = emptyMap();
        self.name = "";
        self.dtype = "";
        self.version = "";
        self.lastRegisterTime = 0;
        self.group = null;
        self.node = null;
        self.elector = null;
        self.deviceAPI = null;
        self.vendor = null;
        self.vendorData = "";
        self.lock = false;
        self.stat = false;
        self.events = false;
    }

    get fun data(): DeviceData {
        return DeviceData {
            devicePublicKey: self.devicePublicKey,
            walletPublicKey: self.walletPublicKey,
            ownerPublicKeys: self.ownerPublicKeys,
            name: self.name,
            dtype: self.dtype,
            version: self.version,
            lastRegisterTime: self.lastRegisterTime,
            group: self.group,
            node: self.node,
            elector: self.elector,
            deviceAPI: self.deviceAPI,
            vendor: self.vendor,
            vendorData: self.vendorData,
            lock: self.lock,
            stat: self.stat,
            events: self.events,
        };
    }

    get fun node(): Address? {
        return self.node;
    }

    get fun nextSeqno(publicKey: Int): Int {
        let current = self.seqnos.get(publicKey);
        if (current == null) {
            return 1;
        }
        return current!! + 1;
    }

    fun requireTrustedKey(publicKey: Int) {
        throwUnless(
            TactExitCodeAccessDenied,
            publicKey == self.devicePublicKey ||
            publicKey == self.walletPublicKey ||
            self.ownerPublicKeys.exists(publicKey),
        );
    }

    fun topUpIfNeeded() {
        if (myBalance() < ton("1")) {
            throwUnless(self.ErrorGroupNotConfigured, self.group != null);
            send(SendParameters {
                to: self.group!!,
                value: ton("0"),
                bounce: true,
                mode: SendPayFwdFeesSeparately | SendIgnoreErrors,
                body: SendTonToDevice { dest: myAddress(), amount: ton("1") }.toCell(),
            });
        }
    }

    fun sendUpdate() {
        if (self.node != null) {
            send(SendParameters {
                to: self.node!!,
                value: ton("0.1"),
                bounce: true,
                mode: SendIgnoreErrors,
                body: DeviceUpdateEvent { device: myAddress() }.toCell(),
            });
        }
    }

    fun setOwner(publicKey: Int, name: String) {
        throwUnless(self.ErrorImmutableOwnerKey, publicKey != self.devicePublicKey && publicKey != self.walletPublicKey);
        self.ownerPublicKeys.set(publicKey, name.asSlice().asCell());
        self.sendUpdate();
    }

    fun removeOwner(publicKey: Int) {
        throwUnless(self.ErrorImmutableOwnerKey, publicKey != self.devicePublicKey && publicKey != self.walletPublicKey);
        throwUnless(self.ErrorOwnerNotFound, self.ownerPublicKeys.exists(publicKey));
        self.ownerPublicKeys.del(publicKey);
        self.seqnos.del(publicKey);
        self.sendUpdate();
    }

    fun emitDeviceEvent(name: String, data: String) {
        emit(DeviceEvent { name, data }.toCell());
        throwUnless(self.ErrorGroupNotConfigured, self.group != null);
        send(SendParameters {
            to: self.group!!,
            value: ton("0"),
            bounce: true,
            mode: SendPayFwdFeesSeparately | SendIgnoreErrors,
            body: GroupEvent { name, data }.toCell(),
        });
    }

    fun setNode(node: Address) {
        throwUnless(self.ErrorElectorNotConfigured, self.elector != null);

        let oldNode = self.node;

        send(SendParameters {
            to: self.elector!!,
            value: ton("0.1"),
            bounce: true,
            mode: SendIgnoreErrors,
            body: GetPayment { group: self.group!! }.toCell(),
        });

        send(SendParameters {
            to: node,
            value: ton("0.1"),
            bounce: true,
            mode: SendIgnoreErrors,
            body: DeviceRegisterEvent { device: myAddress(), oldnode: oldNode }.toCell(),
        });

        emit(NodeChangeLog {
            contractAddress: myAddress(),
            oldNode,
            newNode: node,
        }.toCell());

        self.node = node;
        self.lastRegisterTime = now();
    }

    fun setName(name: String) {
        throwIf(ErrorEmptyName, name == "");
        self.name = name;
        self.sendUpdate();
    }

    fun setLock(value: Bool) {
        self.lock = value;
        self.sendUpdate();
    }

    fun setStat(value: Bool) {
        self.stat = value;
        self.sendUpdate();
    }

    fun setEvents(value: Bool) {
        self.events = value;
        self.sendUpdate();
    }

    fun setDeviceAPI(deviceAPI: Address) {
        self.deviceAPI = deviceAPI;
        self.sendUpdate();
    }

    fun setVendor(vendor: Address) {
        self.vendor = vendor;
        self.sendUpdate();
    }

    override fun checkAuth(msg: SignedMessage) {
        throwUnless(self.ErrorCommandExpired, msg.validUntil >= now());

        let current = self.seqnos.get(msg.publicKey);
        if (current == null) {
            throwUnless(self.ErrorInvalidSeqno, msg.seqno == 1);
        } else {
            throwUnless(self.ErrorInvalidSeqno, msg.seqno == current!! + 1);
        }

        self.requireTrustedKey(msg.publicKey);
    }

    override fun commitSeqno(msg: SignedMessage) {
        self.seqnos.set(msg.publicKey, msg.seqno);
    }

    override fun beforeSignedMessage(_: SignedMessage) {
        self.topUpIfNeeded();
    }

    override fun dispatchSignedMessage(message: Cell) {
        let s = message.beginParse();
        let op = s.loadUint(32);

        if (op == SetNode.opcode()) {
            let msg = SetNode.fromCell(message);
            self.setNode(msg.node);
            return;
        }
        if (op == SetOwner.opcode()) {
            let msg = SetOwner.fromCell(message);
            self.setOwner(msg.publicKey, msg.name);
            return;
        }
        if (op == RemoveOwner.opcode()) {
            let msg = RemoveOwner.fromCell(message);
            self.removeOwner(msg.publicKey);
            return;
        }
        if (op == SetName.opcode()) {
            let msg = SetName.fromCell(message);
            self.setName(msg.name);
            return;
        }
        if (op == SetLock.opcode()) {
            let msg = SetLock.fromCell(message);
            self.setLock(msg.value);
            return;
        }
        if (op == SetStat.opcode()) {
            let msg = SetStat.fromCell(message);
            self.setStat(msg.value);
            return;
        }
        if (op == SetEvents.opcode()) {
            let msg = SetEvents.fromCell(message);
            self.setEvents(msg.value);
            return;
        }
        if (op == SetDeviceAPI.opcode()) {
            let msg = SetDeviceAPI.fromCell(message);
            self.setDeviceAPI(msg.deviceAPI);
            return;
        }
        if (op == SetVendor.opcode()) {
            let msg = SetVendor.fromCell(message);
            self.setVendor(msg.vendor);
            return;
        }
        if (op == DeviceEvent.opcode()) {
            let msg = DeviceEvent.fromCell(message);
            self.emitDeviceEvent(msg.name, msg.data);
            return;
        }

        throw(self.ErrorUnsupportedSignedMessage);
    }

    receive(msg: DeviceInit) {
        throwUnless(ErrorAlreadyConfigured, self.group == null);
        throwIf(self.ErrorInvalidGroup, msg.group == myAddress());
        throwUnless(TactExitCodeAccessDenied, sender() == msg.group);

        self.group = msg.group;
        self.name = msg.name;
        self.dtype = msg.dtype;
        self.version = msg.version;
        self.elector = msg.elector;
        self.vendor = msg.vendor;
        self.vendorData = msg.vendorData;
        self.stat = msg.stat;
        self.events = msg.events;
    }

    // todo: remove
    receive(msg: SetNode) {
        self.topUpIfNeeded();
        self.setNode(msg.node);
    }

    receive(msg: Slice) {}
}
