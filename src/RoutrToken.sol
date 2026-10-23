// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title routr (ROUTR)
/// @notice A fixed-supply ERC-20. The whole supply of 1,000,000,000 ROUTR (18 decimals) is minted
/// once, in the constructor, to the deployer (`msg.sender`). There is no owner, no minter, no pause,
/// no blocklist and no fee: after deployment the contract has no privileged functions at all, and
/// `totalSupply()` can never grow.
/// @dev On an IdentityMD launch the deployer is the ProjectFactory, which then distributes the supply
/// (swarm share, pool seed, requester remainder) itself. The constructor takes no arguments and
/// makes no external calls, so it deploys on an empty chain. Transfers are plain OpenZeppelin v5
/// ERC-20 transfers: every flow moves exactly the amount requested.
contract RoutrToken is ERC20 {
    /// @notice Token name returned by `name()`.
    string public constant TOKEN_NAME = "routr";

    /// @notice Token symbol returned by `symbol()`.
    string public constant TOKEN_SYMBOL = "ROUTR";

    /// @notice Decimals, the ERC-20 default of 18.
    uint8 public constant DECIMALS = 18;

    /// @notice The fixed supply in minor units: 1,000,000,000 whole tokens at 18 decimals.
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** uint256(DECIMALS);

    /// @notice The address that received the whole supply at deployment.
    address public immutable INITIAL_HOLDER;

    /// @notice Emitted once, when the supply is minted to the deployer.
    /// @param to The deployer that received the supply.
    /// @param amount The full supply in minor units.
    event SupplyMinted(address indexed to, uint256 amount);

    /// @notice Mints the entire fixed supply to the deployer.
    constructor() ERC20(TOKEN_NAME, TOKEN_SYMBOL) {
        INITIAL_HOLDER = msg.sender;
        _mint(msg.sender, TOTAL_SUPPLY);
        emit SupplyMinted(msg.sender, TOTAL_SUPPLY);
    }

    /// @inheritdoc ERC20
    function decimals() public pure override returns (uint8) {
        return DECIMALS;
    }
}
