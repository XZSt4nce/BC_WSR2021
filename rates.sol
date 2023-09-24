// SPDX-License-Identifier: UNLICENSE

pragma solidity ^0.8.0;

import "./productsOwner.sol";

contract rates is productsOwner {

    struct Rate {
        address addr;
        string login;
        uint8 mark;
        string text;
        uint256 time;
        uint256 likes;
        uint256 dislikes;
    }

    mapping(address => mapping(uint256 => Rate[])) public rating;
    mapping(address => uint256) ratesCount;
    mapping(address => uint256) public marksSum;
    mapping(address => uint256) public marksCount;
    mapping(address => mapping(address => mapping(uint256 => mapping(uint256 => bool)))) public isRateLiked;
    mapping(address => mapping(address => mapping(uint256 => mapping(uint256 => bool)))) public isRateDisliked;

    error TargetNotFound(address addr);
    error InvalidMark(uint8);

    modifier sellerOrStoreTarget(address _target) {
        Roles[] memory _accountRoles = addressToRoles[_target];
        bool _noAccess = true;
        for (uint256 i = 0; i < _accountRoles.length; i++) {
            if (_accountRoles[i] == Roles.Seller) {
                _noAccess = false;
                break;
            }
            if (_accountRoles[i] == Roles.Store) {
                _noAccess = false;
                break;
            }
        }
        if(_noAccess) {
            revert TargetNotFound(_target);
        }
        _;
    }

    function makeRate(address _target, uint8 _mark, string memory _text, uint256 _rateId) public registered onlyRole(Roles.Customer) sellerOrStoreTarget(_target) {
        if (_mark == 0) {
            _makeComment(_target, _rateId, _text);
        } else {
            if (_mark < 1 || _mark > 10) {
                revert InvalidMark(_mark);
            }
            string memory _login = addressToLogin[msg.sender];
            rating[_target][ratesCount[_target]++].push(Rate(msg.sender, _login, _mark, _text, block.timestamp, 0, 0));
            marksSum[_target] += _mark;
            marksCount[_target]++;
        }
    }

    function likeRate(address _target, uint256 _rateId, uint256 _index) public onlyRole(Roles.Customer) sellerOrStoreTarget(_target) {
        require(!isRateLiked[msg.sender][_target][_rateId][_index], "The rate already liked");
        rating[_target][_rateId][_index].likes++;
        isRateLiked[msg.sender][_target][_rateId][_index] = true;
        if (isRateDisliked[msg.sender][_target][_rateId][_index]) {
            rating[_target][_rateId][_index].dislikes--;
            isRateDisliked[msg.sender][_target][_rateId][_index] = false;
        }
    }

    function dislikeRate(address _target, uint256 _rateId, uint256 _index) public onlyRole(Roles.Customer) sellerOrStoreTarget(_target) {
        require(!isRateDisliked[msg.sender][_target][_rateId][_index], "The rate already disliked");
        rating[_target][_rateId][_index].dislikes++;
        isRateDisliked[msg.sender][_target][_rateId][_index] = true;
        if (isRateLiked[msg.sender][_target][_rateId][_index]) {
            rating[_target][_rateId][_index].likes--;
            isRateLiked[msg.sender][_target][_rateId][_index] = false;
        }
    }

    function unlikeRate(address _target, uint256 _rateId, uint256 _index) public onlyRole(Roles.Customer) sellerOrStoreTarget(_target) {
        require(isRateLiked[msg.sender][_target][_rateId][_index], "The rate not liked");
        rating[_target][_rateId][_index].likes--;
        isRateLiked[msg.sender][_target][_rateId][_index] = false;
    }

    function undislikeRate(address _target, uint256 _rateId, uint256 _index) public onlyRole(Roles.Customer) sellerOrStoreTarget(_target) {
        require(isRateDisliked[msg.sender][_target][_rateId][_index], "The rate not disliked");
        rating[_target][_rateId][_index].dislikes--;
        isRateDisliked[msg.sender][_target][_rateId][_index] = false;
    }

    function _makeComment(address _target, uint256 _rateId, string memory _text) private sellerOrStoreTarget(_target) {
        Roles _currentRole = currentRole[msg.sender];
        if (_currentRole == Roles.Seller) {
            if (sellerToStore[msg.sender] != _target) {
                revert PermissionDenied();
            }
        } else if (_currentRole != Roles.Customer) {
            revert PermissionDenied();
        }

        string memory _login = addressToLogin[msg.sender];
        Rate memory _comment = Rate(msg.sender, _login, 0, _text, block.timestamp, 0, 0);
        rating[_target][_rateId].push(_comment);

        if (_currentRole == Roles.Seller) { // The seller's comment will be the first
            for (uint256 i = 1; i < rating[_target][_rateId].length - 1; i++) {
                rating[_target][_rateId][i + 1] = rating[_target][_rateId][i];
            }
            rating[_target][_rateId][1] = _comment;
        }
    }
}