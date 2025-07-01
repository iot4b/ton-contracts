import "@stdlib/ownable";

contract DeviceGroup() {
    // empty receiver for deployment
    receive() {
        cashback(sender());
    }
}
