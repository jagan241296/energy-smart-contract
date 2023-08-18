// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/**
 * @title P2P
 * @dev Implements core energy trading functions between prosumers
 */
contract P2P {
    struct Prosumer {
        address id; // address of the user
        int256 energyStatus; // energy status of the user, positive when in surplus or negative when in deficit
        uint256 walletBalance; // available funds in the smart wallet of the user
    }

    /*#################################### CLASS VARIABLES ##########################################*/

    uint256 private constant PRICE_PER_UNIT = 1 ether;

    // Address to struct map to keep track of all the registered users with their details
    mapping(address => Prosumer) private prosumerMap;

    // Array based Queue to track all the buyers
    Prosumer[] private buyerQueue;

    // Array based queue to track all the sellers
    Prosumer[] private sellerQueue;

    // Address of the owner/deployed contract.
    address private owner;

    constructor() {
        // set the caller contract as the owner for this contract
        owner = msg.sender;
    }

    /*#################################### MODIFIERS ##########################################*/
    /*
        Modifier function to validate if the caller of the functions is only the owner of the contract
     */
    modifier onlyAuthorizedCalls() {
        require(
            owner == msg.sender,
            "Only owner is authorized to call functions"
        );
        _;
    }

    /*#################################### PUBLIC FUNCTIONS ##########################################*/

    /*
        @dev Register new user as prosumer and store details in an instance of sturct
        @param prosumerId: Address of the user
     */
    function registerNewProsumer(address prosumerId)
        public
        onlyAuthorizedCalls
    {
        Prosumer memory prosumer = Prosumer(prosumerId, 0, 0);
        prosumerMap[prosumerId] = prosumer;
    }

    /*
        @dev get user wallet balance from the user details struct
        @param prosumerId: Address of the user
        @return wallet balance of the user
     */
    function getProsumerWalletBalance(address prosumerId)
        public
        view
        onlyAuthorizedCalls
        returns (uint256)
    {
        return prosumerMap[prosumerId].walletBalance;
    }

    /*
        @dev get current energy status of user
        @param prosumerId: Address of the user
        @return current energy status of the user. Can be either positive or negative
     */
    function getProsumerEnergyStatus(address prosumerId)
        public
        view
        onlyAuthorizedCalls
        returns (int256)
    {
        return prosumerMap[prosumerId].energyStatus;
    }

    /*
        @dev deposit the input funds from the msg block against the input user address
        @param prosumerId: Address of the user
     */
    function deposit(address prosumerId) external payable onlyAuthorizedCalls {
        prosumerMap[prosumerId].walletBalance += msg.value;
    }

    /*
        @dev transfer the remaining wallet balance of the user to the address of the user
            Transfer happens only when the user is not a buyer i.e., does not have energy deficit
        @param prosumerId: Address of the user
     */
    function withdrawBalance(address prosumerId)
        public
        payable
        onlyAuthorizedCalls
    {
        if (notBuyer(prosumerId)) {
            payable(address(prosumerId)).transfer(
                prosumerMap[prosumerId].walletBalance
            );
            prosumerMap[prosumerId].walletBalance = 0;
        } else {
            revert("Cannot withdraw balance when user is energy deficit");
        }
    }

    /*
        @dev process the sell request for the user.
        Seller can either fullfill the existing requests from buyers in buyer queue or wait in the seller queue
        @param prosumerId: Address of the user
        @param units: number of requested units ready to sell in the market
     */
    function sellEnergy(address prosumerId, int256 units)
        public
        onlyAuthorizedCalls
    {
        // get associated seller from registered users
        Prosumer storage seller = prosumerMap[prosumerId];
        seller.energyStatus += units;

        // check for any buyer for Energy from the buyer queue
        for (uint256 i = 0; i < buyerQueue.length; i++) {
            if (
                canCompleteOrder(
                    seller.energyStatus,
                    buyerQueue[i].energyStatus
                )
            ) {
                processOrder(
                    seller.id,
                    buyerQueue[i].id,
                    abs(buyerQueue[i].energyStatus)
                );
                continue;
            }
        }

        // if no buyer is available, add seller to seller queue
        addElement(seller, sellerQueue);
    }

    /*
        @dev process the buy request for the user.
        Buyer can either buy from the existing sellers seller queue or wait in the buyer queue
        @param prosumerId: Address of the user
        @param units: number of requested units ready to buy from the market
     */
    function buyEnergy(address prosumerId, int256 units)
        public
        onlyAuthorizedCalls
    {
        // get associated buyer from registered users
        Prosumer storage buyer = prosumerMap[prosumerId];
        buyer.energyStatus += units;

        // check for any seller for energy from the seller queue
        for (uint256 i = 0; i < sellerQueue.length; i++) {
            if (
                canCompleteOrder(
                    sellerQueue[i].energyStatus,
                    buyer.energyStatus
                )
            ) {
                processOrder(
                    sellerQueue[i].id,
                    buyer.id,
                    abs(buyer.energyStatus)
                );
                return;
            }
        }

        // if no seller in available, add buyer to deficit queue
        addElement(buyer, buyerQueue);
    }

    /*#################################### PRIVATE FUNCTIONS ##########################################*/
    /*
        @dev Check if the user is having an energy deficit at the moment
        @param prosumerId: Address of the user
        @return true/false
     */
    function notBuyer(address prosumerId)
        private
        view
        onlyAuthorizedCalls
        returns (bool)
    {
        return prosumerMap[prosumerId].energyStatus >= 0;
    }

    /*
        @dev process transaction by deducting units from seller energy status 
            and adding to buyer energy and deducting the cost from buyer wallet 
            and adding it to seller wallet
        @param sellerId: Address of the seller
        @param buyerId: Address of the buyer
        @param units: number of requested units to process
     */
    function processOrder(
        address sellerId,
        address buyerId,
        int256 units
    ) private {
        Prosumer storage seller = prosumerMap[sellerId];
        Prosumer storage buyer = prosumerMap[buyerId];

        // deduct units from seller
        seller.energyStatus -= units;

        // add units to buyer
        buyer.energyStatus += units;

        // deduct money from buyer
        uint256 cost = uint256(units) * PRICE_PER_UNIT;
        buyer.walletBalance -= cost;

        // add money to Seller wallet
        seller.walletBalance += cost;

        // INCENTIVE: Get 1 ether for each multiple of 5 in a transaction for buyer and seller.
        uint256 unitsInMultipleOfFive = uint256(units / 5);

        // Add ether to both parties wallets
        seller.walletBalance += unitsInMultipleOfFive * 1 ether;
        buyer.walletBalance += unitsInMultipleOfFive * 1 ether;

        // add updated status back to both queues
        addElement(seller, sellerQueue);
        addElement(buyer, buyerQueue);
    }

    /*
        @dev check if the seller can fulfill the buyers requested units of energy
        @param existingUnits: number of energy units available with seller
        @param requestedUnits: number of energy units requested by buyer
        @return true/false
     */
    function canCompleteOrder(int256 existingUnits, int256 requestedUnits)
        private
        pure
        returns (bool)
    {
        return
            existingUnits != 0 &&
            requestedUnits != 0 &&
            abs(existingUnits) >= abs(requestedUnits);
    }

    /*
        @dev Convert the negative energy units to its absolute value
        @param val: any signed integer number
        @return absolute value of the given number
     */
    function abs(int256 val) private pure returns (int256) {
        return val < 0 ? -val : val;
    }

    /*
        @dev add input item to the queue too update the buyer/seller queue
        @param item: user struct to update in queue
        @param queue: buyer/seller queue to add the item
     */
    function addElement(Prosumer memory item, Prosumer[] storage queue)
        private
    {
        bool alreadyExists = false;
        for (uint256 i = 0; i < queue.length; i++) {
            if (queue[i].id == item.id) {
                alreadyExists = true;

                // update the current energy status of the user. This is for seller having more units than buyer demand
                queue[i].energyStatus = item.energyStatus;
                break;
            }
        }
        if (!alreadyExists && item.energyStatus != 0) {
            queue.push(item);
        }
    }
}
