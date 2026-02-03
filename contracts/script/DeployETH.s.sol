// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/ClawFlipETH.sol";

contract DeployETHScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying from:", deployer);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy ClawFlipETH
        // treasury = deployer, minEntry = 0.001 ETH (~$2.50)
        ClawFlipETH game = new ClawFlipETH(
            deployer,       // treasury
            0.001 ether     // minEntry
        );
        console.log("ClawFlipETH deployed at:", address(game));
        
        vm.stopBroadcast();
    }
}
