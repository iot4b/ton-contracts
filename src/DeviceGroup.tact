import "@stdlib/ownable";

message SetName {
    name: String;
}

message SetDevice {
    addr: Address;
    pubkey: Int;
}

message RemoveDevice {
    addr: Address;
}

message Transfer {
    dest: Address;
    amount: Int;
}

message TransferToElector {
    amount: Int;
}

contract DeviceGroup with Ownable {
    owner: Address;

    name: String;
    elector: Address;
    devices: map<Address, Int>; // address => pubkey

    init(
        owner: Address,
        name: String,
        elector: Address,
        devices: map<Address, Int>,
    ) {
        self.owner = owner;
        self.name = name;
        self.elector = elector;
        self.devices = devices;
    }

    receive(msg: SetName) {
        self.requireOwner();
        self.name = msg.name;
    }

    receive(msg: SetDevice) {
        self.requireOwner();
        self.devices.set(msg.addr, msg.pubkey);
    }

    receive(msg: RemoveDevice) {
        self.requireOwner();
        self.devices.del(msg.addr);
    }

    receive(msg: Transfer) {
        self.requireOwner();
        send(SendParameters {
            to: msg.dest,
            value: msg.amount,
            bounce: true,
            mode: SendDefaultMode,
        });
    }

    receive(msg: TransferToElector) {
        self.requireOwner();
        send(SendParameters {
            to: self.elector,
            value: msg.amount,
            bounce: true,
            mode: SendDefaultMode,
        });
    }
}
