//SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "./strings.sol";
import "./SafeMath.sol";
import "./PA.sol";
 

contract TenderingSmartContract is PA {

    using SafeMath for uint;
    using strings for *;

    address owner;
    mapping (address => bool) private allowedInstitution;

    struct BiddingOffer {
        address contractor;
        bytes32 hashOffer;
        bool valid;
        string description;
        string separator;
        string[] NewDescription;
    }

    struct Tender {
        uint256 tender_id;
        uint256 bidOpeningDate;
        uint256 bidSubmissionClosingDateData;
        uint256 bidSubmissionClosingDateHash;
        uint[] evaluation_weights;
        mapping(address => BiddingOffer) bids;
        mapping(address => uint) addressToScore;
        mapping(address => bool) AlreadyBid;
        address tenderingInstitution;
        address winningContractor;
        string tenderName;
        string description;
    }

    struct Weights {
        uint w1;
        uint w2;
        uint w3;
        uint w4;
        uint w5;
        uint w6;
    }

    uint[] private tenderList;
    uint private tenderKeys;
    mapping (uint => Tender) private tenders; 

    mapping(uint => address[]) private _participants;
    mapping(uint => uint[])  private _scores;
    

    modifier inTimeHash (uint256 _tenderKey) {
        require(
        (block.timestamp >= tenders[_tenderKey].bidOpeningDate) && (block.timestamp <= tenders[_tenderKey].bidSubmissionClosingDateHash),
        "hash sent before the opening date or after the hash closing date!"
        );
        _;
    }


    modifier AlreadyPlacedBid(uint256 _tenderKey) {
        require(
            (tenders[_tenderKey].AlreadyBid[msg.sender] != true),
        "Bid already placed for this tender!"
        );
        _;
    }


    modifier inTimeData (uint256 _tenderKey) {
        require(
        (block.timestamp >= tenders[_tenderKey].bidSubmissionClosingDateHash) && (block.timestamp < tenders[_tenderKey].bidSubmissionClosingDateData),
        "data sent before the hash closing date or after the data closing date."
        );
        _;
    }


    modifier afterDeadline (uint256 _tenderKey) {
        require(tenders[_tenderKey].bidSubmissionClosingDateData < block.timestamp);
        _;
    }


    function CreateTender(string calldata _tenderName, string calldata _description,uint256 _daysUntilClosingDateData, uint256 _daysUntilClosingDateHash,
                            string calldata _weights) external onlyPA{
        string[] memory weights = SMT(_weights, '-');
        uint sum = parseInt(weights[0]).add(parseInt(weights[1]).add(parseInt(weights[2]).add(parseInt(weights[5]))));
        require(sum == 100, 'sum must be 100');
        // new weight sum
        uint sum2 = parseInt(weights[3]).add(parseInt(weights[4]));
        require(sum2 == 100, 'Sum of two environment parameters must be 100');

        require(_daysUntilClosingDateData > _daysUntilClosingDateHash);
        
        Tender storage c = tenders[tenderKeys];
        c.tender_id = tenderKeys;
        c.tenderName = _tenderName;
        c.description = _description;
        c.bidOpeningDate = block.timestamp;
        c.bidSubmissionClosingDateHash= block.timestamp + (_daysUntilClosingDateHash* 1 seconds);
        c.bidSubmissionClosingDateData = block.timestamp + (_daysUntilClosingDateData* 1 seconds);
        c.tenderingInstitution = msg.sender;
        c.evaluation_weights.push(parseInt(weights[0]));
        c.evaluation_weights.push(parseInt(weights[1]));
        c.evaluation_weights.push(parseInt(weights[2]));
        c.evaluation_weights.push(parseInt(weights[3]));
        c.evaluation_weights.push(parseInt(weights[4]));
        c.evaluation_weights.push(parseInt(weights[5]));
        tenderKeys ++;

            }

    function placeBid (uint256 _tenderKey, bytes32 _hashOffer) external onlyFirm inTimeHash(_tenderKey) AlreadyPlacedBid(_tenderKey) {
        Tender storage c = tenders[_tenderKey];

        c.AlreadyBid[msg.sender] = true;
        c.bids[msg.sender] = BiddingOffer(msg.sender,_hashOffer,false,"","", new string[](0));
    }
    

    function concludeBid(uint256 _tenderKey, string calldata _description, string calldata _separator) external onlyFirm inTimeData(_tenderKey) {


        require(tenders[_tenderKey].bids[msg.sender].contractor == msg.sender);
        require(keccak256(abi.encodePacked(_description)) == tenders[_tenderKey].bids[msg.sender].hashOffer);
        Tender storage c = tenders[_tenderKey];
        c.bids[msg.sender].description = _description;
        c.bids[msg.sender].separator = _separator;
        c.bids[msg.sender].valid = true;
        _participants[_tenderKey].push(msg.sender);
    }
    

    function SMT(string memory _phrase,string memory _separator ) private pure returns(string[] memory) {
        strings.slice memory s = _phrase.toSlice();
        strings.slice memory delim = _separator.toSlice();
        string[] memory parts = new string[](s.count(delim));
        for (uint i = 0; i < parts.length; i++) {
           parts[i] = s.split(delim).toString();
        }

        return (parts);
    }


    function parseInt(string memory _value) private pure returns (uint _ret) {
        bytes memory _bytesValue = bytes(_value);
        uint j = 1;
        for(uint i = _bytesValue.length-1; i >= 0 && i < _bytesValue.length; i--) {
            assert(uint8(_bytesValue[i]) >= 48 && uint8(_bytesValue[i]) <= 57);
            _ret += (uint8(_bytesValue[i]) - 48)*j;
            j*=10;
        }
    }
    

    function splitDescription(uint256 _tenderKey) private onlyPA afterDeadline(_tenderKey) {
        for (uint i=0; i < _participants[_tenderKey].length; i++){
             string memory separatorToUse  = tenders[_tenderKey].bids[_participants[_tenderKey][i]].separator;
            string memory descriptionAtTheMoment = tenders[_tenderKey].bids[_participants[_tenderKey][i]].description;
            tenders[_tenderKey].bids[_participants[_tenderKey][i]].NewDescription = SMT(descriptionAtTheMoment,separatorToUse);
        }
    }


    function adjust_measures(uint _parameterToCompare, uint _parameterToModify) private pure returns(uint) {

        uint base;
        
        uint _temp = _parameterToCompare;
        while (_temp / (10) != 0) {
            _temp = _temp / 10;
            base++;
        }
        return ( _parameterToModify.mul(10 ** base));
    }

    function environment_score(uint _firmExperience, uint _percentStrengthToNeeds, uint w4, uint w5) private pure returns(uint) {
        uint adjustedExp = adjust_measures(_percentStrengthToNeeds, _firmExperience);
        uint envScore = w4.mul(adjustedExp);
        envScore = envScore.add(w5.mul(_percentStrengthToNeeds));

        return envScore;
    }

    function getWeights(uint _tenderKey) private view returns(Weights memory) {
        Weights memory w;
        w.w1 = tenders[_tenderKey].evaluation_weights[0];
        w.w2 = tenders[_tenderKey].evaluation_weights[1];
        w.w3 = tenders[_tenderKey].evaluation_weights[2];
        w.w4 = tenders[_tenderKey].evaluation_weights[3];
        w.w5 = tenders[_tenderKey].evaluation_weights[4];
        w.w6 = tenders[_tenderKey].evaluation_weights[5];

        return w;
    }

    function compute_scores(uint _tenderKey) external onlyPA afterDeadline(_tenderKey) {
        require(msg.sender == tenders[_tenderKey].tenderingInstitution);

        Weights memory w = getWeights(_tenderKey);

        splitDescription(_tenderKey);

        for (uint i = 0; i < _participants[_tenderKey].length; i++){
            address  target_address = _participants[_tenderKey][i];
            BiddingOffer  memory to_store= tenders[_tenderKey].bids[target_address];
            if (to_store.valid == true){
                uint price = parseInt(to_store.NewDescription[0]);
                uint timing = adjust_measures(price, parseInt(to_store.NewDescription[1]));
                uint environment = adjust_measures(price, environment_score(parseInt(to_store.NewDescription[2]), parseInt(to_store.NewDescription[3]), w.w4, w.w5));
                uint previousPerformance = adjust_measures(price, parseInt(to_store.NewDescription[4]));

                uint score = w.w1.mul(price);
                score = score.add(w.w2.mul(timing));
                score = score.add(w.w3.mul(environment));
                score = score.add(w.w6.mul(previousPerformance));

               _scores[_tenderKey].push(score);
               tenders[_tenderKey].addressToScore[to_store.contractor] = score;
            }
        }
    }

    function assign_winner(uint _tenderKey) external onlyPA afterDeadline(_tenderKey) {
        require(msg.sender == tenders[_tenderKey].tenderingInstitution);
        uint winning_score = _scores[_tenderKey][0];
        uint winning_index;

        for (uint i = 1; i < _participants[_tenderKey].length; i++){
            uint score = _scores[_tenderKey][i];

            if (score < winning_score){
                winning_score = score;
                winning_index = i;
            }
        }
        tenders[_tenderKey].winningContractor = _participants[_tenderKey][winning_index];
    }

    function displayWinner(uint _tenderKey) external view afterDeadline(_tenderKey) returns (address, uint) {
        return (tenders[_tenderKey].winningContractor, tenders[_tenderKey].addressToScore[tenders[_tenderKey].winningContractor]);
    }

    function getResultsLenght(uint _tenderKey) external view afterDeadline(_tenderKey) returns(uint) {
        return _participants[_tenderKey].length;
    }

    function getResultsValue(uint _tenderKey, uint _index) external view afterDeadline(_tenderKey) returns (address,uint, bool) {

        bool is_winner;
        if (tenders[_tenderKey].winningContractor == _participants[_tenderKey][_index]) {
            is_winner = true;
        } else {
            is_winner = false;
        }

        return (_participants[_tenderKey][_index], _scores[_tenderKey][_index], is_winner);
    }


    function getBidDetails(uint _tenderKey, address _index) external view afterDeadline(_tenderKey) returns (address, string[] memory, string memory, uint, bool) {
        address name_contractor = tenders[_tenderKey].bids[_index].contractor;
        string[] memory text_description = tenders[_tenderKey].bids[_index].NewDescription;
        string memory sep = tenders[_tenderKey].bids[_index].separator; // thus, one can check if the score was correct by using the separator and the description

        bool is_winner;
        if (tenders[_tenderKey].winningContractor == _index) {
            is_winner = true;
        } else {
            is_winner = false;
        }

        uint score = tenders[_tenderKey].addressToScore[_index];

        return (name_contractor, text_description, sep, score, is_winner);
    }


    function getTendersLength() external view returns(uint) {
        return (tenderKeys);
    }

    function isPending(uint _tenderKey) external view returns(uint, bool) {

        bool pending_status;

        if (tenders[_tenderKey].bidSubmissionClosingDateHash > block.timestamp) {
            pending_status = true;
        } else {
            pending_status = false;
        }
        return (_tenderKey, pending_status);
    }

    function see_TenderDetails(uint _tenderKey) external view returns (uint  tender_id, string memory tenderName,string memory description,
                                uint[] memory evaluation_weights, uint firms, address winningContractor){

        return (tenders[_tenderKey].tender_id, tenders[_tenderKey].tenderName, tenders[_tenderKey].description, tenders[_tenderKey].evaluation_weights, _participants[_tenderKey].length, tenders[_tenderKey].winningContractor);

    }

}

