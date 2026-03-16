import "@stdlib/ownable";
import "./lib/Messages";

message DeployConfig {
    name: String;
    elector: Address;
}

message SetName {
    name: String;
}

message SetDevice {
    addr: Address;
}

message RemoveDevice {
    addr: Address;
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

    get fun getName(): String {
        return self.name;
    }

    get fun getElector(): Address {
        return self.elector!!;
    }

    receive(msg: GroupEvent) {
        self.requireOwnerOrDevice();
        emit(msg.toCell());
    }

    receive(msg: DeployConfig) {
        self.requireOwner();
        throwUnless(TactExitCodeAccessDenied, self.elector == null);

        self.name = msg.name;
        self.elector = msg.elector;
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
