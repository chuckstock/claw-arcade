// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ClawToken ($CLAW)
 * @author Lobster Arcade
 * @notice The native token for Lobster Arcade games
 * @dev Simple ERC20 with mint/burn capabilities and permit for gasless approvals
 */
contract ClawToken is ERC20, ERC20Burnable, ERC20Permit, Ownable {
    /// @notice Maximum supply cap (1 billion tokens)
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @notice Emitted when tokens are minted
    event TokensMinted(address indexed to, uint256 amount);

    /// @notice Error when mint would exceed max supply
    error ExceedsMaxSupply(uint256 requested, uint256 available);

    /**
     * @notice Deploy the $CLAW token
     * @param initialOwner Address that will own the contract and can mint
     * @param initialSupply Initial token supply to mint to owner
     */
    constructor(address initialOwner, uint256 initialSupply)
        ERC20("Claw Token", "CLAW")
        ERC20Permit("Claw Token")
        Ownable(initialOwner)
    {
        if (initialSupply > 0) {
            _mint(initialOwner, initialSupply);
        }
    }

    /**
     * @notice Mint new tokens (owner only)
     * @param to Recipient address
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) external onlyOwner {
        uint256 available = MAX_SUPPLY - totalSupply();
        if (amount > available) {
            revert ExceedsMaxSupply(amount, available);
        }
        _mint(to, amount);
        emit TokensMinted(to, amount);
    }

    /**
     * @notice Get the number of decimals
     * @return Number of decimals (18)
     */
    function decimals() public pure override returns (uint8) {
        return 18;
    }
}
