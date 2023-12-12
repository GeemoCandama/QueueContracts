// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "../src/YoutubeQueueNew.sol";
import "openzeppelin-contracts/token/ERC721/IERC721Receiver.sol";
import "openzeppelin-contracts/utils/Counters.sol";

contract VideoQueueV2Test is Test, IERC721Receiver {
    address public vitalik = 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045;
    YoutubeQueueNew public video_queue;

    function setUp() public {
       video_queue = new YoutubeQueueNew(
           "test",
           "TST",
           "ewggrwgregrgwegerg",
           300,
           0.0001 ether,
           1000,
           3,
           vitalik,
           vitalik,
           10,
           5
       );
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
        video_queue.enqueue{value: 0.03 ether}("islekjfkao_", 300, 0);
        vm.warp(302 seconds);
        video_queue.voteOnToken(1, true);
        vm.warp(1002 seconds);
        video_queue.enqueue{value: 0.03 ether}("islekjfkao_", 300, 0);
        video_queue.enqueue{value: 0.03 ether}("islekjfkao_", 300, 0);
        video_queue.enqueue{value: 0.03 ether}("islekjfkao_", 300, 0);
        video_queue.enqueue{value: 0.03 ether}("islekjfkao_", 300, 0);
        vm.warp(5002 seconds);
        video_queue.upgradeToVotingToken(1);
    }

    // function test_DequeueBasic() public {
    //     video_queue.enqueue{value: 0.03 ether}("islekjfkao_", 30, 0);
    //     vm.warp(31 seconds);
    //     video_queue.dequeue();
    // }

    // function testFail_RevertWhen_DequeueIsCalledEarly() public {
    //     video_queue.enqueue{value: 0.03 ether}("islekjfkao_", 30, 0);
    //     video_queue.dequeue();
    // }

    // function test_DeployerCanVote() public {
    //     hoax(vitalik, 10 ether);
    //     video_queue.enqueue{value: 0.03 ether}("islekjfkao_", 30, 0);
    //     skip(31 seconds);
    //     video_queue.dequeue();
    //     video_queue.voteOnVideo(1, true);
    // }
}
