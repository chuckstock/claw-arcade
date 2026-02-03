// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/ClawToken.sol";
import "../src/ClawFlipSimple.sol";

contract DeployScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying from:", deployer);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy ClawToken with 100M initial supply
        ClawToken claw = new ClawToken(deployer, 100_000_000 ether);
        console.log("ClawToken deployed at:", address(claw));
        
        // Deploy ClawFlipSimple
        // treasury = deployer, minEntry = 10 CLAW
        ClawFlipSimple game = new ClawFlipSimple(
            address(claw),
            deployer,
            10 ether
        );
        console.log("ClawFlipSimple deployed at:", address(game));
        
        vm.stopBroadcast();
    }
}
