import "./lib/Messages";

const ErrorOwnerNotFound: Int = 601;
const ErrorLastOwnerForbidden: Int = 602;
const ErrorGroupNotConfigured: Int = 603;
const ErrorAlreadyConfigured: Int = 604;
const ErrorInvalidGroup: Int = 605;

message SetNode {
    node: Address;
}

message AddOwner {
    publicKey: Int as uint256;
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

message SetGroup {
    group: Address;
}

message SetDeviceAPI {
    deviceAPI: Address;
}

message SetVendor {
    vendor: Address;
}

message SendTransaction {
    dest: Address;
    value: Int as uint128;
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
    owners: map<Int as uint256, Bool>;
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

contract Device {
    owners: map<Int as uint256, Bool>;
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

    init(publicKey: Int as uint256) {
        self.owners = emptyMap();
        self.owners.set(publicKey, true);
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

    get fun get(): DeviceData {
        return DeviceData {
            owners: self.owners,
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

    fun requireGroup() {
        throwUnless(ErrorGroupNotConfigured, self.group != null);
        throwUnless(TactExitCodeAccessDenied, sender() == self.group!!);
    }

    fun ensureGas() {
        if (myBalance() < ton("1")) {
            throwUnless(ErrorGroupNotConfigured, self.group != null);
            send(SendParameters {
                to: self.group!!,
                value: ton("0"),
                bounce: true,
                mode: SendPayFwdFeesSeparately | SendIgnoreErrors,
                body: SendTon { dest: myAddress(), amount: ton("1") }.toCell(),
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

    receive(msg: DeviceInit) {
        throwUnless(ErrorAlreadyConfigured, self.group == null);
        throwIf(ErrorInvalidGroup, msg.group == myAddress());
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

    receive(msg: DeviceEvent) {
        self.requireGroup();
        self.ensureGas();
        emit(msg.toCell());
        send(SendParameters {
            to: self.group!!,
            value: ton("0"),
            bounce: true,
            mode: SendPayFwdFeesSeparately | SendIgnoreErrors,
            body: GroupEvent { name: msg.name, data: msg.data }.toCell(),
        });
    }

    receive(msg: SetNode) {
        // TODO: restore sender authorization once signed owner commands are implemented.
        self.ensureGas();
        throwUnless(ErrorGroupNotConfigured, self.elector != null);

        let oldNode = self.node;

        send(SendParameters {
            to: self.elector!!,
            value: ton("0.1"),
            bounce: true,
            mode: SendIgnoreErrors,
            body: GetPayment { group: self.group!! }.toCell(),
        });

        send(SendParameters {
            to: msg.node,
            value: ton("0.1"),
            bounce: true,
            mode: SendIgnoreErrors,
            body: DeviceRegisterEvent { device: myAddress(), oldnode: oldNode }.toCell(),
        });

        emit(
            NodeChangeLog {
                contractAddress: myAddress(),
                oldNode,
                newNode: msg.node,
            }.toCell(),
        );

        self.node = msg.node;
        self.lastRegisterTime = now();
    }

    receive(msg: AddOwner) {
        self.requireGroup();
        self.ensureGas();
        self.owners.set(msg.publicKey, true);
        self.sendUpdate();
    }

    receive(msg: RemoveOwner) {
        self.requireGroup();
        self.ensureGas();
        throwUnless(ErrorOwnerNotFound, self.owners.exists(msg.publicKey));
        let count = 0;
        foreach (_, _ in self.owners) {
            count = count + 1;
        }
        throwIf(ErrorLastOwnerForbidden, count <= 1);
        self.owners.del(msg.publicKey);
        self.sendUpdate();
    }

    receive(msg: SetName) {
        self.requireGroup();
        self.ensureGas();
        self.name = msg.name;
        self.sendUpdate();
    }

    receive(msg: SetLock) {
        self.requireGroup();
        self.ensureGas();
        self.lock = msg.value;
        self.sendUpdate();
    }

    receive(msg: SetStat) {
        self.requireGroup();
        self.ensureGas();
        self.stat = msg.value;
        self.sendUpdate();
    }

    receive(msg: SetEvents) {
        self.requireGroup();
        self.ensureGas();
        self.events = msg.value;
        self.sendUpdate();
    }

    receive(msg: SetGroup) {
        self.requireGroup();
        self.ensureGas();
        self.group = msg.group;
        self.sendUpdate();
    }

    receive(msg: SetDeviceAPI) {
        self.requireGroup();
        self.ensureGas();
        self.sendUpdate();
    }

    receive(msg: SetVendor) {
        self.requireGroup();
        self.ensureGas();
        self.vendor = msg.vendor;
        self.sendUpdate();
    }

    receive(msg: SendTon) {
        self.requireGroup();
        self.ensureGas();
        send(SendParameters {
            to: msg.dest,
            value: msg.amount,
            bounce: true,
            mode: SendIgnoreErrors,
        });
    }

    receive(msg: Slice) {}
}
