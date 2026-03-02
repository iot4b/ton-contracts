import "./lib/Messages";

const ErrorOwnersRequired: Int = 600;
const ErrorOwnerNotFound: Int = 601;
const ErrorLastOwnerForbidden: Int = 602;

message SetNode {
    node: Address;
}

message AddOwner {
    addr: Address;
}

message RemoveOwner {
    addr: Address;
}

message SetName {
    name: String;
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
    owners: map<Address, Bool>;
    name: String;
    dtype: String;
    version: String;
    lastRegisterTime: Int;
    group: Address;
    node: Address?;
    elector: Address;
    deviceAPI: Address;
    vendor: Address;
    vendorData: String;
    lock: Bool;
    stat: Bool;
    events: Bool;
}

contract Device {
    owners: map<Address, Bool>;
    name: String;
    dtype: String;
    version: String;
    lastRegisterTime: Int as uint32;

    group: Address;
    node: Address?;
    elector: Address;
    deviceAPI: Address;
    vendor: Address;
    vendorData: String;

    lock: Bool;
    stat: Bool;
    events: Bool;

    init(
        owners: map<Address, Bool>,
        name: String,
        dtype: String,
        version: String,
        group: Address,
        elector: Address,
        deviceAPI: Address,
        vendor: Address,
        vendorData: String,
        stat: Bool,
        events: Bool,
    ) {
        let ownersCount = 0;
        foreach (_, _ in owners) {
            ownersCount = ownersCount + 1;
        }
        throwUnless(ErrorOwnersRequired, ownersCount > 0);

        self.owners = owners;
        self.name = name;
        self.dtype = dtype;
        self.version = version;
        self.lastRegisterTime = 0;
        self.group = group;
        self.node = null;
        self.elector = elector;
        self.deviceAPI = deviceAPI;
        self.vendor = vendor;
        self.vendorData = vendorData;
        self.lock = false;
        self.stat = stat;
        self.events = events;
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

    fun requireOwner() {
        throwUnless(TactExitCodeAccessDenied, self.owners.exists(sender()));
    }

    fun ensureGas() {
        if (myBalance() < ton("1")) {
            send(SendParameters {
                to: self.group,
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

    receive(msg: DeviceEvent) {
        self.requireOwner();
        self.ensureGas();
        emit(msg.toCell());
        send(SendParameters {
            to: self.group,
            value: ton("0"),
            bounce: true,
            mode: SendPayFwdFeesSeparately | SendIgnoreErrors,
            body: GroupEvent { name: msg.name, data: msg.data }.toCell(),
        });
    }

    receive(msg: SetNode) {
        self.requireOwner();
        self.ensureGas();

        let oldNode = self.node;

        send(SendParameters {
            to: self.elector,
            value: ton("0.1"),
            bounce: true,
            mode: SendIgnoreErrors,
            body: GetPayment { group: self.group }.toCell(),
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
        self.requireOwner();
        self.ensureGas();
        self.owners.set(msg.addr, true);
        self.sendUpdate();
    }

    receive(msg: RemoveOwner) {
        self.requireOwner();
        self.ensureGas();
        throwUnless(ErrorOwnerNotFound, self.owners.exists(msg.addr));
        let count = 0;
        foreach (_, _ in self.owners) {
            count = count + 1;
        }
        throwUnless(ErrorLastOwnerForbidden, count > 1);
        self.owners.del(msg.addr);
        self.sendUpdate();
    }

    receive(msg: SetName) {
        self.requireOwner();
        self.ensureGas();
        self.name = msg.name;
        self.sendUpdate();
    }

    receive(msg: SetLock) {
        self.requireOwner();
        self.ensureGas();
        self.lock = msg.value;
        self.sendUpdate();
    }

    receive(msg: SetStat) {
        self.requireOwner();
        self.ensureGas();
        self.stat = msg.value;
        self.sendUpdate();
    }

    receive(msg: SetEvents) {
        self.requireOwner();
        self.ensureGas();
        self.events = msg.value;
        self.sendUpdate();
    }

    receive(msg: SetGroup) {
        self.requireOwner();
        self.ensureGas();
        self.group = msg.group;
        self.sendUpdate();
    }

    receive(msg: SetDeviceAPI) {
        self.requireOwner();
        self.ensureGas();
        self.deviceAPI = msg.deviceAPI;
        self.sendUpdate();
    }

    receive(msg: SetVendor) {
        self.requireOwner();
        self.ensureGas();
        self.vendor = msg.vendor;
        self.sendUpdate();
    }

    receive(msg: SendTon) {
        self.requireOwner();
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
