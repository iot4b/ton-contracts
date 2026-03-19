import "@stdlib/ownable";
import "./Device";
import "./lib/Messages";

message GroupInit {
    name: String;
    elector: Address;
}

message SetDevice {
    addr: Address;
}

message RemoveDevice {
    addr: Address;
}

message DeployDevice {
    publicKey: Int as uint256;
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
    owner: Address;
    deploymentIndex: Int as uint32;
    name: String;
    elector: Address?;
    devices: map<Address, Bool>;
}

contract DeviceGroup with Ownable {
    owner: Address;

    deploymentIndex: Int as uint32;
    name: String;
    elector: Address?;
    devices: map<Address, Bool>;

    init(owner: Address, deploymentIndex: Int) {
        self.owner = owner;
        self.deploymentIndex = deploymentIndex;
        self.name = "";
        self.elector = null;
        self.devices = emptyMap();
    }

    fun requireOwnerOrDevice() {
        let s = sender();
        if (s == self.owner || self.devices.exists(s)) {
            return;
        }
        throw(TactExitCodeAccessDenied);
    }

    fun requireElectorContract() {
        throwUnless(TactExitCodeAccessDenied, self.elector != null);
        throwUnless(TactExitCodeAccessDenied, sender() == self.elector!!);
    }

    get fun get(): DeviceGroupData {
        return DeviceGroupData {
            owner: self.owner,
            deploymentIndex: self.deploymentIndex,
            name: self.name,
            elector: self.elector,
            devices: self.devices,
        };
    }

    receive(msg: GroupInit) {
        self.requireOwner();
        throwIf(TactExitCodeAccessDenied, self.elector != null);

        self.name = msg.name;
        self.elector = msg.elector;
    }

    receive(msg: GroupEvent) {
        self.requireOwnerOrDevice();
        emit(msg.toCell());
    }

    receive(msg: SetName) {
        self.requireOwner();
        self.name = msg.name;
    }

    receive(msg: SetDevice) {
        self.requireOwner();
        self.devices.set(msg.addr, true);
    }

    receive(msg: RemoveDevice) {
        self.requireOwner();
        self.devices.del(msg.addr);
    }

    receive(msg: DeployDevice) {
        self.requireOwner();
        throwUnless(TactExitCodeAccessDenied, self.elector != null);

        let init = initOf Device(msg.publicKey);
        let deviceAddress = contractAddress(init);

        deploy(DeployParameters {
            init,
            body: DeviceInit {
                group: myAddress(),
                name: msg.name,
                dtype: msg.dtype,
                version: msg.version,
                elector: self.elector!!,
                vendor: msg.vendor,
                vendorData: msg.vendorData,
                stat: msg.stat,
                events: msg.events,
            }.toCell(),
            value: msg.amount,
            bounce: false,
            mode: SendIgnoreErrors,
        });

        self.devices.set(deviceAddress, true);
    }

    receive(msg: SendTon) {
        self.requireOwnerOrDevice();
        send(SendParameters {
            to: msg.dest,
            value: msg.amount,
            bounce: true,
            mode: SendDefaultMode,
        });
    }

    receive(msg: SendTonToElector) {
        self.requireElectorContract();
        send(SendParameters {
            to: self.elector!!,
            value: msg.amount,
            bounce: true,
            mode: SendDefaultMode,
        });
    }

    receive(msg: Slice) {}
}
