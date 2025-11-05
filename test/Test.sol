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
