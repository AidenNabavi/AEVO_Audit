pragma solidity 0.8.13;

import "../lib/SafeTransferLib.sol";
import "../lib/Ownable2Step.sol";
import {IExchangeRate} from "./ExchangeRate.sol";
import {Gauge} from "./Gauge.sol";
import {IConnector, IHub} from "./ConnectorPlug.sol";
import {IMintableERC20} from "./MintableToken.sol";

// یک قرار داد مرکزی که کاری های مینت و برن رو انجام میده 
contract Controller is IHub, Gauge, Ownable2Step {
    using SafeTransferLib for IMintableERC20;
    IMintableERC20 public immutable token__;
    IExchangeRate public exchangeRate__;

    struct UpdateLimitParams {
        bool isMint;
        address connector;
        uint256 maxLimit;
        uint256 ratePerSecond;
    }

    // connector => totalLockedAmount
    mapping(address => uint256) public connectorLockedAmounts;

    // connector => mintLimitParams
    mapping(address => LimitParams) _mintLimitParams;

    // connector => burnLimitParams
    mapping(address => LimitParams) _burnLimitParams;

    // connector => receiver => amount
    mapping(address => mapping(address => uint256)) public pendingMints;

    // connector => amount
    mapping(address => uint256) public connectorPendingMints;

    uint256 public totalMinted;

    error ConnectorUnavailable();

    event ExchangeRateUpdated(address exchangeRate);
    event LimitParamsUpdated(UpdateLimitParams[] updates);
    event TokensWithdrawn(
        address connector,
        address withdrawer,
        address receiver,
        uint256 burnAmount
    );
    event PendingTokensMinted(
        address connector,
        address receiver,
        uint256 mintAmount,
        uint256 pendingAmount
    );




    ///📌wrong named

    event TokensPending(
        address connecter,
        address receiver,
        uint256 pendingAmount,
        uint256 totalPendingAmount
    );
    event TokensMinted(address connecter, address receiver, uint256 mintAmount);

    constructor(address token_, address exchangeRate_) {
        token__ = IMintableERC20(token_);
        exchangeRate__ = IExchangeRate(exchangeRate_);
    }

    function updateExchangeRate(address exchangeRate_) external onlyOwner {
        exchangeRate__ = IExchangeRate(exchangeRate_);
        emit ExchangeRateUpdated(exchangeRate_);
    }



// ببین این تابع یک باگ داره که میشه محدودیت لیمیت رو دور زد بیشتر مینت کرد 
    function updateLimitParams(
        UpdateLimitParams[] calldata updates_
    ) external onlyOwner {
        for (uint256 i; i < updates_.length; i++) {
            if (updates_[i].isMint) { //  اگر این فلک درست بادش یعنی داریم پارامتر های مینت رو آپدیت  میکنیم 
                // این برای مینت 
                _consumePartLimit(0, _mintLimitParams[updates_[i].connector]); // nnnnno  /// این 📌
                _mintLimitParams[updates_[i].connector].maxLimit = updates_[i]
                    .maxLimit;// مقدار این رو maxLimit جدید میکنه 
                _mintLimitParams[updates_[i].connector]//ratePerSecond این رو فقط جدید میکنه 
                    .ratePerSecond = updates_[i].ratePerSecond;
            } else {
                // این برای برن است 
                _consumePartLimit(0, _burnLimitParams[updates_[i].connector]); // to keep current limit in sync
                _burnLimitParams[updates_[i].connector].maxLimit = updates_[i]
                    .maxLimit;
                _burnLimitParams[updates_[i].connector]
                    .ratePerSecond = updates_[i].ratePerSecond;
            }
        }

        emit LimitParamsUpdated(updates_);
    }




    function withdrawFromAppChain(
        address receiver_,
        uint256 burnAmount_,
        uint256 msgGasLimit_,
        address connector_
    ) external payable {
        if (_burnLimitParams[connector_].maxLimit == 0)
            revert ConnectorUnavailable();

        _consumeFullLimit(burnAmount_, _burnLimitParams[connector_]); 

        totalMinted -= burnAmount_;
        token__.burn(msg.sender, burnAmount_);

        uint256 unlockAmount = exchangeRate__.getUnlockAmount(
            burnAmount_,
            connectorLockedAmounts[connector_]
        );
        connectorLockedAmounts[connector_] -= unlockAmount; 

        IConnector(connector_).outbound{value: msg.value}(
            msgGasLimit_,
            abi.encode(receiver_, unlockAmount)
        );

        emit TokensWithdrawn(connector_, msg.sender, receiver_, burnAmount_);
    }





//// wait for me...
    function mintPendingFor(address receiver_, address connector_) external {
        if (_mintLimitParams[connector_].maxLimit == 0)
            revert ConnectorUnavailable();

        uint256 pendingMint = pendingMints[connector_][receiver_];
        (uint256 consumedAmount, uint256 pendingAmount) = _consumePartLimit(
            pendingMint,
            _mintLimitParams[connector_]
        );

        pendingMints[connector_][receiver_] = pendingAmount;
        connectorPendingMints[connector_] -= consumedAmount;
        totalMinted += consumedAmount;

        token__.mint(receiver_, consumedAmount);

        emit PendingTokensMinted(
            connector_,
            receiver_,
            consumedAmount,
            pendingAmount
        );
    }

    /// این تابع هم باااااااا داره حتما 📌📌
    function receiveInbound(bytes memory payload_) external override {
        if (_mintLimitParams[msg.sender].maxLimit == 0)
            revert ConnectorUnavailable();

        (address receiver, uint256 lockAmount) = abi.decode(
            payload_,
            (address, uint256)
        );
            ///@audit overflow
        connectorLockedAmounts[msg.sender] += lockAmount;
        uint256 mintAmount = exchangeRate__.getMintAmount(
            lockAmount,
            connectorLockedAmounts[msg.sender]
        );
        (uint256 consumedAmount, uint256 pendingAmount) = _consumePartLimit(
            mintAmount,
            _mintLimitParams[msg.sender]
        );

        if (pendingAmount > 0) {
            // add instead of overwrite to handle case where already pending amount is left
            pendingMints[msg.sender][receiver] += pendingAmount;
            connectorPendingMints[msg.sender] += pendingAmount;
            emit TokensPending(
                msg.sender,
                receiver,
                pendingAmount,
                pendingMints[msg.sender][receiver]
            );
        }

        totalMinted += consumedAmount;
        token__.mint(receiver, consumedAmount);

        emit TokensMinted(msg.sender, receiver, consumedAmount);
    }

    function getMinFees(
        address connector_,
        uint256 msgGasLimit_
    ) external view returns (uint256 totalFees) {
        return IConnector(connector_).getMinFees(msgGasLimit_);
    }
        
    function getCurrentMintLimit(
        address connector_
    ) external view returns (uint256) {
        return _getCurrentLimit(_mintLimitParams[connector_]);
    }

    function getCurrentBurnLimit(
        address connector_
    ) external view returns (uint256) {
        return _getCurrentLimit(_burnLimitParams[connector_]);
    }

    function getMintLimitParams(
        address connector_
    ) external view returns (LimitParams memory) {
        return _mintLimitParams[connector_];
    }

    function getBurnLimitParams(
        address connector_
    ) external view returns (LimitParams memory) {
        return _burnLimitParams[connector_];
    }
}
