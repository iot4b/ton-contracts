/**
 * Node contract tests — TON network (using @ton/sandbox and Tact-generated wrappers).
 * Adapted from Everscale Locklift tests.
 */
import { Blockchain, internal } from "@ton/sandbox";
import { Address, contractAddress, toNano } from "@ton/core";
import { Node } from "../output/Node_Node";

const TEST_ELECTOR = Address.parse("0:da995a0f7e2f75457031cbc016d7cba6fc65b617a94331eb54c349af15e95d1a");

describe("Node contract", () => {
  let blockchain: Blockchain;
  let deployer: Awaited<ReturnType<Blockchain["treasury"]>>;
  let nodeContract: ReturnType<typeof blockchain.openContract<Node>>;
  let nodeAddress: Address;

  beforeAll(async () => {
    blockchain = await Blockchain.create();
    deployer = await blockchain.treasury("deployer");
  });

  it("should deploy contract", async () => {
    const electorAddr = TEST_ELECTOR;
    const init = await Node.init(deployer.address, electorAddr, "123.0.123.0:5865", "test-node");
    nodeAddress = contractAddress(0, init);
    await blockchain.sendMessage(
      internal({
        from: deployer.address,
        to: nodeAddress,
        value: toNano("2"),
        stateInit: init,
      })
    );
    nodeContract = blockchain.openContract(new Node(nodeAddress, init));
  });

  it("should return correct elector, ip, contactInfo from getters", async () => {
    const elector = await nodeContract.getGetElector();
    const ip = await nodeContract.getGetIp();
    const contactInfo = await nodeContract.getGetContactInfo();
    expect(elector.equals(TEST_ELECTOR)).toBe(true);
    expect(ip).toBe("123.0.123.0:5865");
    expect(contactInfo).toBe("test-node");
  });

  it("should get Elector for node", async () => {
    const response = await nodeContract.getGetElector();
    expect(response.equals(TEST_ELECTOR)).toBe(true);
  });

  it("should get ip for node", async () => {
    const response = await nodeContract.getGetIp();
    expect(response).toBe("123.0.123.0:5865");
  });

  it("should get contactInfo for node", async () => {
    const response = await nodeContract.getGetContactInfo();
    expect(response).toBe("test-node");
  });

  it("should set and get ip for node", async () => {
    const newIp = "91.0.91.0:1234";
    await nodeContract.send(deployer.getSender(), { value: toNano("0.01") }, { $$type: "SetIp", value: newIp });
    const response = await nodeContract.getGetIp();
    expect(response).toBe(newIp);
  });

  it("should set and get contactInfo for node", async () => {
    const newContactInfo = "Automation-test-node";
    await nodeContract.send(deployer.getSender(), { value: toNano("0.01") }, { $$type: "SetContactInfo", value: newContactInfo });
    const response = await nodeContract.getGetContactInfo();
    expect(response).toBe(newContactInfo);
  });
});
