import "@stdlib/ownable";
import "./lib/Messages";

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

    name: String;
    elector: Address;
    devices: map<Address, Bool>;

    init(
        owner: Address,
        name: String,
        elector: Address,
        devices: map<Address, Bool>,
    ) {
        self.owner = owner;
        self.name = name;
        self.elector = elector;
        self.devices = devices;
    }

    fun requireOwnerOrDevice() {
        let s = sender();
        if (s == self.owner || self.devices.exists(s)) {
            return;
        }
        throw(TactExitCodeAccessDenied);
    }

    fun requireElectorContract() {
        throwUnless(TactExitCodeAccessDenied, sender() == self.elector);
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
            to: self.elector,
            value: msg.amount,
            bounce: true,
            mode: SendDefaultMode,
        });
    }

    receive(msg: Slice) {}
}
