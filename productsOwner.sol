// SPDX-License-Identifier: UNLICENSE

pragma solidity ^0.8.0;

import "./roleModel.sol";

contract productsOwner is roleModel {

    struct Product {
        string title;
        uint256 cost_wei;
        uint256 amount;
        uint256 production_date;
        uint32 storage_life_days;
    }

    mapping(address => mapping(Roles => mapping(uint256 => Product))) public products;
    mapping(address => mapping(Roles => string[])) public productsTitles;
    mapping(address => mapping(Roles => mapping(uint256 => uint256))) public productsCount;
    mapping(address => mapping(Roles => mapping(uint256 => uint256[]))) public productsCost;
    mapping(address => mapping(Roles => mapping(uint256 => uint256[]))) public productionTimes;
    mapping(address => mapping(Roles => mapping(uint256 => uint32[]))) public storageLifeDays;

    error ProductDoesNotExists(string title);

    modifier productExists(address _owner, Roles _role, string memory _title) {
        bool _exists = false;
        string[] memory _titles = productsTitles[_owner][_role];
        for (uint256 i = 0; i < _titles.length; i++) {
            if (_generateHash(_titles[i]) == _generateHash(_title)) {
                _exists = true;
                break;
            }
        }
        if (!_exists) {
            revert ProductDoesNotExists(_title);
        }
        _;
    }

    function addProduct(string calldata _title, uint256 _cost_wei, uint256 _amount, uint32 _storage_life) public onlyRole(Roles.Supplier) {
        require (_generateHash(_title) != _generateHash(""), "The product must have a title");
        require (_cost_wei > 0, "The product must have a price greater than 0");
        require (_amount > 0, "The product must have a amount greater than 0");
        require (_storage_life > 0, "The product must have a storage life greater than 0 days");
        
        uint256 _currentDay = block.timestamp - block.timestamp % 1 days;
        uint256 _hashProduct = _generateHash(_title, _currentDay, _storage_life, _cost_wei);

        if (_getProduct(msg.sender, Roles.Supplier, _hashProduct).cost_wei > 0) 
        {
            _getProduct(msg.sender, Roles.Supplier, _hashProduct).amount += _amount;
        } else {
            uint256 _hashTitle = _generateHash(_title);
            products[msg.sender][Roles.Supplier][_hashProduct] = Product(_title, _cost_wei, _amount, _currentDay, _storage_life);
            productsTitles[msg.sender][Roles.Supplier].push(_title);
            productsCost[msg.sender][Roles.Supplier][_hashTitle].push(_cost_wei);
            productionTimes[msg.sender][Roles.Supplier][_hashTitle].push(_currentDay);
            storageLifeDays[msg.sender][Roles.Supplier][_hashTitle].push(_storage_life);
            productsCount[msg.sender][Roles.Supplier][_hashTitle]++;
        }
    }

    function _getProduct(address _address, Roles _role, uint256 _productHash) internal view returns (Product memory) {
        return products[_address][_role][_productHash];
    }

    function _generateHash (string memory _text, uint256 _production_date, uint32 _storage_life, uint256 _cost) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(_text, _production_date, _storage_life, _cost)));
    }
}