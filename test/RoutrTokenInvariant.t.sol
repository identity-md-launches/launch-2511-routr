// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {RoutrToken} from "src/RoutrToken.sol";
import {RoutrTokenHandler} from "test/handlers/RoutrTokenHandler.sol";

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract RoutrTokenInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    RoutrToken internal token;
    RoutrTokenHandler internal handler;
    address[4] internal actors;

    function setUp() public {
        actors = [
            makeAddr("invariant-deployer"),
            makeAddr("invariant-alice"),
            makeAddr("invariant-bob"),
            makeAddr("invariant-carol")
        ];
        vm.prank(actors[0]);
        token = new RoutrToken();
        handler = new RoutrTokenHandler(token, actors);

        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = handler.transfer.selector;
        selectors[1] = handler.transferAll.selector;
        selectors[2] = handler.approve.selector;
        selectors[3] = handler.transferFrom.selector;
        selectors[4] = handler.transferInvalid.selector;
        selectors[5] = handler.approveZeroSpender.selector;
        selectors[6] = handler.transferFromInvalid.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// @notice Fixed issuance and exact transfer accounting must hold after every action, including failures.
    function invariant_supplyAndEveryHolderBalanceMatchTheLedger() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            uint256 balance = token.balanceOf(actors[i]);
            assertEq(balance + handler.debits(actors[i]), handler.credits(actors[i]), "holder accounting diverged");
            sum += balance;
        }
        assertEq(sum, SUPPLY, "tokens were created, destroyed or sent outside the tracked holders");
        assertEq(token.totalSupply(), SUPPLY, "fixed supply changed");
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.INITIAL_HOLDER(), actors[0]);
        assertEq(token.name(), "routr");
        assertEq(token.symbol(), "ROUTR");
        assertEq(token.decimals(), 18);
    }

    /// @notice Only approvals and successful finite-allowance spending may change any permission.
    function invariant_allAllowancesMatchAuthorizations() public view {
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.allowance(actors[i], address(0)), 0, "zero spender acquired an allowance");
            assertEq(token.allowance(address(0), actors[i]), 0, "zero owner acquired an allowance");
            for (uint256 j; j < actors.length; ++j) {
                assertEq(
                    token.allowance(actors[i], actors[j]),
                    handler.expectedAllowance(actors[i], actors[j]),
                    "allowance diverged, leaked across pairs or was spent by a failed call"
                );
            }
        }
    }

    /// @dev A deterministic sequence proves that the handler reaches nonzero movement and every failure mode.
    function test_handlerExercisesTransfersRevocationAndRollback() public {
        handler.transfer(0, 1, 1);
        handler.transferFrom(1, 2, 3, 1);
        handler.approve(0, 3, 0, 1);
        handler.transferFrom(0, 3, 0, 2);
        handler.transferInvalid(0, 1, type(uint256).max, false);
        handler.transferInvalid(1, 2, 0, true);
        handler.approveZeroSpender(2, type(uint256).max);
        for (uint8 mode; mode < 4; ++mode) {
            handler.transferFromInvalid(0, 3, 1, mode);
            invariant_supplyAndEveryHolderBalanceMatchTheLedger();
            invariant_allAllowancesMatchAuthorizations();
        }
        handler.approve(2, 1, 0, 2);
        handler.transferAll(3, 2);
        assertGt(handler.positiveTransfers(), 0);
        assertGt(handler.positiveDelegatedTransfers(), 0);
        assertEq(handler.expectedReverts(), 7);
        invariant_supplyAndEveryHolderBalanceMatchTheLedger();
        invariant_allAllowancesMatchAuthorizations();
    }
}
