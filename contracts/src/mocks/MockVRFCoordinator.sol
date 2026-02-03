// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title MockVRFCoordinator
 * @notice Mock VRF Coordinator for testing ClawFlip without Chainlink dependencies
 */
contract MockVRFCoordinator {
    uint256 public lastRequestId;
    mapping(uint256 => address) public requestIdToConsumer;
    
    event RandomWordsRequested(uint256 indexed requestId, address consumer);
    
    function requestRandomWords(
        bytes32, // keyHash
        uint256, // subId
        uint16,  // requestConfirmations
        uint32,  // callbackGasLimit
        uint32   // numWords
    ) external returns (uint256 requestId) {
        lastRequestId++;
        requestId = lastRequestId;
        requestIdToConsumer[requestId] = msg.sender;
        emit RandomWordsRequested(requestId, msg.sender);
    }
    
    /// @notice Fulfill randomness - call this in tests to simulate VRF callback
    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) external {
        address consumer = requestIdToConsumer[requestId];
        require(consumer != address(0), "Invalid request");
        
        // Call the consumer's fulfillRandomWords
        (bool success,) = consumer.call(
            abi.encodeWithSignature(
                "rawFulfillRandomWords(uint256,uint256[])",
                requestId,
                randomWords
            )
        );
        require(success, "Fulfillment failed");
    }
}
