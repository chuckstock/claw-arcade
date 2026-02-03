// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IVRFCoordinatorV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/interfaces/IVRFCoordinatorV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";

/**
 * @title MockVRFCoordinatorV2_5
 * @notice Mock VRF Coordinator V2.5 for testing ClawFlipETHv2
 * @dev Implements the minimal interface needed for testing
 */
contract MockVRFCoordinatorV2_5 {
    uint256 public lastRequestId;
    mapping(uint256 => address) public requestIdToConsumer;
    mapping(uint256 => uint256) public requestIdToSeed;
    
    // Configurable delay for testing
    bool public autoFulfill;
    uint256 public defaultSeed;
    
    event RandomWordsRequested(
        bytes32 indexed keyHash,
        uint256 requestId,
        uint256 preSeed,
        uint256 indexed subId,
        uint16 minimumRequestConfirmations,
        uint32 callbackGasLimit,
        uint32 numWords,
        bytes extraArgs,
        address indexed sender
    );
    
    event RandomWordsFulfilled(uint256 indexed requestId, uint256[] randomWords);
    
    constructor() {
        autoFulfill = false;
        defaultSeed = 0xDEADBEEF;
    }
    
    /**
     * @notice Enable/disable auto-fulfillment for testing
     */
    function setAutoFulfill(bool _auto) external {
        autoFulfill = _auto;
    }
    
    /**
     * @notice Set default seed for auto-fulfillment
     */
    function setDefaultSeed(uint256 _seed) external {
        defaultSeed = _seed;
    }
    
    /**
     * @notice Request random words (V2.5 interface)
     */
    function requestRandomWords(
        VRFV2PlusClient.RandomWordsRequest calldata req
    ) external returns (uint256 requestId) {
        lastRequestId++;
        requestId = lastRequestId;
        requestIdToConsumer[requestId] = msg.sender;
        
        emit RandomWordsRequested(
            req.keyHash,
            requestId,
            uint256(keccak256(abi.encodePacked(requestId, msg.sender))),
            req.subId,
            req.requestConfirmations,
            req.callbackGasLimit,
            req.numWords,
            req.extraArgs,
            msg.sender
        );
        
        // Auto-fulfill if enabled (for simpler tests)
        if (autoFulfill) {
            _fulfillRandomWords(requestId, defaultSeed);
        }
        
        return requestId;
    }
    
    /**
     * @notice Manually fulfill randomness - call this in tests
     * @param requestId The request ID to fulfill
     * @param seed The random seed to provide
     */
    function fulfillRandomWords(uint256 requestId, uint256 seed) external {
        _fulfillRandomWords(requestId, seed);
    }
    
    /**
     * @notice Fulfill with specific random words array
     */
    function fulfillRandomWordsWithArray(uint256 requestId, uint256[] calldata randomWords) external {
        address consumer = requestIdToConsumer[requestId];
        require(consumer != address(0), "Invalid request");
        
        // Clean up
        delete requestIdToConsumer[requestId];
        
        // Call the consumer's rawFulfillRandomWords
        (bool success, bytes memory reason) = consumer.call(
            abi.encodeWithSignature(
                "rawFulfillRandomWords(uint256,uint256[])",
                requestId,
                randomWords
            )
        );
        require(success, string(reason));
        
        emit RandomWordsFulfilled(requestId, randomWords);
    }
    
    function _fulfillRandomWords(uint256 requestId, uint256 seed) internal {
        address consumer = requestIdToConsumer[requestId];
        require(consumer != address(0), "Invalid request");
        
        // Clean up
        delete requestIdToConsumer[requestId];
        
        // Create array with single random word
        uint256[] memory randomWords = new uint256[](1);
        randomWords[0] = seed;
        
        // Call the consumer's rawFulfillRandomWords
        (bool success, bytes memory reason) = consumer.call(
            abi.encodeWithSignature(
                "rawFulfillRandomWords(uint256,uint256[])",
                requestId,
                randomWords
            )
        );
        require(success, string(reason));
        
        emit RandomWordsFulfilled(requestId, randomWords);
    }
    
    /**
     * @notice Get pending request consumer
     */
    function getPendingRequest(uint256 requestId) external view returns (address) {
        return requestIdToConsumer[requestId];
    }
}
