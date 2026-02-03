// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/ClawFlipETHv2.sol";

/**
 * @title DeployETHv2Script
 * @notice Deployment script for ClawFlipETHv2 on Base Sepolia
 * 
 * Prerequisites:
 * 1. Create a VRF subscription at https://vrf.chain.link/
 * 2. Fund the subscription with LINK
 * 3. Add the deployed contract as a consumer
 * 
 * Usage:
 *   forge script script/DeployETHv2.s.sol:DeployETHv2Script \
 *     --rpc-url $BASE_SEPOLIA_RPC \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast \
 *     --verify
 */
contract DeployETHv2Script is Script {
    // ═══════════════════════════════════════════════════════════
    //             BASE SEPOLIA VRF V2.5 CONFIGURATION
    // ═══════════════════════════════════════════════════════════
    
    // Chainlink VRF V2.5 Coordinator on Base Sepolia
    // Source: https://docs.chain.link/vrf/v2-5/supported-networks#base-sepolia-testnet
    address constant BASE_SEPOLIA_VRF_COORDINATOR = 0x5C210eF41CD1a72de73bF76eC39637bB0d3d7BEE;
    
    // Key hash (gas lane) for Base Sepolia - 500 gwei
    bytes32 constant BASE_SEPOLIA_KEY_HASH = 0x9e9e46732b32662b9adc6f3abdf6c5e926a666d174a4d6b8e39c4cca76a38897;
    
    // ═══════════════════════════════════════════════════════════
    //             BASE MAINNET VRF V2.5 CONFIGURATION
    // ═══════════════════════════════════════════════════════════
    
    // Chainlink VRF V2.5 Coordinator on Base Mainnet
    address constant BASE_MAINNET_VRF_COORDINATOR = 0xd5D517aBE5cF79B7e95eC98dB0f0277788aFF634;
    
    // Key hash (gas lane) for Base Mainnet - 500 gwei
    bytes32 constant BASE_MAINNET_KEY_HASH = 0xdc2f87677b01473c763cb0aee938ed3b6a23c9f5a54a0d6d3a1e6fb5f3b1e3f9;

    function run() external {
        // Load configuration from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        // VRF subscription ID - create one at https://vrf.chain.link/
        uint256 vrfSubscriptionId = vm.envOr("VRF_SUBSCRIPTION_ID", uint256(0));
        require(vrfSubscriptionId > 0, "Set VRF_SUBSCRIPTION_ID env var");
        
        // Treasury address (defaults to deployer)
        address treasury = vm.envOr("TREASURY_ADDRESS", deployer);
        
        // Minimum entry (defaults to 0.001 ETH)
        uint256 minEntry = vm.envOr("MIN_ENTRY", uint256(0.001 ether));
        
        // Network detection - use chain ID
        bool isMainnet = block.chainid == 8453; // Base Mainnet
        bool isSepolia = block.chainid == 84532; // Base Sepolia
        
        address vrfCoordinator;
        bytes32 keyHash;
        
        if (isMainnet) {
            vrfCoordinator = BASE_MAINNET_VRF_COORDINATOR;
            keyHash = BASE_MAINNET_KEY_HASH;
            console.log("Deploying to BASE MAINNET");
        } else if (isSepolia) {
            vrfCoordinator = BASE_SEPOLIA_VRF_COORDINATOR;
            keyHash = BASE_SEPOLIA_KEY_HASH;
            console.log("Deploying to BASE SEPOLIA");
        } else {
            // Local/other - require explicit configuration
            vrfCoordinator = vm.envAddress("VRF_COORDINATOR");
            keyHash = vm.envBytes32("VRF_KEY_HASH");
            console.log("Deploying to CUSTOM NETWORK (chain:", block.chainid, ")");
        }
        
        console.log("");
        console.log("=== DEPLOYMENT CONFIGURATION ===");
        console.log("Deployer:        ", deployer);
        console.log("Treasury:        ", treasury);
        console.log("Min Entry:       ", minEntry);
        console.log("VRF Coordinator: ", vrfCoordinator);
        console.log("VRF Key Hash:    ", vm.toString(keyHash));
        console.log("VRF Sub ID:      ", vrfSubscriptionId);
        console.log("");
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy ClawFlipETHv2
        ClawFlipETHv2 game = new ClawFlipETHv2(
            treasury,
            minEntry,
            vrfCoordinator,
            vrfSubscriptionId,
            keyHash
        );
        
        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("ClawFlipETHv2:", address(game));
        console.log("");
        console.log("IMPORTANT: Add this contract as a consumer to your VRF subscription!");
        console.log("Go to: https://vrf.chain.link/");
        console.log("1. Select your subscription (ID:", vrfSubscriptionId, ")");
        console.log("2. Click 'Add Consumer'");
        console.log("3. Enter contract address:", address(game));
        
        vm.stopBroadcast();
    }
}

/**
 * @title DeployETHv2LocalScript
 * @notice Deployment script for local testing with mock VRF
 */
contract DeployETHv2LocalScript is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)); // Anvil default
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deploying to LOCAL NETWORK with mock VRF");
        console.log("Deployer:", deployer);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy mock VRF coordinator
        MockVRFCoordinatorV2_5 mockVRF = new MockVRFCoordinatorV2_5();
        console.log("Mock VRF Coordinator:", address(mockVRF));
        
        // Deploy game
        ClawFlipETHv2 game = new ClawFlipETHv2(
            deployer,           // treasury
            0.001 ether,        // minEntry
            address(mockVRF),   // vrfCoordinator
            1,                  // subscriptionId (mock)
            bytes32(uint256(1)) // keyHash (mock)
        );
        console.log("ClawFlipETHv2:", address(game));
        
        // Enable auto-fulfillment for easy testing
        mockVRF.setAutoFulfill(true);
        console.log("Mock VRF auto-fulfill enabled");
        
        vm.stopBroadcast();
    }
}

// Import mock for local deployment
import "../src/mocks/MockVRFCoordinatorV2_5.sol";
