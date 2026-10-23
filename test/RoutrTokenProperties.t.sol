// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {RoutrToken} from "src/RoutrToken.sol";

/// @notice Complements the original deployment/launch tests with allowance lifecycle and arithmetic edges.
/// forge-config: default.fuzz.runs = 1000
contract RoutrTokenPropertiesTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    RoutrToken internal token;
    address internal deployer = makeAddr("property-deployer");
    address internal alice = makeAddr("property-alice");
    address internal bob = makeAddr("property-bob");
    address internal spender = makeAddr("property-spender");

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        vm.prank(deployer);
        token = new RoutrToken();
    }

    function test_oneWeiAndFullSupplyCanMakeARoundTrip() public {
        vm.prank(deployer);
        assertTrue(token.transfer(alice, 1));
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(deployer), SUPPLY - 1);
        vm.prank(alice);
        assertTrue(token.transfer(deployer, 1));

        vm.prank(deployer);
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        vm.prank(alice);
        assertTrue(token.transfer(deployer, SUPPLY));
        _assertUnmovedSupply();
    }

    function test_zeroTransfersFromEmptyHolderEmitEvents() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));

        // A zero delegated transfer needs neither funds nor a positive allowance.
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, alice, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, alice, 0));
        assertEq(token.allowance(alice, spender), 0);
        _assertUnmovedSupply();
    }

    function test_zeroAmountStillRejectsZeroReceiver() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(alice);
        token.transfer(address(0), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(alice, address(0), 0);
        _assertUnmovedSupply();
    }

    function test_zeroApprovalStillRejectsZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(deployer);
        token.approve(address(0), 0);
        assertEq(token.allowance(deployer, address(0)), 0);
        _assertUnmovedSupply();
    }

    function test_zeroOwnerCannotMintThroughTransferFrom() public {
        // The zero owner cannot authorize a spender, even for a zero-value request.
        vm.expectRevert();
        vm.prank(spender);
        token.transferFrom(address(0), alice, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(0), alice, 1);
        assertEq(token.allowance(address(0), spender), 0);
        _assertUnmovedSupply();
    }

    function test_selfTransferCannotBypassBalanceCheck() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, SUPPLY + 1)
        );
        vm.prank(deployer);
        token.transfer(deployer, SUPPLY + 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(alice, 1);
        _assertUnmovedSupply();
    }

    function test_maximumAmountCannotWrapBalancesOrConsumeInfiniteApproval() public {
        _approve(deployer, spender, type(uint256).max);
        bytes memory reason =
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, type(uint256).max);
        vm.expectRevert(reason);
        vm.prank(deployer);
        token.transfer(alice, type(uint256).max);
        vm.expectRevert(reason);
        vm.prank(spender);
        token.transferFrom(deployer, alice, type(uint256).max);
        assertEq(token.allowance(deployer, spender), type(uint256).max);
        _assertUnmovedSupply();
    }

    function test_maximumMinusOneAllowanceIsFinite() public {
        _approve(deployer, spender, type(uint256).max - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, 1));
        assertEq(token.allowance(deployer, spender), type(uint256).max - 2);
        assertEq(token.balanceOf(deployer), SUPPLY - 1);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_exactFullSupplyAllowanceIsExhaustedAndCannotBeReused() public {
        _approve(deployer, spender, SUPPLY);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, SUPPLY));
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(alice), SUPPLY);

        // Replenishing the owner does not restore an already spent permission.
        vm.prank(alice);
        assertTrue(token.transfer(deployer, SUPPLY));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(deployer, bob, 1);
        _assertUnmovedSupply();
    }

    function test_unlimitedApprovalCanBeRevokedAfterUse() public {
        _approve(deployer, spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, 1));
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(deployer, spender, 0);
        _approve(deployer, spender, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(deployer, bob, 1);
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.balanceOf(deployer), SUPPLY - 1);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ownerCallingTransferFromStillNeedsSelfApproval() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        vm.prank(deployer);
        token.transferFrom(deployer, alice, 1);
        _approve(deployer, deployer, 1);
        vm.prank(deployer);
        assertTrue(token.transferFrom(deployer, alice, 1));
        assertEq(token.allowance(deployer, deployer), 0);
        assertEq(token.balanceOf(deployer), SUPPLY - 1);
        assertEq(token.balanceOf(alice), 1);
    }

    function test_spenderCannotBorrowAnotherSpendersApproval() public {
        _approve(deployer, bob, SUPPLY);
        _approve(alice, spender, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(deployer, spender, 1);
        assertEq(token.allowance(deployer, bob), SUPPLY);
        assertEq(token.allowance(alice, spender), type(uint256).max);
        assertEq(token.allowance(deployer, spender), 0);
        _assertUnmovedSupply();
    }

    function test_failedRecipientCheckRollsBackAnAlreadyAuthorizedSpend() public {
        _approve(deployer, spender, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(deployer, address(0), 1);
        assertEq(token.allowance(deployer, spender), 1);
        _assertUnmovedSupply();

        // The same approval remains usable for a valid recipient after the failed transaction.
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, 1));
        assertEq(token.allowance(deployer, spender), 0);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(deployer), SUPPLY - 1);
    }

    function test_delegatedSelfTransferEmitsAndConsumesAllowanceWithoutMovingFunds() public {
        _approve(deployer, spender, SUPPLY);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(deployer, deployer, SUPPLY);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, deployer, SUPPLY));
        assertEq(token.allowance(deployer, spender), 0);
        _assertUnmovedSupply();
    }

    function test_transferToTokenContractDoesNotBurnTheSupply() public {
        vm.prank(deployer);
        assertTrue(token.transfer(address(token), SUPPLY));
        assertEq(token.balanceOf(address(token)), SUPPLY);
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferRoundTripRestoresBalances(uint256 held, uint256 amount) public {
        held = bound(held, 0, SUPPLY);
        amount = bound(amount, 0, held);
        vm.prank(deployer);
        assertTrue(token.transfer(alice, held));
        vm.prank(alice);
        assertTrue(token.transfer(bob, amount));
        vm.prank(bob);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), held);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(deployer), SUPPLY - held);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_approvalReplacementIsIdempotentAndPairScoped(uint256 first, uint256 replacement) public {
        _approve(deployer, spender, first);
        _approve(deployer, bob, first);
        _approve(alice, spender, first);
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(deployer, spender, replacement);
        _approve(deployer, spender, replacement);
        assertEq(token.allowance(deployer, spender), replacement);
        _approve(deployer, spender, replacement);
        assertEq(token.allowance(deployer, spender), replacement);
        assertEq(token.allowance(deployer, bob), first);
        assertEq(token.allowance(alice, spender), first);
        assertEq(token.allowance(spender, deployer), 0);
        _assertUnmovedSupply();
    }

    function testFuzz_finiteAllowanceAccountsForMultipleSpends(uint256 allowed, uint256 first, uint256 second) public {
        allowed = bound(allowed, 0, type(uint256).max - 1);
        first = bound(first, 0, _min(SUPPLY, allowed));
        second = bound(second, 0, _min(SUPPLY - first, allowed - first));
        _approve(deployer, spender, allowed);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, first));
        assertEq(token.allowance(deployer, spender), allowed - first);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, bob, second));
        uint256 remaining = allowed - first - second;
        assertEq(token.allowance(deployer, spender), remaining);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, remaining, remaining + 1)
        );
        vm.prank(spender);
        token.transferFrom(deployer, bob, remaining + 1);
        assertEq(token.allowance(deployer, spender), remaining);
        assertEq(token.balanceOf(alice), first);
        assertEq(token.balanceOf(bob), second);
        assertEq(token.balanceOf(deployer), SUPPLY - first - second);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_failedBalanceCheckPreservesAllowance(uint256 held, uint256 amount, uint256 allowed) public {
        held = bound(held, 0, SUPPLY);
        amount = bound(amount, held + 1, type(uint256).max);
        allowed = bound(allowed, amount, type(uint256).max);
        vm.prank(deployer);
        assertTrue(token.transfer(alice, held));
        _approve(alice, spender, allowed);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, held, amount));
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), allowed);
        assertEq(token.balanceOf(alice), held);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(deployer), SUPPLY - held);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_zeroRecipientFailurePreservesAllowance(uint256 allowed, uint256 amount) public {
        amount = bound(amount, 0, _min(SUPPLY, allowed));
        _approve(deployer, spender, allowed);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(deployer, address(0), amount);
        assertEq(token.allowance(deployer, spender), allowed);
        _assertUnmovedSupply();
    }

    function testFuzz_infiniteApprovalSurvivesMultipleSpends(uint256 first, uint256 second) public {
        first = bound(first, 0, SUPPLY);
        second = bound(second, 0, SUPPLY - first);
        _approve(deployer, spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, alice, first));
        assertEq(token.allowance(deployer, spender), type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, bob, second));
        assertEq(token.allowance(deployer, spender), type(uint256).max);
        assertEq(token.balanceOf(alice), first);
        assertEq(token.balanceOf(bob), second);
        assertEq(token.balanceOf(deployer), SUPPLY - first - second);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_delegatedSelfTransferOnlySpendsAllowance(uint256 amount, uint256 allowed, bool unlimited) public {
        amount = bound(amount, 0, SUPPLY);
        allowed = unlimited ? type(uint256).max : bound(allowed, amount, type(uint256).max - 1);
        _approve(deployer, spender, allowed);
        vm.prank(spender);
        assertTrue(token.transferFrom(deployer, deployer, amount));
        assertEq(token.allowance(deployer, spender), unlimited ? allowed : allowed - amount);
        _assertUnmovedSupply();
    }

    function testFuzz_approvalBeforeFundingRemainsUsableAfterFailedSpend(uint256 amount, uint256 allowed) public {
        amount = bound(amount, 1, SUPPLY);
        allowed = bound(allowed, amount, type(uint256).max);
        _approve(alice, spender, allowed);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, amount));
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), allowed);

        vm.prank(deployer);
        assertTrue(token.transfer(alice, amount));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, amount));
        assertEq(token.allowance(alice, spender), allowed == type(uint256).max ? allowed : allowed - amount);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(deployer), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function _approve(address owner, address approvedSpender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(approvedSpender, amount));
    }

    function _assertUnmovedSupply() private view {
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function _min(uint256 a, uint256 b) private pure returns (uint256) {
        return a < b ? a : b;
    }
}
