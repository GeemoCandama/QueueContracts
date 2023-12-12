pragma solidity >=0.8.0 <0.9.0;

import "./QueueV2.sol";

contract YoutubeQueueNew is QueueV2 {
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
        uint256 _influencePerVotingToken
    ) QueueV2 (
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
        _influencePerVotingToken
    ) {}
    modifier validIdentifier(string memory _identifier) override {
        bytes memory idBytes = bytes(_identifier);
        require(idBytes.length == 11, "Invalid video ID length");

        for (uint256 i = 0; i < idBytes.length; i++) {
            require(
                (idBytes[i] >= "0" && idBytes[i] <= "9") ||
                (idBytes[i] >= "a" && idBytes[i] <= "z") ||
                (idBytes[i] >= "A" && idBytes[i] <= "Z") ||
                idBytes[i] == "_" || idBytes[i] == "-",
                "Invalid video ID character"
            );
        }
        _;
    }
}
