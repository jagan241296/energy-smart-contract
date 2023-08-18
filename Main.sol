// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "contracts/P2P.sol";

/**
 * @title Main
 * @dev Provides an interface to iplement energy trading between registered prosumers
 */
contract Main {
    /*#################################### CLASS VARIABLES ##########################################*/

    uint256 private constant PRICE_PER_UNIT = 1 ether;

    // Instance of the P2P contract that handles the core trading logic
    P2P private peerContract;

    // Address to boolean map to keep track of all the registered users in the system
    mapping(address => bool) private registrationMap;

    constructor() {
        peerContract = new P2P();
    }

    /*#################################### MODIFIERS ##########################################*/
    /*
        Modifier function to check if the sender is a registered prosumer with the system
     */
    modifier onlyRegisteredUser() {
        require(
            registrationMap[msg.sender],
            "User needs to be registered to perform any operation"
        );
        _;
    }

    /*
        Modifier function to check for only one registration of the given user address across the system
     */
    modifier onlySingleUserRegistration() {
        require(!registrationMap[msg.sender], "User is already registered");
        _;
    }

    /*
        @dev Modifier function to check the user has sufficient balance in the wallet to buy energy
        @param purchaseUnits to calculate the cost of energy
     */
    modifier hasSufficientBalance(uint256 purchaseUnits) {
        require(
            peerContract.getProsumerWalletBalance(msg.sender) >=
                (purchaseUnits * PRICE_PER_UNIT),
            "User does not have enough balance to buy energy"
        );
        _;
    }

    /*
        Modifier function to check if the user is currently a buye i.e., user has deficit of energy at the moment.
        This modifier is needed to block the withdrawl of funds from the wallet if there is energy deficit for user.
     */
    modifier notABuyer() {
        require(
            peerContract.getProsumerEnergyStatus(msg.sender) >= 0,
            "User cannot withdraw balance when in energy deficit"
        );
        _;
    }

    /*#################################### PUBLIC FUNCTIONS ##########################################*/
    /*
        @dev Register a new user as a prosumer in the trading system
     */
    function register() public onlySingleUserRegistration {
        try peerContract.registerNewProsumer(msg.sender) {
            registrationMap[msg.sender] = true;
        } catch {
            revert("User Registration not successful");
        }
    }

    /*
        @dev Add the funds sent in the msg block by a user to their respective smart wallets created in the system.
     */
    function depositAmount() public payable onlyRegisteredUser {
        require(msg.value >= 0, "Deposit Ether cannot be negative");

        peerContract.deposit{value: msg.value}(msg.sender);
    }

    /*
        @dev Fetch current Energy status for a user
        @return currentEnergyStatus - Energy status of user. Positive if in surplus or negative if in deficit
     */
    function getEnergyStatus()
        public
        view
        onlyRegisteredUser
        returns (int256 currentEnergyStatus)
    {
        return peerContract.getProsumerEnergyStatus(msg.sender);
    }

    /*
        @dev Get current wallet balance for the user.
        @return balance: Current Wallet Balance in Wei for the user from the user's smart wallet.
     */
    function getWalletBalance()
        public
        view
        onlyRegisteredUser
        returns (uint256 balance)
    {
        return peerContract.getProsumerWalletBalance(msg.sender);
    }

    /*
        @dev Withdraw existing wallet balance to the sender address.
        Withdrawl of funds can only happen if the user is not energy deficit.
     */
    function withdrawAmount() public payable onlyRegisteredUser notABuyer {
        peerContract.withdrawBalance(msg.sender);
    }

    /*
        @dev Send energy buy/sell request to the system.
        @param requestUnits: nuber of energy units requested to buy/sell
     */
    function request(int256 requestUnits) public onlyRegisteredUser {
        if (requestUnits > 0) {
            // sell request
            sell(requestUnits);
        } else if (requestUnits < 0) {
            // buy request
            buy(requestUnits);
        }
    }

    /*#################################### PRIVATE FUNCTIONS ##########################################*/
    /*
        @dev Execute the sell operation by calling the P2P contract with user provided details
        @param requestUnits: nuber of energy units requested sell
     */
    function sell(int256 requestUnits) private {
        peerContract.sellEnergy(msg.sender, requestUnits);
    }

    /*
        @dev Execute the buy operation by calling the P2P contract with user provided details
        @param requestUnits: nuber of energy units requested buy
     */
    function buy(int256 requestUnits)
        private
        hasSufficientBalance(uint256(abs(requestUnits)))
    {
        peerContract.buyEnergy(msg.sender, requestUnits);
    }

    /*
        @dev Convert the negative energy units to its absolute value
        @param val: any signed integer number
        @return absolute value of the given number
     */
    function abs(int256 val) private pure returns (int256) {
        return val < 0 ? -val : val;
    }
}
