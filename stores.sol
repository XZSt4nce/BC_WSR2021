//SPDX-License-Identifier: UNLICENSE

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./rates.sol";

contract stores is rates, ERC20("WinPlace", "WPC") {
    
    uint256 constant EXTRA = 2;

    error InsufficientFunds(uint256 available, uint256 required);

    constructor (address[] memory _addresses) {
        for (uint i = 0; i < _addresses.length; i++) {
            require(_addresses[i] != msg.sender, "The deployer must not have an account");
        }
        _createBank(_addresses[0]);
        _createUser(_addresses[1], "ivan", unicode"Иванов", unicode"Иван", unicode"Иванович", Roles.Admin);
        _createUser(_addresses[2], "semen", unicode"Семенов", unicode"Семен", unicode"Семенович", Roles.Seller);
        sellerToStore[_addresses[2]] = _addresses[4];
        storeToSellers[_addresses[4]].push(_addresses[2]);
        _createUser(_addresses[3], "petr", unicode"Петров", unicode"Петр", unicode"Петрович", Roles.Customer);
        _createStore(_addresses[4], Cities.Dmitrov);
        _createStore(_addresses[5], Cities.Kaluga);
        _createStore(_addresses[6], Cities.Moscow);
        _createStore(_addresses[7], Cities.Ryazan);
        _createStore(_addresses[8], Cities.Samara);
        _createStore(_addresses[9], Cities.SPB);
        _createStore(_addresses[10], Cities.Taganrok);
        _createStore(_addresses[11], Cities.Tomsk);
        _createStore(_addresses[12], Cities.Habarovsk);
        _createSupplier(_addresses[13], "goldfish");
    }

    function borrow(uint256 _borrowerId) public payable onlyRole(Roles.Bank) {
        address payable _borrower = borrowRequests[_borrowerId];
        if (msg.value < borrowValue[_borrower]) {
            revert InsufficientFunds({
                available: msg.value,
                required: borrowValue[_borrower]
            });
        }
        _borrower.transfer(START_UP_CAPITAL);
        payable(msg.sender).transfer(address(this).balance);
        _removeArrayElement(borrowRequests, _borrowerId);
        addressToBankAccount[msg.sender].borrowers.push(_borrower);
    }

    function payBorrow() public payable onlyRole(Roles.Store) {
        address payable _bank = borrowerToBank[msg.sender];
        if (msg.value < borrowValue[msg.sender]) {
            borrowValue[msg.sender] -= msg.value;
            _bank.transfer(msg.value);
        } else {
            _bank.transfer(borrowValue[msg.sender]);
            borrowValue[msg.sender] = 0;
            payable(msg.sender).transfer(address(this).balance);
            address[] memory _borrowers = addressToBankAccount[_bank].borrowers;
            for (uint256 i = 0; i < _borrowers.length; i++) {
                if (_borrowers[i] == msg.sender) {
                    _removeArrayElement(addressToBankAccount[_bank].borrowers, i);
                    break;
                }
            }
        }
    }

    function buyProducts(address payable _store, string calldata _title, uint256 _productHash, uint256 _amount) external payable registered notBank {
        Roles _currentRole = currentRole[msg.sender];

        Product memory _product;
        Roles _role;
        if (_currentRole == Roles.Customer) {
            _product = _getProduct(_store, Roles.Store, _productHash);
            _role = Roles.Store;
        } else if (_currentRole == Roles.Store) {
            _product = _getProduct(_store, Roles.Supplier, _productHash);
            _role = Roles.Supplier;
        } else {
            revert PermissionDenied();
        }
        if (_product.cost_wei <= 0) {
            revert ProductDoesNotExists(_title);
        }
        require (_amount > 0, "You must buy at least 1 product");
        require (_product.amount >= _amount, "There is no such quantity of products in stock");
        uint256 _totalCost = _product.cost_wei * _amount;
        if (msg.value < _totalCost) {
            revert InsufficientFunds({
                available: msg.value,
                required: _totalCost
            });
        }

        // Transfer
        _store.transfer(_totalCost);
        payable(msg.sender).transfer(address(this).balance);
        _decProduct(
            _product.title, 
            _store,
            _role,
            _amount, 
            _product.production_date, 
            _product.storage_life_days,
            _product.cost_wei
        );

        if (currentRole[msg.sender] == Roles.Store) {
            _incProduct(
                _product.title, 
                _product.cost_wei * EXTRA, // Extra charge
                _amount, 
                _product.production_date, 
                _product.storage_life_days
            ); 
        } else {
            _incProduct(
                _product.title, 
                _product.cost_wei, 
                _product.amount, 
                _product.production_date, 
                _product.storage_life_days
            );
        }
        _addAction(string.concat("You bought ", _title, " ", Strings.toString(_amount), " pcs. in the amount of ", Strings.toString(_totalCost), "wei"));
    }

    function signIn(string calldata _login, string calldata _lastName, string calldata _name, string calldata _middleName) public {
        require (!signedIn[msg.sender], "You are already registered");
        uint256 _emptyStringHash = _generateHash("");
        if (_generateHash(_login) == _emptyStringHash) {
            revert LoginIsEmpty();
        } else if (_generateHash(_lastName) == _emptyStringHash) {
            revert LastNameIsEmpty();
        } else if (_generateHash(_name) == _emptyStringHash) {
            revert NameIsEmpty();
        } else if (_generateHash(_middleName) == _emptyStringHash) {
            revert MiddleNameIsEmpty();
        }
        _createUser(msg.sender, _login, _lastName, _name, _middleName, Roles.Customer);
    }

    function _getProductsHashesByTitle(address _owner, Roles _role, string memory _productTitle) private view productExists(_owner, _role, _productTitle) returns (uint256[] memory) {
        uint256 _hashTitle = _generateHash(_productTitle);
        uint256 _count = productsCount[_owner][_role][_hashTitle];
        uint256[] memory _costs = productsCost[_owner][_role][_hashTitle];
        uint256[] memory _productionTimes = productionTimes[_owner][_role][_hashTitle];
        uint32[] memory _storageLifeDays = storageLifeDays[_owner][_role][_hashTitle];
        uint256[] memory _products = new uint256[](_count);
        for (uint256 i = 0; i < _count; i++) {
            _products[i] = _generateHash(_productTitle, _productionTimes[i], _storageLifeDays[i], _costs[i]);
        }
        return _products;
    }

    function _randomNumber(uint32 _storage_life) private view returns (uint32) {
        return uint32(( uint256( keccak256(abi.encodePacked(block.timestamp))) % ((_storage_life * 2) * 1 days)) / 1 days);
    }

    function _incProduct(string memory _title, uint256 _cost_wei, uint256 _amount, uint256 _production_date, uint32 _storage_life) private {
        uint256 _hashProduct = _generateHash(_title, _production_date, _storage_life, _cost_wei);
        Roles _currentRole = currentRole[msg.sender];
        if (products[msg.sender][_currentRole][_hashProduct].cost_wei > 0) {
            products[msg.sender][_currentRole][_hashProduct].amount += _amount;
        } else {
            uint256 _hashTitle = _generateHash(_title);
            products[msg.sender][_currentRole][_hashProduct] = Product(_title, _cost_wei, _amount, _production_date, _storage_life);
            productsTitles[msg.sender][_currentRole].push(_title);
            productsCost[msg.sender][_currentRole][_hashTitle].push(_cost_wei);
            productionTimes[msg.sender][_currentRole][_hashTitle].push(_production_date);
            storageLifeDays[msg.sender][_currentRole][_hashTitle].push(_storage_life);
            productsCount[msg.sender][_currentRole][_hashTitle]++;
        }
    }

    function _decProduct(string memory _title, address _owner, Roles _role, uint256 _amount, uint256 _production_date, uint32 _storage_life, uint256 _cost_wei) private {
        uint256 _hashProduct = _generateHash(_title, _production_date, _storage_life, _cost_wei);
        Roles _currentRole = currentRole[_owner];
        products[_owner][_currentRole][_hashProduct].amount -= _amount;
        if (products[_owner][_currentRole][_hashProduct].amount == 0) {
            uint256 _hashTitle = _generateHash(_title);
            delete products[_owner][_currentRole][_hashProduct];
            _removeProductTitle(_owner, _role, _title);
            productsCost[_owner][_currentRole][_hashTitle].pop();
            productionTimes[_owner][_currentRole][_hashTitle].pop();
            storageLifeDays[_owner][_currentRole][_hashTitle].pop();
            productsCount[_owner][_currentRole][_hashTitle]--;
        }
    }

    

    function _removeProductTitle(address _owner, Roles _role, string memory _title) private {
        uint256 i = 0;
        string[] memory _titles = productsTitles[_owner][_role];
        bytes32 _titleHash = keccak256(abi.encodePacked(_title));
        for (; i < _titles.length; i++) {
            if (keccak256(abi.encodePacked(_titles[i])) == _titleHash) {
                _removeArrayElement(productsTitles[_owner][_role], i);
                break;
            }
        }
    }

    function _createBank(address _address) private {
        address[] memory _borrowers;
        addressToBankAccount[_address] = Banks(payable(_address), _borrowers);
        banks.push(_address);
        currentRole[_address] = Roles.Bank;
        addressToRoles[_address].push(Roles.Bank);
        signedIn[_address] = true;
    }

    function _createStore(address _address, Cities _city) private {
        addressToShopAccount[_address] = Shops(payable(_address));
        stores.push(_address);
        addressToStoreNumber[_address] = storeId++;
        currentRole[_address] = Roles.Store;
        addressToRoles[_address].push(Roles.Store);
        storeToCity[_address] = _city;
        signedIn[_address] = true;
    }

    function _createSupplier(address _address, string memory _login) private {
        addressToShopAccount[_address] = Shops(payable(_address));
        suppliers.push(_address);
        addressToLogin[_address] = _login;
        currentRole[_address] = Roles.Supplier;
        addressToRoles[_address].push(Roles.Supplier);
        signedIn[_address] = true;
    }

    function _createUser(address _address, string memory _login, string memory lastName, string memory name, string memory middleName, Roles _role) private {
        addressToUserAccount[_address] = Users(payable(_address), lastName, name, middleName);
        users.push(_address);
        addressToLogin[_address] = _login;
        currentRole[_address] = _role;
        if (_role != Roles.Customer) {
            addressToRoles[_address].push(Roles.Customer);
        }
        addressToRoles[_address].push(_role);
        signedIn[_address] = true;
    }
}