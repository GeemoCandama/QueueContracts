pragma solidity ^0.8.0;

import "openzeppelin-contracts/token/ERC721/ERC721.sol";
import "openzeppelin-contracts/utils/Counters.sol";

contract VideoQueue is ERC721 {
    using Counters for Counters.Counter;
    Counters.Counter public _tokenIds;
    Counters.Counter public _currnetVideotokenId;

    struct Video {
        string videoId;
        uint256 minTime;
        uint256 playbackStartTime;
    }

    struct Listing {
        bool isForSale;
        uint256 price;
    }

    mapping(uint256 => Video) public videoDetails;
    mapping(uint256 => Listing) public listings;

    uint256 public currentVideoStartTime;
    uint256 public costPerSecond;

    event VideoBecameFirstInQueue(Video video, uint256 timestamp);
    event VideoDetailsUpdated(Video video, uint256 indexed tokenId);
    event newListing(uint256 indexed tokenId, Listing listing);

    constructor(uint256 _costPerSecond) ERC721("QueueSpot", "QSPT") {
        costPerSecond = _costPerSecond;
        _currnetVideotokenId.increment();
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

        if (_currnetVideotokenId.current() == _tokenIds.current()) {
            currentVideoStartTime = block.timestamp;
            emit VideoBecameFirstInQueue(newVideo, currentVideoStartTime);
        }
    }

    function dequeue() external {
        require(_currnetVideotokenId.current() <= _tokenIds.current(), "No videos in the queue");

        Video memory firstVideo = videoDetails[_tokenIds.current()];
        uint256 elapsedTime = block.timestamp - currentVideoStartTime;

        require(elapsedTime >= firstVideo.minTime, "Minimum playtime not reached");

        _currnetVideotokenId.increment();

        if (_currnetVideotokenId.current() <= _tokenIds.current()) {
            currentVideoStartTime = block.timestamp;
            emit VideoBecameFirstInQueue(videoDetails[_currnetVideotokenId.current()], currentVideoStartTime);
        } else {
            currentVideoStartTime = 0;
            emit VideoBecameFirstInQueue(Video ({
                videoId: "",
                minTime: 0,
                playbackStartTime: 0
            }), 0);
        }

        uint256 gasRefund = tx.gasprice * gasleft();
        uint256 maxRefund = firstVideo.minTime * costPerSecond;

        if (gasRefund > maxRefund) {
            gasRefund = maxRefund;
        }

        payable(msg.sender).transfer(gasRefund);
    }

    function getCurrentVideo() external view returns (Video memory) {
        if (_currnetVideotokenId.current() <= _tokenIds.current()) {
            return videoDetails[_currnetVideotokenId.current()];
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
        require(_tokenId > _currnetVideotokenId.current(), "Video details are unalterable at this point in the queue");
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
        require(tokenId > _currnetVideotokenId.current(), "Cannot transfer NFT after the video has started playing");
        super.safeTransferFrom(from, to, tokenId, _data);
    }

    function transferFrom(address from, address to, uint256 tokenId) public override {
        require(tokenId > _currnetVideotokenId.current(), "Cannot transfer NFT after the video has started playing");
        super.transferFrom(from, to, tokenId);
    }

    function listQueueSpot(uint256 tokenId, uint256 price) public {
        require(tokenId > _currnetVideotokenId.current(), "Cannot transfer NFT after the video has started playing");
        approve(address(this), tokenId);
        Listing memory listing =  Listing ({
            isForSale: true,
            price: price
        });
        listings[tokenId] = listing;
        emit newListing(tokenId, listing);
    }

    function buyListedQueueSpot(uint256 tokenId) public payable {
        require(tokenId > _currnetVideotokenId.current(), "Cannot transfer NFT after the video has started playing");
        Listing memory listing = listings[tokenId];
        require(listing.isForSale == true, "This Queue Spot is not for sale");
        require(msg.value >= listing.price, "Insufficient payment!");
        _transfer(ownerOf(tokenId), msg.sender, tokenId);
        delete listings[tokenId];
    }
}
