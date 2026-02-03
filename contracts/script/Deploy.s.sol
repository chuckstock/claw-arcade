// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {ClawToken} from "../src/ClawToken.sol";
import {ClawFlip} from "../src/ClawFlip.sol";

/**
 * @title Deploy
 * @notice Deployment script for Lobster Arcade contracts
 *
 * Usage:
 *   # Deploy to Base Sepolia
 *   forge script script/Deploy.s.sol:Deploy --rpc-url $BASE_SEPOLIA_RPC_URL --broadcast --verify
 *
 *   # Dry run (simulation)
 *   forge script script/Deploy.s.sol:Deploy --rpc-url $BASE_SEPOLIA_RPC_URL
 */
contract Deploy is Script {
    // ═══════════════════════════════════════════════════════════
    //                     BASE SEPOLIA CONFIG
    // ═══════════════════════════════════════════════════════════

    // Chainlink VRF v2.5 on Base Sepolia
    address constant VRF_COORDINATOR_SEPOLIA = 0x5C210eF41CD1a72de73bF76eC39637bB0d3d7BEE;

    // Key hash for Base Sepolia (check Chainlink docs for current values)
    bytes32 constant KEY_HASH_SEPOLIA = 0x9e1344a1247c8a1785d0a4681a27152bffdb43666ae5bf7d14d24a5efd44bf71;

    // ═══════════════════════════════════════════════════════════
    //                     BASE MAINNET CONFIG
    // ═══════════════════════════════════════════════════════════

    // Chainlink VRF v2.5 on Base Mainnet
    address constant VRF_COORDINATOR_MAINNET = 0xd5D517aBE5cF79B7e95eC98dB0f0277788aFF634;

    // Key hashes for Base Mainnet
    bytes32 constant KEY_HASH_2_GWEI = 0x00b81b5a830cb0a4009fbd8904de511e28631e62ce5ad231373d3cdad373ccab;
    bytes32 constant KEY_HASH_30_GWEI = 0xdc2f87677b01473c763cb0aee938ed3341512f6057324a584e5944e786144d70;

    // ═══════════════════════════════════════════════════════════
    //                      DEPLOYMENT CONFIG
    // ═══════════════════════════════════════════════════════════

    // Initial token supply: 100M CLAW for initial distribution
    uint256 constant INITIAL_SUPPLY = 100_000_000 * 10 ** 18;

    // Minimum entry: 10 CLAW
    uint256 constant MIN_ENTRY = 10 * 10 ** 18;

    function run() external {
        // Load environment variables
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 subscriptionId = vm.envUint("VRF_SUBSCRIPTION_ID");
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        bool isMainnet = vm.envOr("MAINNET", false);

        // Select network config
        address vrfCoordinator;
        bytes32 keyHash;

        if (isMainnet) {
            vrfCoordinator = VRF_COORDINATOR_MAINNET;
            keyHash = KEY_HASH_30_GWEI; // Higher gas lane for reliability
            console2.log("Deploying to Base Mainnet...");
        } else {
            vrfCoordinator = VRF_COORDINATOR_SEPOLIA;
            keyHash = KEY_HASH_SEPOLIA;
            console2.log("Deploying to Base Sepolia...");
        }

        address deployer = vm.addr(deployerPrivateKey);
        console2.log("Deployer:", deployer);
        console2.log("Treasury:", treasury);
        console2.log("VRF Coordinator:", vrfCoordinator);
        console2.log("Subscription ID:", subscriptionId);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy $CLAW token
        ClawToken clawToken = new ClawToken(deployer, INITIAL_SUPPLY);
        console2.log("ClawToken deployed at:", address(clawToken));

        // 2. Deploy ClawFlip game
        ClawFlip clawFlip = new ClawFlip(
            vrfCoordinator,
            address(clawToken),
            subscriptionId,
            keyHash,
            MIN_ENTRY,
            treasury
        );
        console2.log("ClawFlip deployed at:", address(clawFlip));

        vm.stopBroadcast();

        // Log deployment summary
        console2.log("\n========================================");
        console2.log("           DEPLOYMENT SUMMARY");
        console2.log("========================================");
        console2.log("Network:", isMainnet ? "Base Mainnet" : "Base Sepolia");
        console2.log("ClawToken:", address(clawToken));
        console2.log("ClawFlip:", address(clawFlip));
        console2.log("Initial Supply:", INITIAL_SUPPLY / 10 ** 18, "CLAW");
        console2.log("Min Entry:", MIN_ENTRY / 10 ** 18, "CLAW");
        console2.log("========================================\n");

        // Remind about VRF consumer registration
        console2.log("IMPORTANT: Add ClawFlip as a consumer to your VRF subscription!");
        console2.log("VRF Subscription ID:", subscriptionId);
        console2.log("Consumer to add:", address(clawFlip));
    }
}

/**
 * @title DeployToken
 * @notice Deploy only the $CLAW token
 */
contract DeployToken is Script {
    uint256 constant INITIAL_SUPPLY = 100_000_000 * 10 ** 18;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console2.log("Deploying ClawToken...");
        console2.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);
        ClawToken clawToken = new ClawToken(deployer, INITIAL_SUPPLY);
        vm.stopBroadcast();

        console2.log("ClawToken deployed at:", address(clawToken));
    }
}

/**
 * @title DeployGame
 * @notice Deploy only the ClawFlip game (requires existing $CLAW token)
 */
contract DeployGame is Script {
    uint256 constant MIN_ENTRY = 10 * 10 ** 18;

    // Base Sepolia config
    address constant VRF_COORDINATOR = 0x5C210eF41CD1a72de73bF76eC39637bB0d3d7BEE;
    bytes32 constant KEY_HASH = 0x9e1344a1247c8a1785d0a4681a27152bffdb43666ae5bf7d14d24a5efd44bf71;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        uint256 subscriptionId = vm.envUint("VRF_SUBSCRIPTION_ID");
        address treasury = vm.envAddress("TREASURY_ADDRESS");
        address clawToken = vm.envAddress("CLAW_TOKEN_ADDRESS");

        console2.log("Deploying ClawFlip...");
        console2.log("CLAW Token:", clawToken);
        console2.log("Treasury:", treasury);

        vm.startBroadcast(deployerPrivateKey);
        ClawFlip clawFlip = new ClawFlip(VRF_COORDINATOR, clawToken, subscriptionId, KEY_HASH, MIN_ENTRY, treasury);
        vm.stopBroadcast();

        console2.log("ClawFlip deployed at:", address(clawFlip));
    }
}
