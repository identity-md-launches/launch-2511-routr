// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {RoutrToken} from "src/RoutrToken.sol";

/// @notice Drives a closed set of holders through valid operations and deliberate failures.
/// @dev Credits/debits come from requested transfers, never from observed token balances.
/// All token movement stays within actors, so summing their balances accounts for the whole supply.
contract RoutrTokenHandler is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    RoutrToken public immutable token;
    address[4] public actors;
    mapping(address => uint256) public credits;
    mapping(address => uint256) public debits;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    uint256 public positiveTransfers;
    uint256 public positiveDelegatedTransfers;
    uint256 public expectedReverts;

    constructor(RoutrToken token_, address[4] memory actors_) {
        token = token_;
        actors = actors_;
        // The brief, rather than the implementation's totalSupply(), is the accounting oracle.
        credits[actors[0]] = SUPPLY;
        for (uint256 i = 1; i < actors.length; ++i) {
            _transfer(actors[0], actors[i], SUPPLY / 4);
        }
        // Seed finite and unlimited permissions so delegated transfers are useful immediately.
        // Other pairs (including self-approvals) start at zero and can be changed by the fuzzer.
        for (uint256 i; i < actors.length; ++i) {
            _approve(actors[i], actors[(i + 1) % actors.length], SUPPLY / 8);
            _approve(actors[i], actors[(i + 2) % actors.length], type(uint256).max);
        }
        positiveTransfers = 0;
    }

    function expectedBalance(address holder) public view returns (uint256) {
        return credits[holder] - debits[holder];
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        address from = _actor(fromSeed);
        _transfer(from, _actor(toSeed), _amount(amountSeed, expectedBalance(from)));
    }

    function transferAll(uint256 fromSeed, uint256 toSeed) external {
        address from = _actor(fromSeed);
        _transfer(from, _actor(toSeed), expectedBalance(from));
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, uint8 mode) external {
        uint256 amount;
        mode %= 5;
        if (mode == 1) amount = type(uint256).max;
        else if (mode == 2) amount = type(uint256).max - 1;
        else if (mode == 3) amount = bound(amountSeed, 0, SUPPLY);
        else if (mode == 4) amount = amountSeed;
        // mode 0 explicitly revokes the allowance, including previously unlimited approvals.
        _approve(_actor(ownerSeed), _actor(spenderSeed), amount);
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 available = expectedBalance(owner);
        uint256 amount = _amount(amountSeed, available < allowed ? available : allowed);

        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount), "valid delegated transfer returned false");
        _recordTransfer(owner, to, amount);
        if (allowed != type(uint256).max) expectedAllowance[owner][spender] = allowed - amount;
        if (amount > 0) ++positiveDelegatedTransfers;
    }

    function transferInvalid(uint256 fromSeed, uint256 toSeed, uint256 amountSeed, bool zeroReceiver) external {
        address from = _actor(fromSeed);
        uint256 balance = expectedBalance(from);
        address to = zeroReceiver ? address(0) : _actor(toSeed);
        uint256 amount = zeroReceiver ? _amount(amountSeed, balance) : bound(amountSeed, balance + 1, type(uint256).max);
        bytes memory reason = zeroReceiver
            ? abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
            : abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount);
        _reject(from, abi.encodeCall(token.transfer, (to, amount)), reason);
    }

    function approveZeroSpender(uint256 ownerSeed, uint256 amount) external {
        _reject(
            _actor(ownerSeed),
            abi.encodeCall(token.approve, (address(0), amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
        );
    }

    /// @dev Each mode reaches a distinct failure, even after earlier calls changed approvals.
    /// Preparatory approvals are recorded; the rejected transfer must change nothing afterwards.
    function transferFromInvalid(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint8 mode) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        address to = _actor(toSeed);
        uint256 balance = expectedBalance(owner);
        uint256 allowed = expectedAllowance[owner][spender];
        uint256 amount;
        bytes memory reason;
        mode %= 4;

        if (mode == 0) {
            // There is no amount above an infinite approval; make it finite before overspending.
            if (allowed == type(uint256).max) {
                allowed = type(uint256).max - 1;
                _approve(owner, spender, allowed);
            }
            amount = allowed + 1;
            reason = abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount);
        } else if (mode == 1) {
            amount = balance + 1;
            _approve(owner, spender, amount);
            reason = abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, amount);
        } else if (mode == 2) {
            to = address(0);
            amount = balance < allowed ? balance : allowed;
            reason = abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0));
        } else {
            _approve(owner, spender, 0);
            amount = 1;
            reason = abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, amount);
        }
        _reject(spender, abi.encodeCall(token.transferFrom, (owner, to, amount)), reason);
    }

    function _actor(uint256 seed) private view returns (address) {
        return actors[seed % actors.length];
    }

    /// @dev Regularly select zero, one wei and the full available amount, as well as interior values.
    function _amount(uint256 seed, uint256 maximum) private pure returns (uint256) {
        if (seed % 4 == 0) return 0;
        if (seed % 4 == 1) return maximum == 0 ? 0 : 1;
        if (seed % 4 == 2) return maximum;
        return bound(seed, 0, maximum);
    }

    function _transfer(address from, address to, uint256 amount) private {
        vm.prank(from);
        assertTrue(token.transfer(to, amount), "valid transfer returned false");
        _recordTransfer(from, to, amount);
        if (amount > 0) ++positiveTransfers;
    }

    function _recordTransfer(address from, address to, uint256 amount) private {
        // Recording both sides also handles self-transfers without a special-case oracle.
        debits[from] += amount;
        credits[to] += amount;
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount), "valid approval returned false");
        expectedAllowance[owner][spender] = amount;
    }

    function _reject(address caller, bytes memory data, bytes memory reason) private {
        vm.prank(caller);
        (bool success, bytes memory returned) = address(token).call(data);
        assertFalse(success, "invalid operation succeeded");
        assertEq(returned, reason, "unexpected revert reason");
        ++expectedReverts;
    }
}
