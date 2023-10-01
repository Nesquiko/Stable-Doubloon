// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title StableDoubloon
 * @author Nesquiko
 *
 * A ERC20 implementation of StableDoubloon
 *
 * @notice This contract is meant to be governed by SDEngine.
 */
contract StableDoubloon is ERC20Burnable, Ownable {
    error StableDoubloon__MustBeMoreThanZero();
    error StableDoubloon__BurnAmountExceedsBalance();
    error StableDoubloon__NotZeroAddress();

    constructor() ERC20("StableDoubloon", "SD") {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert StableDoubloon__MustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert StableDoubloon__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert StableDoubloon__NotZeroAddress();
        }
        if (_amount <= 0) {
            revert StableDoubloon__MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }
}
