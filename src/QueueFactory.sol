pragma solidity >=0.8.0 <0.9.0;
import "./SpotifyQueue.sol";
import "openzeppelin-contracts/utils/Counters.sol";

contract QueueFactory {
    using Counters for Counters.Counter;
    Counters.Counter public queueIdCounter;

    event QueueCreated(
        address indexed queueAddress, 
        uint256 indexed queueId,
        string  _name,
        string _symbol,
        string _queueURI,
        uint256 _minTimeActive,
        uint256 _costPerSecond,
        uint256 _votePeriodLength,
        uint256 _releasePeriodLength,
        address _voteFundDonationAddress,
        address _initialVoter,
        uint256 _initialVoteInfluence,
        uint256 _maxRefund
    );

    function createSpotifyQueue(
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
    ) public {
        Queue queue = new SpotifyQueue(
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
        );
        emit QueueCreated(
            address(queue), 
            queueIdCounter.current(),
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
        );
        queueIdCounter.increment();
    }
}

