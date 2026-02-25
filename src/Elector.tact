import "@stdlib/ownable";
import "./lib/Messages";

message SetNodes {
    nodes: map<Address, Bool>;
}

message TakeNextRound {
    addr: Address;
}

message ReportFaultNode {
    addr: Address;
}

message Election {}

contract Elector with Ownable {
    owner: Address;

    nodesCurrent: map<Address, Bool>;
    nodesNext: map<Address, Bool>;
    nodesParticipants: map<Address, Bool>;
    nodesFault: map<Address, Int>;

    init(owner: Address, defaultNodes: map<Address, Bool>) {
        self.owner = owner;
        self.nodesCurrent = defaultNodes;
        self.nodesNext = emptyMap();
        self.nodesParticipants = emptyMap();
        self.nodesFault = emptyMap();
    }

    get fun getNodesCurrent(): map<Address, Bool> {
        return self.nodesCurrent;
    }

    get fun getNodesNext(): map<Address, Bool> {
        return self.nodesNext;
    }

    get fun getNodesParticipants(): map<Address, Bool> {
        return self.nodesParticipants;
    }

    get fun getNodesFault(): map<Address, Int> {
        return self.nodesFault;
    }

    receive(msg: GetPayment) {
        send(SendParameters{
            to: msg.group,
            value: ton("0"),
            bounce: true,
            mode: SendPayFwdFeesSeparately | SendIgnoreErrors,
            body: SendTonToElector{ amount: ton("1") }.toCell(),
        });
    }

    receive(msg: SetNodes) {
        self.requireOwner();
        self.nodesCurrent = msg.nodes;
    }

    receive(msg: TakeNextRound) {
        self.requireOwner();
        self.nodesParticipants.set(msg.addr, true);
    }

    receive(msg: ReportFaultNode) {
        self.requireOwner();
        let current = self.nodesFault.get(msg.addr);
        if (current == null) {
            self.nodesFault.set(msg.addr, 1);
        } else {
            let next = current!! + 1;
            if (next >= 5) {
                self.nodesCurrent.del(msg.addr);
                self.nodesFault.del(msg.addr);
            } else {
                self.nodesFault.set(msg.addr, next);
            }
        }
    }

    receive(msg: Election) {
        self.requireOwner();
        foreach (addr, _ in self.nodesParticipants) {
            self.nodesCurrent.set(addr, true);
        }
        self.nodesParticipants = emptyMap();
    }

    receive(msg: SendTon) {
        self.requireOwner();
        send(SendParameters{
            to: msg.dest,
            value: msg.amount,
            bounce: true,
            mode: SendDefaultMode,
        });
    }

    receive(msg: Slice) {}
}
