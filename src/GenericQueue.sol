// pragma solidity >=0.8.0 <0.9.0;
// 
// import "./Queue.sol";
// 
// contract GenericQueue is Queue {
//     uint256 public immutable identifierLength;
//     string public immutable identifierCharacterAllowString;
// 
//     constructor(
//         string memory _name,
//         string memory _symbol,
//         string memory _queueURI,
//         uint256 _minTimeActive,
//         uint256 _costPerSecond,
//         uint256 _votePeriodLength,
//         uint256 _releasePeriodLength,
//         address _voteFundDonationAddress,
//         address _initialVoter,
//         uint256 _initialVoteInfluence,
//         uint256 _maxRefund,
//         uint256 _identifierLength,
//         string memory _identifierCharacterAllowString
//     ) Queue(
//         _name,
//         _symbol,
//         _queueURI,
//         _minTimeActive,
//         _costPerSecond,
//         _votePeriodLength,
//         _releasePeriodLength,
//         _voteFundDonationAddress,
//         _initialVoter,
//         _initialVoteInfluence,
//         _maxRefund
//     ) {
//         identifierLength = _identifierLength;
//         identifierCharacterAllowString = _identifierCharacterAllowString;
//     }
// 
//     modifier validIdentifier(string memory _identifier) override {
//         require(bytes(_identifier).length == identifierLength, "Invalid identifier length");
// 
//         for (uint i = 0; i < bytes(_identifier).length; i++) {
//             bool isValidCharacter = false;
//             bytes memory allowListBytes = bytes(identifierCharacterAllowString);
//             for (uint j = 0; j < allowListBytes.length; j++) {
//                 if (bytes(_identifier)[i] == allowListBytes[j]) {
//                     isValidCharacter = true;
//                     break;
//                 }
//             }
//             require(isValidCharacter, "Invalid character in identifier");
//         }
//         _;
//     }
// }
