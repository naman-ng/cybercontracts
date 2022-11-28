// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.14;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { ERC721 } from "../../dependencies/solmate/ERC721.sol";
import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { ISubscribeMiddleware } from "../../interfaces/ISubscribeMiddleware.sol";
import { ICyberEngine } from "../../interfaces/ICyberEngine.sol";

import { Constants } from "../../libraries/Constants.sol";

import { FeeMw } from "../base/FeeMw.sol";

/**
 * @title  Subscribe Middleware for different time periods
 * @author Naman Garg
 * @notice This contract is a middleware to only allow users to subscribe for a specific time period when they pay a certain fee to the profile owner.
 */
contract SubscribePaidMw is ISubscribeMiddleware, FeeMw {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                EVENT
    //////////////////////////////////////////////////////////////*/

    event SubscribePaidMwSet(
        address indexed namespace,
        uint256 indexed profileId,
        uint256 indexed amount,
        address recipient,
        address currency,
        bool nftRequired,
        address nftAddress,
        uint64 subscribeTime,
        uint64 period
    );

    /*//////////////////////////////////////////////////////////////
                               STATES
    //////////////////////////////////////////////////////////////*/

    struct PaidSubscribeData {
        uint256 amount;
        address recipient;
        address currency;
        bool nftRequired;
        address nftAddress;
        uint64 subscribeTime;
        uint64 period;
    }

    mapping(address => mapping(uint256 => PaidSubscribeData))
        internal _paidSubscribeData;

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address treasury) FeeMw(treasury) {}

    /*//////////////////////////////////////////////////////////////
                              EXTERNAL
    //////////////////////////////////////////////////////////////*/

    /**
     * @inheritdoc ISubscribeMiddleware
     * @notice Stores the parameters for setting up the paid subscribe middleware, checks if the amount, recipient, and
     * currency is valid and approved, and whether a special NFT is needed to subscribe
     */
    function setSubscribeMwData(uint256 profileId, bytes calldata data)
        external
        override
        returns (bytes memory)
    {
        (
            uint256 amount,
            address recipient,
            address currency,
            bool nftRequired,
            address nftAddress,
            uint64 period
        ) = abi.decode(data, (uint256, address, address, bool, address, uint64));

        require(amount != 0, "INVALID_AMOUNT");
        require(recipient != address(0), "INVALID_ADDRESS");
        require(_currencyAllowed(currency), "CURRENCY_NOT_ALLOWED");

        _paidSubscribeData[msg.sender][profileId].amount = amount;
        _paidSubscribeData[msg.sender][profileId].recipient = recipient;
        _paidSubscribeData[msg.sender][profileId].currency = currency;
        _paidSubscribeData[msg.sender][profileId].nftRequired = nftRequired;
        _paidSubscribeData[msg.sender][profileId].nftAddress = nftAddress;
        _paidSubscribeData[msg.sender][profileId].subscribeTime = block.timestamp;
        _paidSubscribeData[msg.sender][profileId].period = period;

        emit SubscribePaidMwSet(
            msg.sender,
            profileId,
            amount,
            recipient,
            currency,
            nftRequired,
            nftAddress,
            block.timestamp,
            period
        );
        return new bytes(0);
    }

    /**
     * @inheritdoc ISubscribeMiddleware
     * @notice Checks if the subscriber has the required NFT, then transfers the amount required from the subscriber to the treasury
     */
    function preProcess(
        uint256 profileId,
        address subscriber,
        address,
        bytes calldata
    ) external override {
        require(
            checkSubscriptionValidity(profileId),
            "INVALID"
        );
        address currency = _paidSubscribeData[msg.sender][profileId].currency;
        uint256 amount = _paidSubscribeData[msg.sender][profileId].amount;
        uint256 treasuryCollected = (amount * _treasuryFee()) /
            Constants._MAX_BPS;
        uint256 actualPaid = amount - treasuryCollected;

        if (_paidSubscribeData[msg.sender][profileId].nftRequired) {
            require(
                ERC721(_paidSubscribeData[msg.sender][profileId].nftAddress)
                    .balanceOf(subscriber) > 0,
                "NO_REQUIRED_NFT"
            );
        }

        IERC20(currency).safeTransferFrom(
            subscriber,
            _paidSubscribeData[msg.sender][profileId].recipient,
            actualPaid
        );

        if (treasuryCollected > 0) {
            IERC20(currency).safeTransferFrom(
                subscriber,
                _treasuryAddress(),
                treasuryCollected
            );
        }
    }

    /**
     * @notice Tells if the subscription has expired or not.
     *
     * @param profileId The profile ID.
     * @return boolean The subscription is valid or not.
     */
    function checkSubscriptionValidity(uint256 profileId)
        internal
        view
        returns (bool)
    {
        uint256 subscribeTime = _paidSubscribeData[msg.sender][profileId].subscribeTime;
        uint256 duration = block.timestamp - subscribeTime;

        return (_paidSubscribeData[msg.sender][profileId].period > duration);
    }

    /// @inheritdoc ISubscribeMiddleware
    function postProcess(
        uint256,
        address,
        address,
        bytes calldata
    ) external {
        // do nothing
    }
}
