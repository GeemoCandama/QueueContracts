pragma solidity >=0.8.0 <0.9.0;

import "openzeppelin-contracts/token/ERC721/ERC721.sol";
import "openzeppelin-contracts/utils/Counters.sol";

/**
 * @title A Contract for queues with spots in the queue being NFTs.
 * @dev This contract uses OpenZeppelin's ERC721 implementation.
 */
abstract contract Queue is ERC721 {
    using Counters for Counters.Counter;

    struct TokenDetails {
        string identifier;
        uint256 timeActive;
        uint256 playerStartTime;
    }

    struct Offer {
        uint256 price;
        address offerer;
        uint256 tokenId;
    }

    struct VotePeriod {
        uint256 endTimeStamp;
        uint256 good;
        uint256 bad;
        uint256 tokensReleasePeriod;
        mapping(address => bool) hasVoted;
    }

    /**
     * @dev A release period is used to average across all tokens in the interval.
     * Without this we would expect to see items queued for longer to attract more voters
     * because of the costPerSecond variable.
     */
    struct ReleasePeriod {
        uint256 startTimestamp;
        uint256 rewards;
        uint256 totalVotesCasted;
        mapping(address => uint256) numVotesCastedThisPeriod;
        mapping(address => bool) hasReceivedShare;
    }

    struct VoteData {       
        uint256 good;
        uint256 bad;
    }    

    /**
     * @dev We use the isForSale boolean to support zero cost listings.
     */
    struct Listing {
        bool isForSale;
        uint256 price;
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

    uint256 public activeTokenStartTime;

    Counters.Counter public tokenCounter;
    Counters.Counter public activeTokenCounter;
    Counters.Counter public activeReleasePeriodCounter;
    Counters.Counter public offerCounter;

    // MetaData: queueURI is the uri associated with every token in the queue
    string public queueURI; 
    uint256 public immutable votePeriodLength;
    uint256 public immutable releasePeriodLength;
    uint256 public immutable costPerSecond;
    uint256 public immutable maxRefund;
    uint256 public immutable minTimeActive;

    address immutable voteFundDonationAddress;
    uint256 donationAddressFunds;

    uint256 private previousReleasePeriodEndTimeStamp;

    event TokenEnqueued(string identifier, uint256 timeActive, uint256 playerStartTime, uint256 indexed tokenId);
    event NewActiveToken(string identifier, uint256 timeActive, uint256 playerStartTime, uint256 indexed tokenId, uint256 timestamp);
    event ActiveTokenDequeued(uint256 indexed tokenId, uint256 indexed endTimeStamp, uint256 indexed releasePeriod);
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
     * @param _maxRefund The largest gas refund provided during a call to dequeue. This parameter will greatly influence the 
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
        uint256 _maxRefund
    ) ERC721(_name, _symbol) {
        require(_releasePeriodLength > _votePeriodLength, "Release period length must be greater than vote period length");
        require(_initialVoteInfluence > 0, "The initial vote influence of the initialVoter must be positive");
        require(_initialVoter != address(0), "initialVoter address cannot be 0");
        require(_maxRefund < _costPerSecond * _minTimeActive, "max refund must be sustainable via enqueue");
        queueURI = _queueURI;  
        minTimeActive = _minTimeActive;
        costPerSecond = _costPerSecond;

        maxRefund = _maxRefund;
        // We increment this at the start so there is no token of this value
        activeTokenCounter.increment();
        activeReleasePeriodCounter.increment();
        releasePeriodInfo[1].startTimestamp = block.timestamp;

        votePeriodLength = _votePeriodLength;
        releasePeriodLength = _releasePeriodLength;

        voteFundDonationAddress = _voteFundDonationAddress;
        voteInfluenceBalance[_initialVoter] = _initialVoteInfluence;
        queueURI = _queueURI;
    }

    modifier validIdentifier(string memory _identifier) virtual;

    function enqueue(string memory _identifier, uint256 _timeActive, uint256 _playerStartTime) external payable validIdentifier(_identifier) {
        require(_timeActive >= minTimeActive, "_timeActive must be greater than minTimeActive");
        uint256 requiredPayment = _timeActive * costPerSecond;
        require(msg.value >= requiredPayment, "Insufficient payment");

        TokenDetails memory newTokenDetails = TokenDetails ({
            identifier: _identifier,
            timeActive: _timeActive,
            playerStartTime: _playerStartTime
        });

        tokenCounter.increment();
        uint256 newTokenId = tokenCounter.current();
        _safeMint(msg.sender, newTokenId); 
        tokenDetails[newTokenId] = newTokenDetails;
        emit TokenEnqueued(_identifier, _timeActive, _playerStartTime, newTokenId);

        if (activeTokenCounter.current() == tokenCounter.current()) {
            activeTokenStartTime = block.timestamp;
            emit NewActiveToken(_identifier, _timeActive, _playerStartTime, newTokenId, block.timestamp);
        }
        releasePeriodInfo[activeReleasePeriodCounter.current()].rewards += msg.value;
    }

    /**
     * @dev Increment activeTokenCounter if the activeToken's timeActive has passed.
     * This function acts as the timekeeper of the contract. It updates the releasePeriod and active token up.
     * ~Security~ This function refunds the gas used on this function internal/external transaction.
     */
    function dequeue() external {
        uint256 startGas = gasleft();
        uint256 activeTokenId = activeTokenCounter.current();
        uint256 totalTokens = tokenCounter.current();
        require(activeTokenId <= totalTokens, "No tokens in the queue");

        TokenDetails memory activeToken = tokenDetails[activeTokenId];
        uint256 elapsedTime = block.timestamp - activeTokenStartTime;

        require(elapsedTime >= activeToken.timeActive, "active time not reached");
        uint256 activeReleasePeriodPriorToPotentialUpdate = activeReleasePeriodCounter.current();

        voting[activeTokenId].endTimeStamp = block.timestamp + votePeriodLength;
        voting[activeTokenId].tokensReleasePeriod = activeReleasePeriodPriorToPotentialUpdate;
        emit ActiveTokenDequeued(activeTokenId, block.timestamp + votePeriodLength, activeReleasePeriodPriorToPotentialUpdate);
        uint256 activeReleasePeriodTimestamp = releasePeriodInfo[activeReleasePeriodPriorToPotentialUpdate].startTimestamp;

        if (block.timestamp >= activeReleasePeriodTimestamp + releasePeriodLength) {
            uint256 queuedGasCosts;
            if (activeTokenCounter.current() > totalTokens) {
                queuedGasCosts = 0;
            } else {
                queuedGasCosts = (totalTokens - activeTokenId) * maxRefund;
            }

            releasePeriodInfo[activeReleasePeriodPriorToPotentialUpdate].rewards -= queuedGasCosts;
            activeReleasePeriodCounter.increment();
            releasePeriodInfo[activeReleasePeriodPriorToPotentialUpdate + 1].startTimestamp = block.timestamp;
        }

        activeTokenCounter.increment();
        uint256 newActiveTokenId = activeTokenCounter.current();

        if (newActiveTokenId <= totalTokens) {
            activeTokenStartTime = block.timestamp;
            TokenDetails memory newTokenDetails = tokenDetails[newActiveTokenId];
            emit NewActiveToken(newTokenDetails.identifier, newTokenDetails.timeActive, newTokenDetails.playerStartTime, newActiveTokenId, block.timestamp);
        } else {
            activeTokenStartTime = 0;
            emit NewActiveToken("", 0, 0, 0, 0);
        }

        uint256 gasSpent = startGas - gasleft();
        if (maxRefund > 0) {
            uint256 gasCost = tx.gasprice * (gasSpent + 2300);
            if (gasCost > maxRefund) {
                gasCost = maxRefund;
                if (gasCost > address(this).balance) {
                    payable(msg.sender).transfer(address(this).balance);
                } else {
                    payable(msg.sender).transfer(gasCost);
                }
            }
        }
    }

    function getActiveTokenDetails() external view returns (TokenDetails memory) {
        require(activeTokenCounter.current() <= tokenCounter.current(), "There are no tokens in queue");
        return tokenDetails[activeTokenCounter.current()];
    }

    function getTokenDetails(uint256 _tokenId) public view returns (TokenDetails memory) {
        require(_exists(_tokenId), "Token does not exist");
        return tokenDetails[_tokenId];
    }

    function changeTokenDetails(string memory _identifier, uint256 _playerStartTime, uint256 _tokenId) external validIdentifier(_identifier) {
        require(_exists(_tokenId), "Token does not exist");
        require(_tokenId > activeTokenCounter.current(), "Spot details are unalterable once active");
        require(ownerOf(_tokenId) == msg.sender, "Only the owner can change token details");

        TokenDetails memory newTokenDetails = TokenDetails ({
            identifier: _identifier,
            timeActive: tokenDetails[_tokenId].timeActive,
            playerStartTime: _playerStartTime
        });

        tokenDetails[_tokenId] = newTokenDetails;
        emit TokenDetailsUpdated(_identifier, _playerStartTime, _tokenId);
    }

    function safeTransferFrom(address _from, address _to, uint256 _tokenId, bytes memory _data) public override {
        require(_tokenId > activeTokenCounter.current(), "Cannot transfer token once active");
        super.safeTransferFrom(_from, _to, _tokenId, _data);
        delete listings[_tokenId];
    }

    function transferFrom(address _from, address _to, uint256 _tokenId) public override {
        require(_tokenId > activeTokenCounter.current(), "Cannot transfer token once active");
        super.transferFrom(_from, _to, _tokenId);
        delete listings[_tokenId];
    }


    //--------------------OFFER/LIST FUNCTIONS----------------------

    function listToken(uint256 _tokenId, uint256 _price) public {
        require(_tokenId > activeTokenCounter.current(), "Cannot list token once active");
        approve(address(this), _tokenId);
        Listing memory listing =  Listing ({
            isForSale: true,
            price: _price
        });
        listings[_tokenId] = listing;
        emit NewListing(_tokenId, listing);
    }

    function buyListedQueueToken(uint256 _tokenId) public payable {
        require(_tokenId > activeTokenCounter.current(), "Cannot transfer token once active");
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
        require(_tokenId > activeTokenCounter.current(), "Cannot make an offer on a token once active");
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
        require(offerToAccept.tokenId > activeTokenCounter.current(), "Cannot accept offers once token is active");
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
        require(voting[_tokenId].endTimeStamp > 0, "Voting has not started on this token");
        require(block.timestamp <= voting[_tokenId].endTimeStamp, "Voting period is over");
        require(!voting[_tokenId].hasVoted[msg.sender], "You can only vote once");
        uint256 voteInfluence = voteInfluenceBalance[msg.sender];
        require(voteInfluence > 0, "You don't have any voting eligible tokens");
        if (_wasGoodIdentifier) {
            voting[_tokenId].good += voteInfluence;
            allVotes[msg.sender].good += voteInfluence;
        } else {
            voting[_tokenId].bad += voteInfluence;
            allVotes[msg.sender].bad += voteInfluence;
        }
        voting[_tokenId].hasVoted[msg.sender] = true;
        emit VoteCasted(_tokenId, _wasGoodIdentifier, msg.sender, voteInfluence);
        releasePeriodInfo[voting[_tokenId].tokensReleasePeriod].numVotesCastedThisPeriod[msg.sender] += voteInfluence;
        releasePeriodInfo[voting[_tokenId].tokensReleasePeriod].totalVotesCasted += voteInfluence; 
    }

    function upgradeToVotingToken(uint256 _tokenId) public {
        require(voting[_tokenId].endTimeStamp > 0, "Voting has not started on this token");
        require(block.timestamp > voting[_tokenId].endTimeStamp, "Voting period is still in progress");
        require(voting[_tokenId].good > voting[_tokenId].bad, "Your token was not good"); 
        require(activeReleasePeriodCounter.current() > voting[_tokenId].tokensReleasePeriod);
        voteInfluenceBalance[ownerOf(_tokenId)] += 1;
    }

    //-----------------------RECEIVE PAYOUT FUNCTIONS-------------------------

    function receivePeriodFunds(uint256 _releasePeriod) public {
        require(activeReleasePeriodCounter.current() > _releasePeriod, "This period has not concluded"); 
        require(block.timestamp > releasePeriodInfo[_releasePeriod].startTimestamp + votePeriodLength, "Wait for votes from the previous period to finish");
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

    function receiveDonatedFunds() public {
        require(msg.sender == voteFundDonationAddress, "You must be the donation address");
        uint256 val = donationAddressFunds;
        donationAddressFunds = 0;
        (bool success, ) = payable(msg.sender).call{value: val}("");
        require(success, "Failed to send ether to caller");
    }
    //END--------------------RECEIVE PAYOUT FUNCTIONS-------------------------
}
