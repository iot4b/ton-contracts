import "@stdlib/ownable";
import "./lib/Messages";

message SetIp {
    value: String;
}

message SetContactInfo {
    value: String;
}

contract Node with Ownable {
    owner: Address;

    elector: Address;
    ip: String;
    contactInfo: String;

    init(owner: Address, elector: Address, ip: String, contactInfo: String) {
        self.owner = owner;
        self.elector = elector;
        self.ip = ip;
        self.contactInfo = contactInfo;
    }

    get fun getElector(): Address {
        return self.elector;
    }

    get fun getIp(): String {
        return self.ip;
    }

    get fun getContactInfo(): String {
        return self.contactInfo;
    }

    receive(msg: DeviceRegisterEvent) {
        emit(msg.toCell());
    }

    receive(msg: DeviceUpdateEvent) {
        emit(msg.toCell());
    }

    receive(msg: SetIp) {
        self.requireOwner();
        self.ip = msg.value;
    }

    receive(msg: SetContactInfo) {
        self.requireOwner();
        self.contactInfo = msg.value;
    }

    receive(msg: SendTon) {
        self.requireOwner();
        send(SendParameters {
            to: msg.dest,
            value: msg.amount,
            bounce: true,
            mode: SendDefaultMode,
        });
    }

    receive(msg: Slice) {}
}
