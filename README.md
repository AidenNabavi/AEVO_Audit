
#  Smart Contract Vulnerability Report
**AEVO**:

##  Vulnerability Title 

Broken Logic Bypass LimitMechanism  in updateLimitParams 

## 🗂 Report Type

Smart Contract


## 🔗 Target

- https://arbiscan.io/address/0x80d40e32fad8be8da5c6a42b8af1e181984d137c?utm_source=immunefi#code

- https://vscode.blockscan.com/42161/0x80d40e32fad8be8da5c6a42b8af1e181984d137c



## Asset

Controller.sol

Gauge.sol



##  Rating

Severity: High 

Impact: Medium ~ High

Likelihood: High 

Attack Complexity : Low



##  Description


1_

in this contract `Controller.sol` the mint rate-limiting mechanism, the `updateLimitParams()` function updates the configuration parameters (`maxLimit` and `ratePerSecond`), but it does not recompute the `currentLimit` value from scratch.

instead, it keeps the previous `currentLimit` value as-is — even if the limit was already completely full at the moment of update.

as a result, after the parameters are changed, a user (or attacker) can immediately mint up to the full limit  without waiting for the gradual refill controlled by `ratePerSecond`.

this effectively   ------> bypasses the intended rate-limiting mechanism.


the issue occurs inside the `updateLimitParams()` function because `currentLimit` is  not recalculated  based on the elapsed time and new parameters. It is simply carried over, allowing the limit to remain  full  eveen  when the parameters are changed.


These three functions work together:

 call sequence:
 `updateLimitParams()` is called from `Controller.sol`
 `updateLimitParams()` calls `_consumePartLimit()`  in `Gauge.sol`
 `_consumePartLimit()` calls `_getCurrentLimit()` in `Gauge.sol`

 so the flow is:
 updateLimitParams() -> _consumePartLimit() -> _getCurrentLimit()



we need to understand the difference between these values:


`maxLimit`:
    This is the absolute maximum capacity the limit can reach.
    The currentLimit cannot exceed this value.

`currentLimit`:
    This is the currently available limit at this moment.
    It increases over time (refilling) until it reaches maxLimit,
    and decreases when minting or burning consumes capacity.

`ratePerSecond`:
    This defines how fast the currentLimit refills.
    In other words, how much is added to currentLimit every second,
    until it fully reaches maxLimit again.


🐧Everything is explained step-by-step inside the test file 👇🏽FLOW & POC





2_

 just Best Practice:
  in this contract `Controller.sol`
  The word `connecter` is misspelled. Correct spelling is `connector`.

event TokensPending(
    address connecter, ----> connector
    address receiver,
    uint256 pendingAmount,
    uint256 totalPendingAmount
);



##  Impact

- the bug causes the limits to reach the maxLimit much faster, meaning the system assumes the capacity is refilled over time or after each parameter update, even without real activity.

-  as a result, users or connectors can mint more tokens much earlier, since the currentLimit value jumps closer to the maxLimit immediately after an update.

- when the owner increases the maxLimit, the system continues from the previous limit (e.g., 500) instead of resetting to zero — allowing the refill to start from a higher point and reach the new maximum almost instantly.

- this behavior can lead to over-minting, token dilution, and potential liquidity drain if the protocol relies on these limits for mint control or collateral safety.



##  Vulnerability Details


