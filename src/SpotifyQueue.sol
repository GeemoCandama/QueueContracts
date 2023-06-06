pragma solidity >=0.8.0 <0.9.0;

import "./Queue.sol";

contract SpotifyQueue is Queue {
    constructor(
        string memory _name,
        string memory _symbol,
        string memory _queueURI,
        uint256 _minTimeActive,
        uint256 _costPerSecond,
        uint256 _votePeriodLength,
        uint256 _releasePeriodLength,
        address _voteFundDonationAddress,
        address _initialVoter,
        uint256 _initialVoteInfluence,
        uint256 _maxRefund
    ) Queue (
        _name,
        _symbol,
        _queueURI,
        _minTimeActive,
        _costPerSecond,
        _votePeriodLength,
        _releasePeriodLength,
        _voteFundDonationAddress,
        _initialVoter,
        _initialVoteInfluence,
        _maxRefund
    ) {}

    modifier validIdentifier(string memory _identifier) override {
        bytes memory idBytes = bytes(_identifier);
        require(idBytes.length == 22, "Invalid video ID length");

        for (uint256 i = 0; i < idBytes.length; i++) {
            require(
                (idBytes[i] >= "0" && idBytes[i] <= "9") ||
                (idBytes[i] >= "a" && idBytes[i] <= "z") ||
                (idBytes[i] >= "A" && idBytes[i] <= "Z"),
                "Invalid video ID character"
            );
        }
        _;
    }
}
