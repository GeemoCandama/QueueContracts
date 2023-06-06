// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console2.sol";
import "../src/Queue.sol";
import "openzeppelin-contracts/token/ERC721/IERC721Receiver.sol";

contract QueueTest is Test, IERC721Receiver {
    uint256 testNumber;

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

    function setUp() public {
        testNumber = 42;
    }
}
