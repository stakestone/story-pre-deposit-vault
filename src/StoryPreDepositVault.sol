// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";

import {Token} from "./Token.sol";

import "./Errors.sol";

/// @title StoryPreDepositVault - Fundraising contract for Story Protocol
/// @notice Handles asset deposit, asset custody, early receipts issuing(ERC20). Only USDC and USDC on Ethereum will be supported.
contract StoryPreDepositVault is AccessControl {
    /*//////////////////////////////////////////////////////////////////////////
                                    STATE VARIABLES
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice A role designated for managing Vault parameters, such as adjusting the cap, pausing operations, and other related tasks.
    /// @dev Hash digests for `VAULT_OPERATOR_ROLE`
    bytes32 public constant VAULT_OPERATOR_ROLE =
        keccak256("VAULT_OPERATOR_ROLE");

    /// @notice A role responsible for withdrawing the assets raised within the contract.
    /// @dev Hash digests for `ASSETS_MANAGEMENT_ROLE`
    bytes32 public constant ASSETS_MANAGEMENT_ROLE =
        keccak256("ASSETS_MANAGEMENT_ROLE");

    /// @dev Represent 1000000000000000000
    uint256 public constant D18 = 1e18;

    /// @dev Represent 1000000
    uint256 public constant D6 = 1e6;

    /// @notice The minimum amount a user can deposit.
    /// @dev USDT and USDC have a decimal of 6, so D6 represents 1 USD.
    uint256 public minDeposit = D6;

    /// @notice The maximum amount a user can deposit.
    /// @dev USDT and USDC have a decimal of 6, so D6 represents 1 USD.
    uint256 public maxDeposit = 50_000 * D6;

    /// @notice The maximum total amount that all users can deposit into the vault(in USD).
    /// @dev USDT and USDC have a decimal of 6, so D6 represents 1 USD.
    uint256 public cap = 5_000_000 * D6;

    /// @notice The total amount of assets deposited by all users(in USD).
    /// @dev USDT and USDC have a decimal of 6, so D6 represents 1 USD.
    uint256 public totalDeposit;

    /// @notice The Receipt token a user receives after depositing assets.
    Token public immutable earlyReceipt;

    /// @notice The list of supported depositable assets in the Vault.
    /// @dev Only USDC and USDC on Ethereum can be supported.
    address[] public supportedTokens;

    /// @notice Mapping of deposited amount per user
    mapping(address => uint256) public depositedAmount;

    /// @notice If a token is supported.
    mapping(address => bool) public isSupportedToken;

    /// @notice If deposit for a token is paused.
    mapping(address => bool) public depositPaused;

    /*//////////////////////////////////////////////////////////////////////////
                                    EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    event Deposit(
        address indexed caller,
        address indexed owner,
        address indexed asset,
        uint256 amount,
        uint256 shares
    );
    event SetCap(uint256 oldVal, uint256 newVal);
    event SetMinDeposit(uint256 oldVal, uint256 newVal);
    event SetMaxDeposit(uint256 oldVal, uint256 newVal);
    event SetDepositPause(address indexed asset, bool flag);
    event TokensWithdrawn(address indexed caller, uint256 amount);

    /*//////////////////////////////////////////////////////////////////////////
                                    CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    constructor(
        address _earlyReceipt,
        address _admin,
        address[] memory _supportedTokens
    ) {
        if (_earlyReceipt == address(0) || _admin == address(0))
            revert InvalidAddress();

        uint256 length = _supportedTokens.length;
        if (length == 0) revert InvalidArrayLength();

        uint256 i;
        for (i; i < length; i++) {
            address token = _supportedTokens[i];
            if (token == address(0)) revert InvalidAddress();

            isSupportedToken[token] = true;
            supportedTokens.push(token);
        }

        earlyReceipt = Token(_earlyReceipt);
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    PERMISSIONLESS FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice User mint receipt tokens by depositing USDC/USDT.
    /// @dev Anyone can mint receipt tokens for any receivers.
    /// @param _token The address of the asset(USDC or USDT)
    /// @param _amount The amount of the token that user will deposit
    /// @param _receiver The address of the user that will receive the receipt tokens
    function deposit(
        address _token,
        uint256 _amount,
        address _receiver
    ) external {
        uint256 afterDeposit = _amount + depositedAmount[msg.sender];
        uint256 afterDepositTotal = totalDeposit + _amount;

        if (!isSupportedToken[_token]) revert UnsupportedToken();
        if (depositPaused[_token]) revert Paused();
        if (afterDeposit < minDeposit || afterDeposit > maxDeposit)
            revert InvalidAmount();
        if (afterDepositTotal > cap) revert ExceedCap();
        if (_receiver == address(0)) revert InvalidAddress();

        TransferHelper.safeTransferFrom(
            _token,
            msg.sender,
            address(this),
            _amount
        );

        depositedAmount[msg.sender] = afterDeposit;
        totalDeposit = afterDepositTotal;

        uint256 shares = _amount * (10 ** 12);
        earlyReceipt.mint(_receiver, shares);

        emit Deposit(msg.sender, _receiver, _token, _amount, shares);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Called by admin to set the cap of the vault.
    /// @param _cap The amount of the new cap
    function setCap(uint256 _cap) external onlyRole(VAULT_OPERATOR_ROLE) {
        emit SetCap(cap, _cap);
        cap = _cap;
    }

    /// @notice Called by admin to set the minimum deposit amount for a user of the vault.
    /// @param _minDeposit The amount of the new minimum deposit amount
    function setMinDeposit(
        uint256 _minDeposit
    ) external onlyRole(VAULT_OPERATOR_ROLE) {
        emit SetMinDeposit(minDeposit, _minDeposit);
        minDeposit = _minDeposit;
    }

    /// @notice Called by admin to set the maximum deposit amount for a user of the vault.
    /// @param _maxDeposit The amount of the new maximum deposit amount
    function setMaxDeposit(
        uint256 _maxDeposit
    ) external onlyRole(VAULT_OPERATOR_ROLE) {
        emit SetMinDeposit(maxDeposit, _maxDeposit);
        maxDeposit = _maxDeposit;
    }

    /// @notice Called by admin to pause the deposit of certain token.
    /// @param _token The address of the asset(USDC or USDT)
    /// @param _pause If deposit for a token need to be paused
    function setDepositPause(
        address _token,
        bool _pause
    ) external onlyRole(VAULT_OPERATOR_ROLE) {
        depositPaused[_token] = _pause;
        emit SetDepositPause(_token, _pause);
    }

    /// @notice Called by admin to withdraw the assets from the vault.
    /// @param _token The address of the asset(USDC or USDT)
    /// @param _amount The amount of the token that admin will withdraw
    function withdrawTokens(
        address _token,
        uint256 _amount
    ) external onlyRole(ASSETS_MANAGEMENT_ROLE) {
        if (!isSupportedToken[_token]) revert UnsupportedToken();

        TransferHelper.safeTransfer(_token, msg.sender, _amount);

        emit TokensWithdrawn(_token, _amount);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Get the list of supported tokens
    /// @return tokens The array of the supported tokens
    function getSupportedTokens()
        external
        view
        returns (address[] memory tokens)
    {
        return supportedTokens;
    }

    /// @notice Get the exchange rate between the receipt token and USD
    /// @return rate The exchange rate between the receipt token and USD. (D18 means 1:1)
    function getRate() public pure returns (uint256 rate) {
        return D18;
    }
}
