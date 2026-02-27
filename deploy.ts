import { resolve } from "path";
import { readFile } from "fs/promises";
import { Address, contractAddress, Dictionary } from "@ton/core";
import { prepareTactDeployment } from "@tact-lang/deployer";
import { DeviceGroup } from "./output/DeviceGroup_DeviceGroup";

async function main() {
    console.log("Deploying...");
    const toProduction = process.argv.length === 3 && process.argv[2] === "mainnet";
    const addr = Address.parse("0QCSES0TZYqcVkgoguhIb8iMEo4cvaEwmIrU5qbQgnN8fo2A");
    const init = await DeviceGroup.init(addr, "Test Device Group", addr, Dictionary.empty());
    const prepare = await prepareTactDeployment({
        pkg: await readFile(resolve(__dirname, "output", "DeviceGroup_DeviceGroup.pkg")),
        data: init.data.toBoc(),
        testnet: !toProduction,
    });
    const address = contractAddress(0, init).toString({ testOnly: !toProduction });
    console.log(`Contract address: ${address}`);
    console.log(`Please, follow deployment link: ${prepare}`);
}

void main();
