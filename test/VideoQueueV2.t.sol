// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "../src/VideoQueueV2.sol";
import "openzeppelin-contracts/token/ERC721/IERC721Receiver.sol";

contract VideoQueueV2Test is Test, IERC721Receiver {
    address public vitalik = 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045;
    VideoQueueV2 public video_queue;
    function setUp() public {
       video_queue = new VideoQueueV2(0.001 ether);
    }

    receive() external payable {}
    
    // Implement the onERC721Received function
    function onERC721Received(
        address /*operator*/,
        address /*from*/,
        uint256 /*tokenId*/,
        bytes calldata /*data*/
    ) external pure override returns (bytes4) {
        // Return the function selector for the onERC721Received function
        // This value is defined as: bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))
        return this.onERC721Received.selector;
    }

    function test_Enqueue() public {
        video_queue.enqueue{value: 0.03 ether}("islekjfkao_", 30, 0);
    }

    function test_DequeueBasic() public {
        video_queue.enqueue{value: 0.03 ether}("islekjfkao_", 30, 0);
        vm.warp(31 seconds);
        video_queue.dequeue();
    }

    function testFail_RevertWhen_DequeueIsCalledEarly() public {
        video_queue.enqueue{value: 0.03 ether}("islekjfkao_", 30, 0);
        video_queue.dequeue();
    }

    function test_DeployerCanVote() public {
        hoax(vitalik, 10 ether);
        video_queue.enqueue{value: 0.03 ether}("islekjfkao_", 30, 0);
        skip(31 seconds);
        video_queue.dequeue();
        video_queue.voteOnVideo(1, true);
    }
}
