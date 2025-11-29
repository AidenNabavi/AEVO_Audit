owner wants to set limit ----> The limit in these contracts is set to control the amount of Mint and Burn within a specific time period.

thats why owner call this function ---->updateLimitParams()
and he set this input for this function 
    isMint = true                          
    connector = <address>             // conector address must be set by owner 
    maxLimit = 864000         // That is, the same 10 days.  //This is the absolute maximum capacity the limit can reach.
    ratePerSecond = 1                //how much is added to currentLimit every second,



every thing OK until here✅











Then, what happens inside this function is:

After this function u`pdateLimitParams()` is called,
the first condition accept because `isMint` is `true`,
and then the function `_consumePartLimit` is called.

`The main problem is right here: the input of this function is always 0, both in the first and second conditions:`
```solidity
if (updates_[i].isMint) { 
    _consumePartLimit(0, _mintLimitParams[updates_[i].connector]); //📌 here the first input is always zero
    _mintLimitParams[updates_[i].connector].maxLimit = updates_[i]
        .maxLimit;// 
    _mintLimitParams[updates_[i].connector]
        .ratePerSecond = updates_[i].ratePerSecond;
}

```


Now, let's see what happens inside the `_consumePartLimit` function when the input is `0`, and why this causes the bug.✅









in this function `_consumePartLimit`  Line  by Line 


 first, it calculates this `currentLimit`                
 what is this  `currentLimit` at all ? 👇🏽
 `This is the currently available limit at this moment. It increases over time (refilling) until it reaches maxLimit`,
```solidity 
uint256 currentLimit = _getCurrentLimit(_params);//
```
This function sums up the previously used limit and adds it to `currentLimit`.




This line updates `lastUpdateTimestamp` to the current time based on the last time this function was called; this is clear
```solidity 
_params.lastUpdateTimestamp = block.timestamp;
```




because `amount_` was always `0`, and `currentLimit` can never be less than `0`. That’s why this condition is always `true` 
```solidity 
if (currentLimit >= amount_) {}
```




`here is very very important `👇🏽

The first condition is executed, and the following happens inside it 👇🏽
```
if (currentLimit >= amount_) {
    _params.lastUpdateLimit = currentLimit - amount_; // 📌 lastUpdateLimit = 864000 - 0 ---> lastUpdateLimit = 864000
}
```
`lastUpdateLimit = 864000 is never updated and never starts from 0`.By itself, this doesn’t cause any issue👇🏽
bug is exactly here happen👇🏽👇🏽👇🏽👇🏽👇🏽👇🏽

The next time the owner calls the function for another update and sets `maxLimit` to 1,000,000, `lastUpdateLimit` will still be 864,000. This value is used in the calculation of `currentLimit` in the `_getCurrentLimit`() function. As a result, `instead of the limit starting from 0 and increasing up to 1,000,000, it starts from 864,000 to 1,000,000`
👆🏽👆🏽👆🏽

This means that in the new limit range that has been set, the limit does not start from zero; it starts from the last limit value of the previous update and goes up to the new maxLimit.




` READ Line by line  ` 
`This is exactly what happens in the test I’m sending you now:




The owner first calls `updateLimitParams` with:
```
maxLimit = 864,000  
ratePerSecond = 1
```

This sets the `maxlimit` to 864,000 seconds, which is about 10 days.
The `currentLimit` starts from `0` and increases by `1` every second until it reaches` 864,000` taking roughly 10 days to fully refill.



After at least 10 days
the `currentLimit` is full.





the owner calls `updateLimitParams` for the second time with:
but this time it sets a larger limit range.👇🏽
```
maxLimit = 1,000,000  
ratePerSecond = 1
```

but this time the `currentLimit` starts from `864,000`  to `1,000,000`  instead of  `0` to`1,000,000`

pay attention no time has passed but it start from `864000` inftead os `0`



After that, exploitation can easily occur👇🏽
when the limit starts from `864,000`, which means that right after the owner’s update, a user can mint or burn up to
 `864,000` tokens instead of `1` . Any user can do this, and this is exactly a bypass and a logic bug.



