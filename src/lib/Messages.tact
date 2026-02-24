// Common
message Transfer {
    dest: Address;
    amount: Int;
}

// DeviceGroup
message TransferToElector {
    amount: Int;
}
message GroupEvent {
    name: String;
    data: String;
}

// Elector
message GetPayment {
    group: Address;
}

// Node
message DeviceRegisterMsg {
    device: Address;
    oldnode: Address?;
}
message DeviceUpdateMsg {
    device: Address;
}
