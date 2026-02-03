import "@stdlib/ownable";

message DeviceRegisterMsg {
    device: Address;
    oldnode: Address;
}

message DeviceUpdateMsg {
    device: Address;
}

message SetIpPort {
    value: String;
}

message SetContactInfo {
    value: String;
}

// Logs

// DeviceRegister log is emitted when a new device is registered.
struct DeviceRegisterLog {
    device: Address;
    oldnode: Address;
}

// DeviceUpdate log is emitted when a device is updated.
struct DeviceUpdateLog {
    device: Address;
}

contract Node with Ownable {
    owner: Address;

    elector: Address;
    ipPort: String;
    contactInfo: String;

    init(owner: Address, elector: Address, ipPort: String, contactInfo: String) {
        self.owner = owner;
        self.elector = elector;
        self.ipPort = ipPort;
        self.contactInfo = contactInfo;
    }

    get fun getElector(): Address {
        return self.elector;
    }

    get fun getIpPort(): String {
        return self.ipPort;
    }

    get fun getContactInfo(): String {
        return self.contactInfo;
    }

    receive(msg: DeviceRegisterMsg) {
        emit(DeviceRegisterLog{ device: msg.device, oldnode: msg.oldnode }.toCell());
    }

    receive(msg: DeviceUpdateMsg) {
        emit(DeviceUpdateLog{ device: msg.device }.toCell());
    }

    receive(msg: SetIpPort) {
        self.requireOwner();
        self.ipPort = msg.value;
    }

    receive(msg: SetContactInfo) {
        self.requireOwner();
        self.contactInfo = msg.value;
    }
}
