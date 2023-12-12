pragma solidity >=0.8.0 <0.9.0;

import "openzeppelin-contracts/token/ERC721/ERC721.sol";
import "openzeppelin-contracts/utils/Counters.sol";

/**
 * @title A Contract for queues with spots in the queue being NFTs.
 * @dev This contract uses OpenZeppelin's ERC721 implementation.
 */
abstract contract QueueV2 is ERC721 {
    using Counters for Counters.Counter;

    struct TokenDetails {
        string identifier;
        uint256 timeActive;
        uint256 playerStartTime;
        uint256 startTime;
        uint256 releasePeriod;
    }

    struct Offer {
        uint256 price;
        address offerer;
        uint256 tokenId;
    }

    struct VotePeriod {
        uint256 good;
        uint256 bad;
        mapping(address => bool) hasVoted;
    }

    /**
     * @dev A release period is used to average across all tokens in the interval.
     * Without this we would expect to see items queued for longer to attract more voters
     * because of the costPerSecond variable.
     */
    struct ReleasePeriod {
        uint256 rewards;
        uint256 totalVotesCasted;
        mapping(address => uint256) numVotesCastedThisPeriod;
        mapping(address => bool) hasReceivedShare;
        uint256 endTimeStamp;
    }

    /**
     * @dev We use the isForSale boolean to support zero cost listings.
     */
    struct Listing {
        bool isForSale;
        uint256 price;
    }

    struct VoteData {       
        uint256 good;
        uint256 bad;
    }    

    /**
     * @dev Map from token id to token details.
     */
    mapping(uint256 => TokenDetails) public tokenDetails;

    /**
     * @dev Map from token id to Listing.
     */
    mapping(uint256 => Listing) public listings;

    /**
     * @dev Map from offer_id to Offer.
     */
    mapping(uint256 => Offer) public offers;

    /**
     * @dev Map from token id to VotePeriod.
     */
    mapping(uint256 => VotePeriod) public voting;

    /**
     * @dev Map from release period id to ReleasePeriod.
     */
    mapping(uint256 => ReleasePeriod) public releasePeriodInfo;

    /**
     * @dev Map from addresses to the number of voting tokns they hold.
     */
    mapping(address => uint256) public voteInfluenceBalance;

    /**
     * @dev Map from addresses to the number of good and bad votes they have made.
     */
    mapping(address => VoteData) public allVotes;

    Counters.Counter public tokenCounter;
    Counters.Counter public offerCounter;

    // MetaData: queueURI is the uri associated with every token in the queue
    string public queueURI; 
    uint256 public immutable votePeriodLength;
    uint256 public immutable releasePeriodLength;
    uint256 public immutable costPerSecond;
    uint256 public immutable minTimeActive;
    uint256 public immutable influencePerVotingToken;

    address immutable voteFundDonationAddress;
    uint256 donationAddressFunds;

    uint256 private previousReleasePeriodEndTimeStamp;

    event TokenEnqueued(string identifier, uint256 timeActive, uint256 playerStartTime, uint256 startTime, uint256 block_timestamp, uint256 releasePeriod, uint256 indexed tokenId);
    event TokenDetailsUpdated(string identifier, uint256 playerStartTime, uint256 indexed tokenId);
    event NewListing(uint256 indexed tokenId, Listing listing);
    event NewOffer(uint256 indexed price, address indexed offerer, uint256 indexed tokenId);

    event VoteCasted(uint256 indexed tokenId, bool indexed wasGood, address indexed voter, uint256 voteInfluence);
    
    /**
     * @dev Create a new Queue token with a given name and symbol.
     * @param _name The name of the token.
     * @param _symbol The symbol of the token.
     * @param _costPerSecond The cost per second of identifiers active time.
     * @param _minTimeActive The minimum amount of time an identifier can be queued for.
     * @param _votePeriodLength The amount of time that a vote period is active.
     * @param _releasePeriodLength The amount of time between release periods.
     * @param _voteFundDonationAddress address to donate to.
     * @param _initialVoteInfluence The amount of votes that the initialVoter will have when deployed.
     * the amount of ether availabe for voting rewards. I'd recommend setting it somewhere between 1/10 and 1/100 of the cost to
     * queue the shortest token possible. Note that the actual gas cost of the dequeue function is not influenced by these parameters.
     * You can think of setting this value at 1/100 of the shortest token possible as 1% of enqueue fees going to gas refunds.
     */
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
    ) ERC721(_name, _symbol) {
        require(_initialVoteInfluence > 0, "The initial vote influence of the initialVoter must be positive");
        require(_initialVoter != address(0), "initialVoter address cannot be 0");
        queueURI = _queueURI;  
        minTimeActive = _minTimeActive;
        costPerSecond = _costPerSecond;
        influencePerVotingToken = _influencePerVotingToken;

        votePeriodLength = _votePeriodLength;
        releasePeriodLength = _releasePeriodLength;

        voteFundDonationAddress = _voteFundDonationAddress;
        voteInfluenceBalance[_initialVoter] = _initialVoteInfluence;
    }

    modifier validIdentifier(string memory _identifier) virtual;

    function enqueue(string memory _identifier, uint256 _timeActive, uint256 _playerStartTime) external payable validIdentifier(_identifier) {
        require(_timeActive >= minTimeActive, "_timeActive must be greater than minTimeActive");
        uint256 requiredPayment = _timeActive * costPerSecond;
        require(msg.value >= requiredPayment, "Insufficient payment");
        uint256 startTime;
        if (tokenCounter.current() == 0) {
           startTime = block.timestamp; 
        } else {
            TokenDetails memory previousTokenDetails = tokenDetails[tokenCounter.current()];
            if (previousTokenDetails.startTime + previousTokenDetails.timeActive < block.timestamp) {
                startTime = block.timestamp;
            } else {
                startTime = previousTokenDetails.startTime + previousTokenDetails.timeActive + 1;
            }
        }

        TokenDetails memory newTokenDetails = TokenDetails ({
            identifier: _identifier,
            timeActive: _timeActive,
            playerStartTime: _playerStartTime,
            startTime: startTime,
            releasePeriod: tokenCounter.current() / releasePeriodLength
        });
        if ((tokenCounter.current() + 1) % releasePeriodLength == 0 && tokenCounter.current() != 0) {
            releasePeriodInfo[(tokenCounter.current() / releasePeriodLength)].endTimeStamp = startTime + _timeActive + votePeriodLength;
        }

        tokenCounter.increment();
        uint256 newTokenId = tokenCounter.current();
        _safeMint(msg.sender, newTokenId); 
        tokenDetails[newTokenId] = newTokenDetails;
        emit TokenEnqueued(_identifier, _timeActive, _playerStartTime, startTime, block.timestamp, newTokenDetails.releasePeriod, newTokenId);

        releasePeriodInfo[newTokenDetails.releasePeriod].rewards += msg.value;
    }

    function getTokenDetails(uint256 _tokenId) public view returns (TokenDetails memory) {
        require(_exists(_tokenId), "Token does not exist");
        return tokenDetails[_tokenId];
    }

    function changeTokenDetails(string memory _identifier, uint256 _playerStartTime, uint256 _tokenId) external validIdentifier(_identifier) {
        require(_exists(_tokenId), "Token does not exist");
        require(block.timestamp < tokenDetails[_tokenId].startTime, "Token details are unalterable once active");
        require(ownerOf(_tokenId) == msg.sender, "Only the owner can change token details");

        TokenDetails memory newTokenDetails = TokenDetails ({
            identifier: _identifier,
            timeActive: tokenDetails[_tokenId].timeActive,
            playerStartTime: _playerStartTime,
            startTime: tokenDetails[_tokenId].startTime,
            releasePeriod: tokenDetails[_tokenId].releasePeriod
        });

        tokenDetails[_tokenId] = newTokenDetails;
        emit TokenDetailsUpdated(_identifier, _playerStartTime, _tokenId);
    }

    function safeTransferFrom(address _from, address _to, uint256 _tokenId, bytes memory _data) public override {
        require(block.timestamp < tokenDetails[_tokenId].startTime, "Cannot transfer token once active");
        super.safeTransferFrom(_from, _to, _tokenId, _data);
        delete listings[_tokenId];
    }

    function transferFrom(address _from, address _to, uint256 _tokenId) public override {
        require(block.timestamp < tokenDetails[_tokenId].startTime, "Cannot transfer token once active");
        super.transferFrom(_from, _to, _tokenId);
        delete listings[_tokenId];
    }


    //--------------------OFFER/LIST FUNCTIONS----------------------

    function listToken(uint256 _tokenId, uint256 _price) public {
        require(block.timestamp < tokenDetails[_tokenId].startTime, "Cannot list token once active");
        approve(address(this), _tokenId);
        Listing memory listing =  Listing ({
            isForSale: true,
            price: _price
        });
        listings[_tokenId] = listing;
        emit NewListing(_tokenId, listing);
    }

    function buyListedQueueToken(uint256 _tokenId) public payable {
        require(block.timestamp < tokenDetails[_tokenId].startTime, "Cannot transfer token once active");
        Listing memory listing = listings[_tokenId];
        require(listing.isForSale == true, "This token is not for sale");
        require(msg.value >= listing.price, "Insufficient payment!");
        _transfer(ownerOf(_tokenId), msg.sender, _tokenId);

        if (msg.value > 0) {
            (bool success, ) = payable(ownerOf(_tokenId)).call{value: msg.value}("");
            require(success, "Failed to send ether to caller");
        }
        delete listings[_tokenId];
    }

    function offer(uint256 _tokenId) public payable {
        require(block.timestamp < tokenDetails[_tokenId].startTime, "Cannot make an offer on a token once active");
        require(msg.value > 0, "0 offers arent allowed");
        Offer memory newOffer = Offer ({
           price: msg.value,
           offerer: msg.sender,
           tokenId: _tokenId
        });

        offers[offerCounter.current()] = newOffer;
        offerCounter.increment();
        emit NewOffer(msg.value, msg.sender, _tokenId);
    }

    function revokeOffer(uint256 _offerId) public {
        require(msg.sender == offers[_offerId].offerer, "only the offerer can revoke the offer");
        (bool success, ) = payable(offers[_offerId].offerer).call{value: offers[_offerId].price}("");
        require(success, "Failed to send ether to caller");
    }

    function acceptOffer(uint256 _offerId) public { 
        Offer memory offerToAccept = offers[_offerId];
        require(block.timestamp < tokenDetails[offerToAccept.tokenId].startTime, "Cannot make an offer on a token once active");
        require(msg.sender == ownerOf(offerToAccept.tokenId), "You must be the owner to accept the offer");
        
        (bool success, ) = payable(msg.sender).call{value: offerToAccept.price}("");
        require(success, "Failed to send ether to caller");

        _transfer(msg.sender, offerToAccept.offerer, offerToAccept.tokenId);
        delete listings[offerToAccept.tokenId];
        delete offers[_offerId];
    }

    //END--------------------OFFER/LIST FUCTIONS----------------------

    //-----------------------VOTING FUNCTIONS-------------------------
    
    function voteOnToken(uint256 _tokenId, bool _wasGoodIdentifier) public {
        require(_exists(_tokenId), "Token does not exist");
        uint256 endTimeStamp = tokenDetails[_tokenId].startTime + tokenDetails[_tokenId].timeActive;
        require(block.timestamp > endTimeStamp, "Voting has not started on this token");
        require(block.timestamp <= endTimeStamp + votePeriodLength, "Voting period is over");
        require(!voting[_tokenId].hasVoted[msg.sender], "You can only vote once");
        uint256 voteInfluence = voteInfluenceBalance[msg.sender] + 1;
        if (_wasGoodIdentifier) {
            voting[_tokenId].good += voteInfluence;
            allVotes[msg.sender].good += voteInfluence;
        } else {
            voting[_tokenId].bad += voteInfluence;
            allVotes[msg.sender].bad += voteInfluence;
        }
        voting[_tokenId].hasVoted[msg.sender] = true;
        emit VoteCasted(_tokenId, _wasGoodIdentifier, msg.sender, voteInfluence);
        releasePeriodInfo[tokenDetails[_tokenId].releasePeriod].numVotesCastedThisPeriod[msg.sender] += voteInfluence;
        releasePeriodInfo[tokenDetails[_tokenId].releasePeriod].totalVotesCasted += voteInfluence; 
    }

    function upgradeToVotingToken(uint256 _tokenId) public {
        require(_exists(_tokenId), "Token does not exist");
        uint256 releasePeriod = tokenDetails[_tokenId].releasePeriod;
        require(releasePeriodInfo[releasePeriod].endTimeStamp > 0 && block.timestamp > releasePeriodInfo[releasePeriod].endTimeStamp, "Ensure that voting period of last video is over");
        require(voting[_tokenId].good > voting[_tokenId].bad, "Your token was not good"); 
        voteInfluenceBalance[ownerOf(_tokenId)] += influencePerVotingToken;
    }

    //-----------------------RECEIVE PAYOUT FUNCTIONS-------------------------

    function receivePeriodFunds(uint256 _releasePeriod) public {
        // FIGURE IT OUT
        // require(activeReleasePeriodCounter.current() > _releasePeriod, "This period has not concluded"); 
        require(releasePeriodInfo[_releasePeriod].endTimeStamp > 0 && block.timestamp > releasePeriodInfo[_releasePeriod].endTimeStamp, "This period has not concluded"); 
        require(releasePeriodInfo[_releasePeriod].hasReceivedShare[msg.sender] == false, "You have already received this periods rewards");
        require(releasePeriodInfo[_releasePeriod].numVotesCastedThisPeriod[msg.sender] > 0, "You didnt vote on any tokens this period");
        uint256 rewardsUnit = releasePeriodInfo[_releasePeriod].rewards / releasePeriodInfo[_releasePeriod].totalVotesCasted;
        uint256 rewardsShare = rewardsUnit * releasePeriodInfo[_releasePeriod].numVotesCastedThisPeriod[msg.sender];  
        releasePeriodInfo[_releasePeriod].hasReceivedShare[msg.sender] = true;
        // calculate multiplier and multiply the share by it.
        uint256 multiplier = getVoterMultiplier(msg.sender);
        uint256 voterRewardsShare = rewardsShare * multiplier / 1e18; 
        if (voterRewardsShare < rewardsShare) {
           donationAddressFunds += rewardsShare - voterRewardsShare; 
        }

        (bool success, ) = payable(msg.sender).call{value: voterRewardsShare}("");
        require(success, "Failed to send ether to caller");
    }
    
    function getVoterMultiplier(address voter) public view returns (uint256) {
        // Calculate the parameters of the Beta distribution.
        uint256 alpha = allVotes[voter].good + 8;
        uint256 beta = allVotes[voter].bad + 10;
    
        // Calculate the expected value of the Beta distribution, scaled up by 1e18.
        uint256 expectedValue = (alpha * 1e18) / (alpha + beta);
    
        // Since we want a score that starts at 1 and decreases, we'll subtract the expected value from 2.
        // The multiplier will be 1 when there are equal numbers of good and bad votes, and will decrease as the number of bad votes increases.
        uint256 tempMultiplier = 5e17 + expectedValue;
    
        // Limit the multiplier to a maximum value of 1e18 (or 1 when divided by 1e18).
        uint256 multiplier = tempMultiplier > 1e18 ? 1e18 : tempMultiplier;
    
        return multiplier;
    }

    function moveEmptyVotePeriodFundsToDonateFunds(uint256 _releasePeriod) public {
        require(releasePeriodInfo[_releasePeriod].endTimeStamp > 0 && block.timestamp > releasePeriodInfo[_releasePeriod].endTimeStamp, "This period has not concluded");
        require(releasePeriodInfo[_releasePeriod].totalVotesCasted == 0, "There were more than 0 votes this period");
        donationAddressFunds += releasePeriodInfo[_releasePeriod].rewards;
    }

    function receiveDonatedFunds() public {
        require(msg.sender == voteFundDonationAddress, "You must be the donation address");
        uint256 val = donationAddressFunds;
        donationAddressFunds = 0;
        (bool success, ) = payable(msg.sender).call{value: val}("");
        require(success, "Failed to send ether to caller");
    }
    //END--------------------RECEIVE PAYOUT FUNCTIONS-------------------------
}