```solidity 

    struct UpdateLimitParams {
        bool isMint;
        address connector;
        uint256 maxLimit;
        uint256 ratePerSecond;
    }


    function updateLimitParams(
        UpdateLimitParams[] calldata updates_
    ) external onlyOwner {
        for (uint256 i; i < updates_.length; i++) {
            if (updates_[i].isMint) { 
                ///@audit Logic break
                _consumePartLimit(0, _mintLimitParams[updates_[i].connector]); // to keep current limit in sync
                _mintLimitParams[updates_[i].connector].maxLimit = updates_[i]
                    .maxLimit;
                _mintLimitParams[updates_[i].connector]
                    .ratePerSecond = updates_[i].ratePerSecond;
            } else {
                _consumePartLimit(0, _burnLimitParams[updates_[i].connector]); // to keep current limit in sync
                _burnLimitParams[updates_[i].connector].maxLimit = updates_[i]
                    .maxLimit;
                _burnLimitParams[updates_[i].connector]
                    .ratePerSecond = updates_[i].ratePerSecond;
            }
        }

        emit LimitParamsUpdated(updates_);
    }








    struct LimitParams {
        uint256 lastUpdateTimestamp;
        uint256 ratePerSecond;
        uint256 maxLimit;
        uint256 lastUpdateLimit;
    }

    function _consumePartLimit(
        uint256 amount_,
        LimitParams storage _params
    ) internal returns (uint256 consumedAmount, uint256 pendingAmount) {
        uint256 currentLimit = _getCurrentLimit(_params);
        _params.lastUpdateTimestamp = block.timestamp;

        if (currentLimit >= amount_) {
            _params.lastUpdateLimit = currentLimit - amount_; میمونه 
            consumedAmount = amount_;
            pendingAmount = 0;
        } else {
            _params.lastUpdateLimit = 0;
            consumedAmount = currentLimit;
            pendingAmount = amount_ - currentLimit;
        }
    }



    function _getCurrentLimit(
        LimitParams storage _params
    ) internal view returns (uint256 _limit) {
        uint256 timeElapsed = block.timestamp - _params.lastUpdateTimestamp;
        uint256 limitIncrease = timeElapsed * _params.ratePerSecond;

        if (limitIncrease + _params.lastUpdateLimit > _params.maxLimit) {
            _limit = _params.maxLimit;
        } else {
            _limit = limitIncrease + _params.lastUpdateLimit;
        }
    }
```





## How to fix it (Recommended)


 in this contract ------> Gauge.sol 
make updates reset the limit to zero so after any parameter change the refill starts from 0. Add a small helper in Gauge.sol:

