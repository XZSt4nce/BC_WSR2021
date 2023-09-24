// SPDX-License-Identifier: UNLICENSE

import "@openzeppelin/contracts/utils/Strings.sol";

pragma solidity ^0.8.0;

contract roleModel {
    enum Roles {
        Bank,
        Store, 
        Supplier,
        Admin,
        Seller,
        Customer
    }

    enum Cities {
        Taganrok,
        Kaluga,
        Moscow,
        Ryazan,
        Samara,
        SPB,
        Dmitrov,
        Tomsk,
        Habarovsk,
        Penza
    }

    struct Banks {
        address payable addr;
        address[] borrowers;
    }

    struct Shops {
        address payable addr;
    }
    
    struct Users {
        address payable addr;
        string lastName;
        string name;
        string middleName;
    }

    struct Record {
        string text;
        uint256 time;
    }

    address[] public banks;
    address[] public suppliers;
    address[] public stores;
    address[] public users;

    address[] upgradeRequestsAddresses;
    address[] downgradeRequestsAddresses;

    address payable[] borrowRequests;

    Roles[] upgradeRequestsRoles;
    Roles[] downgradeRequestsRoles;

    uint256 storeId = 1;
    uint256 constant START_UP_CAPITAL = 1000 ether;

    mapping(address => bool) signedIn;
    mapping(address => Banks) public addressToBankAccount;
    mapping(address => Shops) public addressToShopAccount;
    mapping(address => Users) public addressToUserAccount;
    mapping(address => string) public addressToLogin;
    mapping(address => uint256) public addressToStoreNumber;
    mapping(address => Roles) currentRole;
    mapping(address => Roles[]) addressToRoles;
    mapping(address => Cities) public storeToCity;

    mapping(address => address) public sellerToStore;
    mapping(address => address[]) public storeToSellers;

    mapping(address => mapping(Roles => Record[])) history;

    mapping(address => address payable) borrowerToBank;
    mapping(address => uint256) borrowValue;

    mapping(address => mapping(Roles => bool)) public upgradeRequestSended;
    mapping(address => address) upgradeRequesterToStore;
    mapping(address => mapping(Roles => bool)) public downgradeRequestSended;

    error AccountNotFound();
    error PermissionDenied();
    error LoginIsEmpty();
    error LastNameIsEmpty();
    error NameIsEmpty();
    error MiddleNameIsEmpty();

    modifier registered {
        require (signedIn[msg.sender], "You aren't registered");
        _;
    }

    modifier notBank {
        require (currentRole[msg.sender] != Roles.Bank, "You are a bank");
        _;
    }

    modifier onlyRole(Roles _role) {
        if (currentRole[msg.sender] != _role) {
            revert PermissionDenied();
        }
        _;
    }

    modifier onlyUser() {
        if (msg.sender != addressToUserAccount[msg.sender].addr) {
            revert PermissionDenied();
        }
        _;
    }

    modifier storeExists(address _address) {
        bool _exists = false;
        for (uint256 i = 0; i < stores.length; i++) {
            address _shop = stores[i];
            if (_shop == _address) {
                if (currentRole[_shop] == Roles.Store) {
                    _exists = true;
                }
                break;
            }
        }
        require (_exists, "The store doesn't exists");
        _;
    }

    function borrowRequest() public onlyRole(Roles.Store) {
        borrowRequests.push(payable(msg.sender));
        borrowValue[msg.sender] = START_UP_CAPITAL;
    }

    function upgradeRequest(address _store) public onlyUser() {
        Roles _role = Roles.Seller;
        string memory _message = string.concat("You have sent a request for promotion to a seller in store #", Strings.toString(addressToStoreNumber[_store]));
        if (_store == address(0)) {
            _role = Roles.Admin;
            _message = "You have sent a request for promotion to an admin";
        } else {
            upgradeRequesterToStore[msg.sender] = _store;
        }
        require(!upgradeRequestSended[msg.sender][_role], "The upgrade request has already been sent");
        upgradeRequestsAddresses.push(msg.sender);
        upgradeRequestSended[msg.sender][_role] = true;
        _addAction(_message);
    }

    function downgradeRequest(Roles _role) public onlyUser() {
        if (_role == Roles.Admin || _role == Roles.Seller) {
            require(!downgradeRequestSended[msg.sender][_role], "The downgrade request has already been sent");
        } else {
            revert PermissionDenied();
        }
        downgradeRequestSended[msg.sender][_role] = true;
        downgradeRequestsAddresses.push(msg.sender);
        _addAction("You have sent a downgrade request");
    }

    function upgrade(uint256 _id, bool _confirm) public onlyRole(Roles.Admin) {
        address _target = upgradeRequestsAddresses[_id];
        if (_confirm) {
            address _store = upgradeRequesterToStore[_target];
            _upgrade(_target, _store);
        } else {
            _addAction("You have rejected a user promotion request");
        }
        _removeUpgradeRequest(_id, Roles.Seller);
    }

    function downgrade(uint256 _id, bool _confirm) public onlyRole(Roles.Admin) {
        
        address _target = downgradeRequestsAddresses[_id];
        if (_confirm) {
            _downgrade(_target);
            _addAction("You demoted the user");
        } else {
            _addAction("You have rejected a user demotion request");
        }
        _removeDowngradeRequest(_id, Roles.Seller);
    }

    function createStore(address _address, Cities _city) public onlyRole(Roles.Admin) {
        require(!signedIn[_address], "The store cannot be created if it is already registered in the system");
        addressToShopAccount[_address] = Shops(payable(_address));
        stores.push(_address);
        addressToStoreNumber[_address] = storeId++;
        currentRole[_address] = Roles.Store;
        addressToRoles[_address].push(Roles.Store);
        storeToCity[_address] = _city;
        signedIn[_address] = true;
        _addAction(string.concat("You have created store #", Strings.toString(addressToStoreNumber[_address])));
    }

    function deleteStore(address _address) public onlyRole(Roles.Admin) {
        address[] memory _sellers = storeToSellers[_address];
        for (uint256 i = 0; i < _sellers.length; i++) {
            _downgrade(_sellers[i]);
        }
        delete addressToShopAccount[_address];
        delete addressToStoreNumber[_address];
        delete currentRole[_address];
        delete addressToRoles[_address];
        delete storeToCity[_address];
        delete signedIn[_address];
        uint256 _shopsLength = stores.length;
        for (uint256 i = 0; i < _shopsLength; i++) {
            if (stores[i] == _address) {
                for (uint256 j = i; j < _shopsLength - 1; j++) {
                    stores[j] = stores[j + 1];
                }
                stores.pop();
                break;
            }
        }
        _addAction(string.concat("You have deleted store #", Strings.toString(addressToStoreNumber[_address])));
    }

    function showHistory() public view returns (Record[] memory) {
        return history[msg.sender][currentRole[msg.sender]];
    }

    function storeProfile() public view onlyRole(Roles.Store) returns (uint256 balance, uint256 storeNumber, Cities city, Users[] memory sellers) {
        address[] memory _sellersAddress = storeToSellers[msg.sender];
        uint256 _sellersCount = _sellersAddress.length;
        Users[] memory _sellers = new Users[](_sellersCount);
        for (uint256 i = 0; i < _sellersCount; i++) {
            _sellers[i] = addressToUserAccount[_sellersAddress[i]];
        }
        return (msg.sender.balance, addressToStoreNumber[msg.sender], storeToCity[msg.sender], _sellers);
    }

    function changeRole(Roles _role) public registered {
        if (!_addressHaveRole(msg.sender, _role)) {
            revert PermissionDenied();
        }
        currentRole[msg.sender] = _role;
    }

    function _addressHaveRole(address _address, Roles _role) internal view returns(bool) {
        bool _haveRole = false;
        Roles[] memory _roles = addressToRoles[_address];
        for (uint256 i = 0; i < _roles.length; i++) {
            if (_roles[i] == _role) {
                _haveRole = true;
                break;
            }
        }
        return _haveRole;
    }

    function _removeArrayElement(address[] storage _array, uint256 _index) internal {
        for (; _index < _array.length - 1; _index++) {
            _array[_index] = _array[_index + 1];
        }
        _array.pop();
    }

    function _removeArrayElement(address payable[] storage _array, uint256 _index) internal {
        for (; _index < _array.length - 1; _index++) {
            _array[_index] = _array[_index + 1];
        }
        _array.pop();
    }

    function _removeArrayElement(string[] storage _array, uint256 _index) internal {
        for (; _index < _array.length - 1; _index++) {
            _array[_index] = _array[_index + 1];
        }
        _array.pop();
    }

    function _addAction(string memory _text) internal {
        history[msg.sender][currentRole[msg.sender]].push(Record(_text, block.timestamp));
    }

    function _generateHash (string memory _text) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(_text)));
    }

    function _upgrade(address _address, address _store) private {
        if (_store == address(0)) {
            addressToRoles[_address].push(Roles.Admin);
            _addAction("You have promoted the user to the status of an admin");
        } else {
            addressToRoles[_address].push(Roles.Seller);
            sellerToStore[_address] = _store;
            storeToSellers[_store].push(_address);
            _addAction(string.concat("You have promoted the user to the status of a seller in the store #", Strings.toString(addressToStoreNumber[_store])));
        }
    }

    function _downgrade(address _address) private {
        address _store = sellerToStore[_address];
        address[] memory _sellers = storeToSellers[_store];
        uint256 _sellersLastIndex = _sellers.length - 1;
        delete sellerToStore[_address];
        for (uint256 i = 0; i < _sellersLastIndex; i++) {
            if (_sellers[i] == _address) {
                for (uint256 j = i; j < _sellersLastIndex; j++) {
                    storeToSellers[_store][j] = _sellers[j + 1];
                }
                storeToSellers[_store].pop();
                break;
            }
        }
        if (currentRole[_address] == Roles.Seller) {
            currentRole[_address] = Roles.Customer;
        }

        Roles[] memory _roles = addressToRoles[_address];
        uint256 _rolesLastIndex = _roles.length - 1;
        for (uint256 i = 0; i < _rolesLastIndex; i++) {
            if (_roles[i] == Roles.Seller) {
                addressToRoles[_address][i] = _roles[i + 1];
            }
        }
        addressToRoles[_address].pop();
    }

    function _removeUpgradeRequest(uint256 _id, Roles _role) private {
        address _target = upgradeRequestsAddresses[_id];
        for (; _id < upgradeRequestsAddresses.length - 1; _id++) {
            upgradeRequestsAddresses[_id] = upgradeRequestsAddresses[_id + 1];
        }
        upgradeRequestsAddresses.pop();
        delete upgradeRequestSended[_target][_role];
        delete upgradeRequesterToStore[_target];
    }

    function _removeDowngradeRequest(uint256 _id, Roles _role) private {
        address _target = downgradeRequestsAddresses[_id];
        for (; _id < downgradeRequestsAddresses.length - 1; _id++) {
            downgradeRequestsAddresses[_id] = downgradeRequestsAddresses[_id + 1];
        }
        downgradeRequestsAddresses.pop();
        delete downgradeRequestSended[_target][_role];
    }
}