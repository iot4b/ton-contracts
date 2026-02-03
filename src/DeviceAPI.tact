import "@stdlib/ownable";

message SetDeviceType {
    value: String;
}

message SetDeviceModel {
    value: String;
}

message SetDeviceFW {
    value: String;
}

message SetDeviceAPI {
    value: String;
}

message SendTx {
    dest: Address;
    value: Int as uint128;
}

contract DeviceAPI with Ownable {
    owner: Address;

    elector: Address;
    vendor: Address;
    deviceType: String;
    deviceModel: String;
    deviceFW: String;
    deviceAPI: String;

    init(
        owner: Address,
        elector: Address,
        vendor: Address,
        deviceType: String,
        deviceModel: String,
        deviceFW: String,
        deviceAPI: String,
    ) {
        self.owner = owner;
        self.elector = elector;
        self.vendor = vendor;
        self.deviceType = deviceType;
        self.deviceModel = deviceModel;
        self.deviceFW = deviceFW;
        self.deviceAPI = deviceAPI;
    }

    get fun getElector(): Address {
        return self.elector;
    }

    get fun getVendor(): Address {
        return self.vendor;
    }

    get fun getDeviceType(): String {
        return self.deviceType;
    }

    get fun getDeviceModel(): String {
        return self.deviceModel;
    }

    get fun getDeviceFW(): String {
        return self.deviceFW;
    }

    get fun getDeviceAPI(): String {
        return self.deviceAPI;
    }

    receive(msg: SetDeviceType) {
        self.requireOwner();
        self.deviceType = msg.value;
    }

    receive(msg: SetDeviceModel) {
        self.requireOwner();
        self.deviceModel = msg.value;
    }

    receive(msg: SetDeviceFW) {
        self.requireOwner();
        self.deviceFW = msg.value;
    }

    receive(msg: SetDeviceAPI) {
        self.requireOwner();
        self.deviceAPI = msg.value;
    }

    receive(msg: SendTx) {
        self.requireOwner();
        send(SendParameters {
            to: msg.dest,
            value: msg.value,
            bounce: true,
            mode: SendIgnoreErrors,
        });
    }
}