```solidity 

    function _resetLimitOnUpdate(LimitParams storage _params) internal {
        _params.lastUpdateTimestamp = block.timestamp;
        _params.lastUpdateLimit = 0;
    }


```
then in `Controller.updateLimitParams()` replace the `_consumePartLimit(0,)` calls with `_resetLimitOnUpdate()` before you set the new maxLimit and ratePerSecond (order doesn't matter much here but clear intent helps):

```solidity
    if (updates_[i].isMint) {
        _resetLimitOnUpdate(_mintLimitParams[updates_[i].connector]); //📌 reset refill progress
        _mintLimitParams[updates_[i].connector].maxLimit = updates_[i].maxLimit;
        _mintLimitParams[updates_[i].connector].ratePerSecond = updates_[i].ratePerSecond;
    } else {
        _resetLimitOnUpdate(_burnLimitParams[updates_[i].connector]);
        _burnLimitParams[updates_[i].connector].maxLimit = updates_[i].maxLimit;
        _burnLimitParams[updates_[i].connector].ratePerSecond = updates_[i].ratePerSecond;
    }

```


## 🔗 References

- https://arbiscan.io/address/0x80d40e32fad8be8da5c6a42b8af1e181984d137c?utm_source=immunefi#code

- https://vscode.blockscan.com/42161/0x80d40e32fad8be8da5c6a42b8af1e181984d137c

Gauge.sol        ---->      _getCurrentLimit()      _consumePartLimit()

Controller.sol   ----->      updateLimitParams()



##  Proof of Concept (PoC)

POC & FLOW

FLOW 👇🏽

 1:
  owner first calls `updateLimitParams()` and sets the parameters:
    isMint = true
    connector = <address>
    maxLimit = 864000   // ~10 days capacity
    ratePerSecond = 1


 2:
 time passes, and `currentLimit` refills until it reaches `maxLimit`.
    currentLimit → 864000 (full)


 3:
 the owner calls `updateLimitParams()` again to update parameters.


 4:
 this time, the owner increases the maxLimit:
    isMint = true
    connector = <address>
    maxLimit = 950400   // ~11 days capacity
    ratePerSecond = 1

5:
expected correct behavior:
    After updating parameters, `currentLimit` should reset to 0
    and gradually refill again up to the new `maxLimit` (950400).

6:
actual (buggy) behavior:
    Right after the update, calling `getCurrentMintLimit(connector)`
    returns the previous value (864000), not 0.
    So the system continues from the old filled limit.

attacker:
    An attacker (or any user) is able to mint up to 864000 tokens
    immediately after the update, instead of starting from 1.
    This allows rapid minting much faster than intended.



POC Step by Step 👇🏽

Download and run the project from the link below 👇🏽


```solidity 

    // SPDX-License-Identifier: MIT
    pragma solidity 0.8.13;

    import "forge-std/Test.sol";
    import "../src/Controller.sol";
    import "forge-std/console.sol";


// this contract is also a mock deployment because we need its address
// when deploying the Controller contract in this test.
    contract token_mock  {
        mapping(address => uint256) public balanceOf;
        uint256 public totalSupply;

        function mint(address to, uint256 amount) external  {
            balanceOf[to] += amount;
            totalSupply += amount;
        }

        function burn(address from, uint256 amount) external  {
            require(balanceOf[from] >= amount, "not enough");
            balanceOf[from] -= amount;
            totalSupply -= amount;
        }
    }

// this contract is also a mock deployment because we need its address
// when deploying the Controller contract in this test.
    contract exchangeRate_mock is IExchangeRate {
        function getMintAmount(uint256 lockAmount, uint256 ) external pure override returns (uint256) {
            return lockAmount;
        }

        function getUnlockAmount(uint256 burnAmount, uint256 ) external pure override returns (uint256) {
            return burnAmount;
        }
    }

    

/*

📌
Before anything, it's important to understand the difference between these values:

maxLimit:
    This is the absolute maximum capacity the limit can reach.
    The currentLimit cannot exceed this value.

currentLimit:
    This is the currently available limit at this moment.
    It increases over time (refilling) until it reaches maxLimit,
    and decreases when minting or burning consumes capacity.

ratePerSecond:
    This defines how fast the currentLimit refills.
    In other words, how much is added to currentLimit every second,
    until it fully reaches maxLimit again.



Read This Flow 👇🏽

 1:
 the owner first calls updateLimitParams() and sets the parameters:
    isMint = true
    connector = <address>
    maxLimit = 864000   // ~10 days capacity
    ratePerSecond = 1


 2:
 time passes, and currentLimit refills until it reaches `maxLimit`.
    currentLimit → 864000 (full)


 3:
 the owner calls updateLimitParams() again to update parameters.


 4:
 this time, the owner increases the maxLimit:
    isMint = true
    connector = <address>
    maxLimit = 950400   // ~11 days capacity
    ratePerSecond = 1

5:
expected correct behavior:
    After updating parameters, currentLimit should reset to 0
    and gradually refill again up to the new `maxLimit` (950400).

6:
actual (buggy) behavior:
    Right after the update, calling getCurrentMintLimit(connector)
    returns the previous value (864000), not 0.
    So the system continues from the old filled limit.

attacker:
    An attacker (or any user) is able to mint up to 864000 tokens
    immediately after the update, instead of starting from 1.
    This allows rapid minting much faster than intended.

*/
// use this -----> forge test -vvv
    contract TestBrokenLogic is Test {
        Controller control;
        token_mock token;
        exchangeRate_mock exchangeRate;

        function setUp() public {
            token = new token_mock();
            exchangeRate = new exchangeRate_mock();
            control = new Controller(address(token), address(exchangeRate)); // here you provide the mock token and mock exchangeRate addresses
            // controller owner is this test contract (deployer)
        }

        /// @dev PoC test: show that calling updateLimitParams second time causes lastUpdateLimit
        /// to be set to the computed currentLimit (i.e. sync-with-amount-zero behavior).
        function test_BrokenLogic_syncSetsLastUpdateLimit() public {

            // this is the connector address
            address connector = address(0xAAAA);

            // build the input data
            /// @dev for example the owner wants to call updateLimitParams so we prepare the calldata
            /// @param maxLimit we set 10 days here which, in seconds, equals 864000
            /// @param ratePerSecond we set 1, meaning currentLimit increases by 1 each second until it reaches maxLimit
            Controller.UpdateLimitParams[] memory params1=new Controller.UpdateLimitParams[](1);
            params1[0] = Controller.UpdateLimitParams({
                isMint: true,
                connector: connector,
                maxLimit: 864000, // 10 days
                ratePerSecond: 1
            });

            /// @dev there's no need for an external admin call here because the contract owner is this test contract (onlyOwner)
            // address(this) ---> caller    note: the access control level is unrelated to this vulnerability

            control.updateLimitParams(params1);

            /// @notice immediately after the update we check currentLimit; it should be zero because no time has passed since the update
            uint256 CurrentLimitBefor10day = control.getCurrentMintLimit(connector);
            console.log("currentLimit in first time : ", CurrentLimitBefor10day);

            /// @notice 10 days pass and the max limit becomes full
            vm.warp(block.timestamp + 10 days); // 10 days = 864000 seconds

            /// @notice now we read the currentLimit again and expect it to equal 864000
            uint256 CurrentLimitAfter10day = control.getCurrentMintLimit(connector);
            console.log("currentLimit  after 10 days : ", CurrentLimitAfter10day);

            /// @notice everything behaved correctly up to this point — refill logic worked as expected.

            /// @notice Now the owner calls updateLimitParams again after 10 days
            /// @notice Prepare the new parameters:
            /// @param maxLimit this time the owner sets maxLimit to 11 days (950400 seconds), i.e. larger than before
            /// @dev The vulnerability begins exactly here when the owner updates maxLimit to a larger value
            /// @param ratePerSecond remains 1
            Controller.UpdateLimitParams[] memory params2=new Controller.UpdateLimitParams[](1);
            params2[0] = Controller.UpdateLimitParams({
                isMint: true,
                connector: connector,
                maxLimit: 950400, // 11 days
                ratePerSecond: 1
            });

            // call update
            control.updateLimitParams(params2);

            /// @notice Immediately after the update we read currentLimit — it SHOULD be reset because parameters changed

            /// @notice we read currentLimit again.
            /// @notice because maxLimit was just updated, currentLimit should have been reset and start from 0 up to 950400.
            /// @notice however, as you see below, the returned value starts from the previous full value (864000) even though no time has passed.
            /// @notice Note that currentLimit normally increases with time until it reaches maxLimit, but here it starts from the previous value right after the update.
            /// @notice this is caused by incorrect logic in `_consumePartLimit`.
            uint256 CurrentLimitAfterUpdate = control.getCurrentMintLimit(connector);
            console.log("currentLimit right after the update, even though no time has passed at all: ", CurrentLimitAfterUpdate);

            /// 📌 now the attacker can exploit:
            /// @notice ----> The attacker can bypass the intended limit because the currentLimit did not reset.
            /// @notice the currentLimit should be reset to 0 after each parameter update and then increase by ratePerSecond each second.
            /// @notice Instead, currentLimit is 864000, so the attacker can mint 864000 immediately after the parameter update.
            /// @notice this allows the limit to be bypassed.

            /// @notice here currentLimit before the update (when it was full) equals currentLimit immediately after the update with no elapsed time — it should have been zero instead.
            // POC 
            assertEq(CurrentLimitAfter10day, CurrentLimitAfterUpdate, "BUG: sync set limit to grown value");


            
            }
    }

    
```








