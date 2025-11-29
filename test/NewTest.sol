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



    // FOLLOW Comments 👇🏽
    function test_BrokenLogic_syncSetsLastUpdateLimit() public {
        address connector = address(0xAAAA);

        //---------------------------step1--------------------------------

        // First, before anything, we check the current limit. It is equal to zero before everything, which is correct. 
        uint256 CurrentLimitInTheFirst = control.getCurrentMintLimit(connector);
        console.log("CurrentLimitInTheFirst : ", CurrentLimitInTheFirst);





        //---------------------------step2--------------------------------

        // input for updateLimitParams
        Controller.UpdateLimitParams[] memory params1=new Controller.UpdateLimitParams[](1);
        params1[0] = Controller.UpdateLimitParams({
            isMint: true,
            connector: connector,
            maxLimit: 864000, // 10 days
            ratePerSecond: 1
        });
        //  Admin calls this function to update it
        control.updateLimitParams(params1);
        // 📌 Now the limit range has changed to 0 → 864000, and every second 1 unit is added from 0 upward until it reaches 864000 👉🏽( ratePerSecond: 1)

      



        //---------------------------step3--------------------------------

        // Note: the current limit starts from 0 and increases second by second until reach to 864000(10 days). This is very important.
        // If you pay close attention, you will see that we read the current limit immediately after the update, without even a single second having passed
        // if you call it 1 second later, the output becomes 1 since ratePerSecond: 1, meaning each second one unit is added to the current limit.
        
        uint256 CurrentLimitBefor10day = control.getCurrentMintLimit(connector);
        console.log("currentLimit in first time : ", CurrentLimitBefor10day); // Its output is therefore 0, and this is correct.






        //---------------------------step4--------------------------------

        // Now exactly 10 days pass, meaning exactly 864000 seconds pass and the current limit becomes full.
        vm.warp(block.timestamp + 10 days); // 10 days = 864000 seconds






        //---------------------------step5--------------------------------

        // Now again we get the current limit after exactly 10 days or the same 864000 seconds.
        // It is fully filled. This exactly shows that the current limit increases by one unit per second.
        
        uint256 CurrentLimitAfter10day = control.getCurrentMintLimit(connector);
        console.log("currentLimit  after 10 days : ", CurrentLimitAfter10day);//Its output is 864000, and this is correct.





        //---------------------------step6--------------------------------

        
        // Now the admin again calls this function to update the max limit, setting it higher than last time — meaning 1,000,000 seconds.
        Controller.UpdateLimitParams[] memory params2=new Controller.UpdateLimitParams[](1);
        params2[0] = Controller.UpdateLimitParams({
            isMint: true,
            connector: connector,
            maxLimit: 1000000,
            ratePerSecond: 1
        });

        //and  owner call it  // her BUG occured👇🏽
        control.updateLimitParams(params2);
        // 📌 Now the range has changed and it should be from 0 to 1,000,000, where every second 1 unit is added to the current limit until it reaches 1,000,000.
        // BUT you see that the current limit right now, immediately after the update, equals 864000 seconds  instead of resetting to 0. 👇🏽

        /// This part is VERY important. Pay close attention.
        /// No time has passed  at all— we are getting the current limit immediately after the admin calls the update.
        /// The output is exactly the previous value (864000) instead of starting from 0.
        uint256 CurrentLimitAfterUpdate = control.getCurrentMintLimit(connector);
        console.log("currentLimit right after the update : ", CurrentLimitAfterUpdate);//BUG

        /// In step 3 you see that the output of current limit immediately after calling update was 0.
        ///LOGIC --->  
        /// Here also the output is taken immediately after calling update for the second time with no delay,
        /// but the output equals the previous value, whereas it should start from zero and go up to 1,000,000.

        assertEq(CurrentLimitAfterUpdate, 864000, "BUG: sync set limit to grown value");
        
        /**

        | Update            Current Limit (Started from )             Current Limit (End)  
        | --------------------------------------------------------------------
        | First Update           0                                                          864000                      // At this point, anyone who wants to mint 864000 must wait 10 days.
        | Second Update     864000                                                 1000000                   // At this point, anyone who wants to mint 864000 can do it in the very first second.
        
        
         */
    }

    }
