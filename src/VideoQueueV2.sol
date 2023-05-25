pragma solidity ^0.8.0;

import "openzeppelin-contracts/token/ERC721/ERC721.sol";
import "openzeppelin-contracts/utils/Counters.sol";

contract VideoQueueV2 is ERC721 {
    using Counters for Counters.Counter;
    Counters.Counter public _tokenIds;
    Counters.Counter public _currentVideoTokenId;
    Counters.Counter public _currentReleasePeriod;
    Counters.Counter public _goodVideoSubmitters;

    uint256 votePeriod = 1 days;
    uint256 ReleasePeriodTime = 7 days;
    uint256 _currentReleasePeriodTimestamp;

    struct Video {
        string videoId;
        uint256 minTime;
        uint256 playbackStartTime;
    }

    struct Listing {
        bool isForSale;
        uint256 price;
    }

    struct VotePeriod {
        uint256 endTimeStamp;
        uint256 good;
        uint256 bad;
        uint256 releasePeriod;
        mapping(address => bool) hasVoted;
    }

    struct ReleasePeriod {
        uint256 rewards;
        uint256 numReceiversThisPeriod;
        uint256 totalVotesCasted;
        mapping(address => uint256) numVotesCastedThisPeriod;
        mapping(address => bool) hasReceivedShare;
    }

    mapping(uint256 => Video) public videoDetails;
    mapping(uint256 => Listing) public listings;
    mapping(uint256 => VotePeriod) public voting;
    mapping(address => uint256) public firstPeriodEligibleForRewards;
    mapping(uint256 => ReleasePeriod) public releasePeriodInfo;

    uint256 public currentVideoStartTime;
    uint256 public costPerSecond;
    uint256 maxRefund = 0.0005 ether;
    uint256 effectiveBalance;

    event VideoBecameFirstInQueue(Video video, uint256 timestamp);
    event VideoDetailsUpdated(Video video, uint256 indexed tokenId);
    event newListing(uint256 indexed tokenId, Listing listing);
    event VoteCasted(uint256 indexed tokenId, bool indexed wasGood);
    event VideoDequeued(uint256 indexed tokenId, uint256 indexed endTimeStamp, uint256 indexed releasePeriod);

    constructor(uint256 _costPerSecond) ERC721("QueueSpot", "QSPT") {
        costPerSecond = _costPerSecond;
        _currentVideoTokenId.increment();
        _currentReleasePeriodTimestamp = block.timestamp;
        firstPeriodEligibleForRewards[msg.sender] = 1;
        _currentReleasePeriod.increment();
        _goodVideoSubmitters.increment();
    }

    modifier validVideoId(string memory videoId) {
        bytes memory idBytes = bytes(videoId);
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

    function enqueue(string memory videoId, uint256 minTime, uint256 playbackStartTime) external payable validVideoId(videoId) {
        require(minTime > 0, "minTime must be greater than 0");
        uint256 requiredPayment = minTime * costPerSecond;
        require(msg.value >= requiredPayment, "Insufficient payment");

        Video memory newVideo = Video({
            videoId: videoId,
            minTime: minTime,
            playbackStartTime: playbackStartTime
        });

        _tokenIds.increment();
        _safeMint(msg.sender, _tokenIds.current()); 
        videoDetails[_tokenIds.current()] = newVideo;

        if (_currentVideoTokenId.current() == _tokenIds.current()) {
            currentVideoStartTime = block.timestamp;
            emit VideoBecameFirstInQueue(newVideo, currentVideoStartTime);
        }
        effectiveBalance += msg.value;
    }

    function dequeue() external {
        require(_currentVideoTokenId.current() <= _tokenIds.current(), "No videos in the queue");

        Video memory firstVideo = videoDetails[_tokenIds.current()];
        uint256 elapsedTime = block.timestamp - currentVideoStartTime;

        require(elapsedTime >= firstVideo.minTime, "Minimum playtime not reached");

        voting[_currentVideoTokenId.current()].endTimeStamp = block.timestamp + votePeriod;
        voting[_currentVideoTokenId.current()].releasePeriod = _currentReleasePeriod.current();
        emit VideoDequeued(_currentVideoTokenId.current(), block.timestamp + votePeriod, _currentReleasePeriod.current());

        if (block.timestamp >= _currentReleasePeriodTimestamp + ReleasePeriodTime) {
            uint256 queuedGasCosts;
            if (_currentVideoTokenId.current() > _tokenIds.current()) {
                queuedGasCosts = 0;
            } else {
                queuedGasCosts = (_tokenIds.current() + 1 - _currentVideoTokenId.current()) * maxRefund;
            }
            uint256 periodRewards = effectiveBalance - queuedGasCosts;
            releasePeriodInfo[_currentReleasePeriod.current()].rewards = periodRewards;
            releasePeriodInfo[_currentReleasePeriod.current()].numReceiversThisPeriod = _goodVideoSubmitters.current();
            effectiveBalance = effectiveBalance - periodRewards;
            _currentReleasePeriod.increment();
            _currentReleasePeriodTimestamp = block.timestamp;
        }

        _currentVideoTokenId.increment();

        if (_currentVideoTokenId.current() <= _tokenIds.current()) {
            currentVideoStartTime = block.timestamp;
            emit VideoBecameFirstInQueue(videoDetails[_currentVideoTokenId.current()], currentVideoStartTime);
        } else {
            currentVideoStartTime = 0;
            emit VideoBecameFirstInQueue(Video ({
                videoId: "",
                minTime: 0,
                playbackStartTime: 0
            }), 0);
        }

        uint256 gasRefund = tx.gasprice * gasleft();

        if (gasRefund > maxRefund) {
            gasRefund = maxRefund;
        }

        payable(msg.sender).transfer(gasRefund);
    }

    function getCurrentVideo() external view returns (Video memory) {
        if (_currentVideoTokenId.current() <= _tokenIds.current()) {
            return videoDetails[_currentVideoTokenId.current()];
        } else {
            return Video({
                videoId: "",
                minTime: 0,
                playbackStartTime: 0
            });
        }
    }

    function getCurrentVideoStartTime() external view returns (uint256) {
        return currentVideoStartTime;
    }

    function getVideoData(uint256 tokenId) public view returns (Video memory video) {
        require(_exists(tokenId), "Token does not exist");
        return videoDetails[tokenId];
    }

    function changeQueueSpotVideoDetails(string memory _videoId, uint256 _playbackStartTime, uint256 _tokenId) external validVideoId(_videoId) {
        require(_exists(_tokenId), "Token does not exist");
        require(_tokenId > _currentVideoTokenId.current(), "Video details are unalterable at this point in the queue");
        require(ownerOf(_tokenId) == msg.sender, "Only the owner can change video details");
        uint256 videoMinTime = videoDetails[_tokenId].minTime;

        Video memory newVideoDetails = Video ({
            videoId: _videoId,
            minTime: videoMinTime,
            playbackStartTime: _playbackStartTime
        });

        videoDetails[_tokenId] = newVideoDetails;
        emit VideoDetailsUpdated(newVideoDetails, _tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory _data) public override {
        require(tokenId > _currentVideoTokenId.current(), "Cannot transfer NFT after the video has started playing");
        super.safeTransferFrom(from, to, tokenId, _data);
    }

    function transferFrom(address from, address to, uint256 tokenId) public override {
        require(tokenId > _currentVideoTokenId.current(), "Cannot transfer NFT after the video has started playing");
        super.transferFrom(from, to, tokenId);
    }

    function listQueueSpot(uint256 tokenId, uint256 price) public {
        require(tokenId > _currentVideoTokenId.current(), "Cannot transfer NFT after the video has started playing");
        approve(address(this), tokenId);
        Listing memory listing =  Listing ({
            isForSale: true,
            price: price
        });
        listings[tokenId] = listing;
        emit newListing(tokenId, listing);
    }

    function buyListedQueueSpot(uint256 tokenId) public payable {
        require(tokenId > _currentVideoTokenId.current(), "Cannot transfer NFT after the video has started playing");
        Listing memory listing = listings[tokenId];
        require(listing.isForSale == true, "This Queue Spot is not for sale");
        require(msg.value >= listing.price, "Insufficient payment!");
        _transfer(ownerOf(tokenId), msg.sender, tokenId);
        delete listings[tokenId];
    }

    function voteOnVideo(uint256 tokenId, bool wasGoodVideo) public {
        require(_exists(tokenId), "Token does not exist");
        require(voting[tokenId].endTimeStamp > 0, "Voting has not started on this video");
        require(block.timestamp <= voting[tokenId].endTimeStamp, "Voting period is over");
        require(!voting[tokenId].hasVoted[msg.sender], "You can only vote once");
        require(firstPeriodEligibleForRewards[msg.sender] <= voting[tokenId].releasePeriod, "You must have submitted a good video before this videos release period to vote");
        if (wasGoodVideo) {
            voting[tokenId].good += 1;
        } else {
            voting[tokenId].bad += 1;
        }
        voting[tokenId].hasVoted[msg.sender] = true;
        emit VoteCasted(tokenId, wasGoodVideo);
        releasePeriodInfo[voting[tokenId].releasePeriod].numVotesCastedThisPeriod[msg.sender] += 1;
        releasePeriodInfo[voting[tokenId].releasePeriod].totalVotesCasted += 1;
    }

    function wasItAGoodVideo(uint256 tokenId) public {
        require(voting[tokenId].endTimeStamp > 0, "Voting has not started on this video");
        require(block.timestamp > voting[tokenId].endTimeStamp, "Voting period is still in progress");
        require(voting[tokenId].good > voting[tokenId].bad, "Your video was not good"); 
        require(voting[tokenId].releasePeriod + 1 < firstPeriodEligibleForRewards[ownerOf(tokenId)] || firstPeriodEligibleForRewards[ownerOf(tokenId)] == 0, "This tokenId would not change your firstPeriodEligibleForRewards");
        if (firstPeriodEligibleForRewards[ownerOf(tokenId)] == 0) {
            _goodVideoSubmitters.increment();
        }
        firstPeriodEligibleForRewards[ownerOf(tokenId)] = _currentReleasePeriod.current() + 1;
    }

    function receivePeriodFunds(uint256 _releasePeriod) public {
        require(_currentReleasePeriod.current() > _releasePeriod, "This period has not concluded"); 
        require(releasePeriodInfo[_releasePeriod].hasReceivedShare[msg.sender] == false, "You have already received this periods rewards");
        require(firstPeriodEligibleForRewards[msg.sender] > 0, "You have never submitted a good video");
        require(firstPeriodEligibleForRewards[msg.sender] <= _releasePeriod, "You are not eligible for this rewards period in the argument");
        uint256 rewardsShare = releasePeriodInfo[_releasePeriod].rewards / releasePeriodInfo[_releasePeriod].numReceiversThisPeriod;
        releasePeriodInfo[_releasePeriod].hasReceivedShare[msg.sender] = true;

        (bool success, ) = payable(msg.sender).call{value: rewardsShare}("");
        require(success, "Failed to send ether to caller");
    }
}
