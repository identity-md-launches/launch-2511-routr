// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {RoutrToken} from "../src/RoutrToken.sol";
import {DeployRoutrToken} from "../script/DeployRoutrToken.s.sol";

/// @notice Stands in for the launch factory: a contract that deploys the token and so becomes
/// `msg.sender` in its constructor, then pays the supply out.
contract FactoryStub {
    RoutrToken public token;

    function launch() external returns (RoutrToken deployed) {
        deployed = new RoutrToken();
        token = deployed;
    }

    function move(address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }
}

contract RoutrTokenTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    RoutrToken internal token;
    address internal deployer = makeAddr("deployer");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal stranger = makeAddr("stranger");

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event SupplyMinted(address indexed to, uint256 amount);

    function setUp() public {
        vm.prank(deployer);
        token = new RoutrToken();
    }

    // ---------------------------------------------------------------- metadata and supply

    function test_metadata() public view {
        assertEq(token.name(), "routr");
        assertEq(token.symbol(), "ROUTR");
        assertEq(token.decimals(), 18);
        assertEq(token.TOKEN_NAME(), "routr");
        assertEq(token.TOKEN_SYMBOL(), "ROUTR");
        assertEq(token.DECIMALS(), 18);
    }

    function test_supplyConstantsMatchTheBrief() public view {
        assertEq(token.TOTAL_SUPPLY(), SUPPLY);
        assertEq(token.TOTAL_SUPPLY(), 1_000_000_000 * 10 ** 18);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_constructorMintsWholeSupplyToDeployer() public view {
        assertEq(token.balanceOf(deployer), SUPPLY, "deployer does not hold the whole supply");
        assertEq(token.INITIAL_HOLDER(), deployer);
        assertEq(token.balanceOf(address(token)), 0, "the contract itself holds tokens");
        assertEq(token.balanceOf(address(this)), 0, "the test holds tokens");
    }

    function test_constructorEmitsMintEvents() public {
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(0), deployer, SUPPLY);
        vm.expectEmit(true, true, true, true);
        emit SupplyMinted(deployer, SUPPLY);
        vm.prank(deployer);
        new RoutrToken();
    }

    /// @dev On a launch the factory is `msg.sender` of the constructor; the supply must land there.
    function test_whenAContractDeploysItHoldsTheSupply() public {
        FactoryStub factory = new FactoryStub();
        RoutrToken launched = factory.launch();
        assertEq(launched.totalSupply(), SUPPLY);
        assertEq(launched.balanceOf(address(factory)), SUPPLY);
        assertEq(launched.INITIAL_HOLDER(), address(factory));

        // The factory pays out the swarm share and the remainder whole: no fee, no burn.
        uint256 swarm = SUPPLY / 10;
        assertTrue(factory.move(alice, swarm));
        assertEq(launched.balanceOf(alice), swarm);
        assertTrue(factory.move(bob, SUPPLY - swarm));
        assertEq(launched.balanceOf(bob), SUPPLY - swarm);
        assertEq(launched.balanceOf(address(factory)), 0);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function test_deployScriptDeploysTheSameToken() public {
        DeployRoutrToken deployScript = new DeployRoutrToken();
        RoutrToken deployed = deployScript.deploy();
        assertEq(deployed.totalSupply(), SUPPLY);
        assertEq(deployed.balanceOf(address(deployScript)), SUPPLY);
        assertEq(deployed.name(), "routr");
        assertEq(deployed.symbol(), "ROUTR");
    }

    function test_eachDeploymentIsIndependent() public {
        vm.prank(alice);
        RoutrToken second = new RoutrToken();
        assertEq(second.totalSupply(), SUPPLY);
        assertEq(second.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    // ---------------------------------------------------------------- transfers

    function test_transferMovesExactAmount() public {
        vm.prank(deployer);
        vm.expectEmit(true, true, true, true);
        emit Transfer(deployer, alice, 1_000 ether);
        assertTrue(token.transfer(alice, 1_000 ether));
        assertEq(token.balanceOf(alice), 1_000 ether);
        assertEq(token.balanceOf(deployer), SUPPLY - 1_000 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferWholeBalanceAndZero() public {
        vm.prank(deployer);
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(alice), SUPPLY);

        vm.prank(bob);
        assertTrue(token.transfer(alice, 0), "a zero transfer from an empty account must succeed");
        assertEq(token.balanceOf(alice), SUPPLY);
    }

    function test_transferToSelfKeepsBalance() public {
        vm.prank(deployer);
        assertTrue(token.transfer(deployer, 5 ether));
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    function test_transferRevertsOnInsufficientBalance() public {
        vm.prank(deployer);
        token.transfer(alice, 10 ether);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 10 ether, 11 ether)
        );
        token.transfer(bob, 11 ether);
        assertEq(token.balanceOf(alice), 10 ether);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_transferRevertsFromEmptyAccount() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, stranger, 0, 1));
        token.transfer(alice, 1);
    }

    function test_transferToZeroAddressReverts() public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1 ether);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    // ---------------------------------------------------------------- allowances

    function test_approveSetsAllowanceAndEmits() public {
        vm.prank(deployer);
        vm.expectEmit(true, true, true, true);
        emit Approval(deployer, alice, 500 ether);
        assertTrue(token.approve(alice, 500 ether));
        assertEq(token.allowance(deployer, alice), 500 ether);
    }

    function test_approveZeroAddressSpenderReverts() public {
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
    }

    function test_transferFromSpendsAllowance() public {
        vm.prank(deployer);
        token.approve(alice, 500 ether);

        vm.prank(alice);
        vm.expectEmit(true, true, true, true);
        emit Transfer(deployer, bob, 200 ether);
        assertTrue(token.transferFrom(deployer, bob, 200 ether));

        assertEq(token.balanceOf(bob), 200 ether);
        assertEq(token.balanceOf(deployer), SUPPLY - 200 ether);
        assertEq(token.allowance(deployer, alice), 300 ether);
    }

    function test_transferFromWithMaxAllowanceDoesNotDecrease() public {
        vm.prank(deployer);
        token.approve(alice, type(uint256).max);
        vm.prank(alice);
        token.transferFrom(deployer, bob, 1 ether);
        assertEq(token.allowance(deployer, alice), type(uint256).max);
    }

    function test_transferFromRevertsWithoutAllowance() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, stranger, 0, 1 ether));
        token.transferFrom(deployer, stranger, 1 ether);
        assertEq(token.balanceOf(deployer), SUPPLY);
        assertEq(token.balanceOf(stranger), 0);
    }

    function test_transferFromRevertsBeyondAllowance() public {
        vm.prank(deployer);
        token.approve(alice, 100 ether);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 100 ether, 101 ether)
        );
        token.transferFrom(deployer, bob, 101 ether);
        assertEq(token.allowance(deployer, alice), 100 ether);
    }

    function test_transferFromRevertsWhenOwnerBalanceTooLow() public {
        vm.prank(alice);
        token.approve(bob, 50 ether);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 50 ether));
        token.transferFrom(alice, bob, 50 ether);
    }

    /// @dev `transferFrom` moves tokens only with the owner's allowance: even the deployer cannot
    /// pull from a holder without one.
    function test_deployerCannotPullFromHolderWithoutAllowance() public {
        vm.prank(deployer);
        token.transfer(alice, 10 ether);
        vm.prank(deployer);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        token.transferFrom(alice, deployer, 1);
        assertEq(token.balanceOf(alice), 10 ether);
    }

    // ---------------------------------------------------------------- no privileged powers

    /// @dev None of the common admin or mint entry points exist. Whoever calls them, from any
    /// address including the deployer, the supply never grows and no balance appears.
    function test_noMintOrAdminEntryPointIncreasesSupply() public {
        string[10] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "setOwner(address)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "initialize(address)",
            "unpause()",
            "setMinter(address)"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], stranger, type(uint128).max);
            vm.prank(stranger);
            (bool ok,) = address(token).call(data);
            assertFalse(ok, string.concat("call unexpectedly succeeded: ", signatures[i]));
            vm.prank(deployer);
            (ok,) = address(token).call(data);
            assertFalse(ok, string.concat("deployer call unexpectedly succeeded: ", signatures[i]));
            assertEq(token.totalSupply(), SUPPLY, signatures[i]);
            assertEq(token.balanceOf(stranger), 0, signatures[i]);
        }
    }

    /// @dev No pause, blocklist, freeze, lock or seize exists, so a holder keeps control of its
    /// balance whatever the deployer tries.
    function test_noPrivilegedCallMovesOrFreezesAHolder() public {
        vm.prank(deployer);
        token.transfer(alice, 1_000 ether);
        string[12] memory signatures = [
            "pause()",
            "blacklist(address)",
            "blocklist(address)",
            "freeze(address)",
            "freezeAccount(address)",
            "setBlacklist(address,bool)",
            "setBlocked(address,bool)",
            "lock(address)",
            "disableTransfers()",
            "setTransfersEnabled(bool)",
            "burnFrom(address,uint256)",
            "seize(address)"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            vm.prank(deployer);
            (bool ok,) = address(token).call(abi.encodeWithSignature(signatures[i], alice, true));
            assertFalse(ok, string.concat("call unexpectedly succeeded: ", signatures[i]));
        }
        assertEq(token.balanceOf(alice), 1_000 ether, "a privileged call moved the holder's balance");
        vm.prank(alice);
        assertTrue(token.transfer(bob, 500 ether), "the holder can no longer transfer");
        assertEq(token.balanceOf(bob), 500 ether);
    }

    function test_noOwnerFunction() public {
        (bool ok,) = address(token).call(abi.encodeWithSignature("owner()"));
        assertFalse(ok, "token exposes owner()");
        (ok,) = address(token).call(abi.encodeWithSignature("paused()"));
        assertFalse(ok, "token exposes paused()");
    }

    function test_rejectsEther() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(token).call{value: 1 ether}("");
        assertFalse(ok, "token accepted ether");
        assertEq(address(token).balance, 0);
    }

    // ---------------------------------------------------------------- bytecode properties

    function test_runtimeCodeSizeWithinLimit() public view {
        uint256 size = address(token).code.length;
        assertGt(size, 0);
        assertLe(size, 24_576, "runtime exceeds EIP-170");
    }

    /// @dev Mirrors the launch floor's opcode scan: no reachable DELEGATECALL, CALLCODE or SELFDESTRUCT.
    function test_runtimeCodeHasNoDelegatecallOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        bool reachable = true;
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op == 0x5B) reachable = true;
            if (op >= 0x60 && op <= 0x7F) {
                i += (op - 0x5F);
                continue;
            }
            if (reachable) {
                assertTrue(op != 0xF4, "runtime code contains DELEGATECALL");
                assertTrue(op != 0xF2, "runtime code contains CALLCODE");
                assertTrue(op != 0xFF, "runtime code contains SELFDESTRUCT");
            }
            if (op == 0x00 || op == 0x56 || op == 0xF3 || op == 0xFD || op == 0xFE || op == 0xFF) reachable = false;
        }
    }

    // ---------------------------------------------------------------- fuzz

    function testFuzz_transferConservesSupply(address to, uint256 amount) public {
        vm.assume(to != address(0));
        amount = bound(amount, 0, SUPPLY);
        vm.prank(deployer);
        assertTrue(token.transfer(to, amount));
        if (to == deployer) {
            assertEq(token.balanceOf(deployer), SUPPLY);
        } else {
            assertEq(token.balanceOf(to), amount);
            assertEq(token.balanceOf(deployer), SUPPLY - amount);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferAboveBalanceReverts(uint256 held, uint256 amount) public {
        held = bound(held, 0, SUPPLY - 1);
        amount = bound(amount, held + 1, SUPPLY);
        vm.prank(deployer);
        token.transfer(alice, held);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, held, amount));
        token.transfer(bob, amount);
    }

    function testFuzz_transferFromRespectsAllowance(uint256 allowance, uint256 amount) public {
        allowance = bound(allowance, 0, SUPPLY);
        amount = bound(amount, 0, SUPPLY);
        vm.prank(deployer);
        token.approve(alice, allowance);
        vm.prank(alice);
        if (amount > allowance) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, allowance, amount)
            );
            token.transferFrom(deployer, bob, amount);
        } else {
            assertTrue(token.transferFrom(deployer, bob, amount));
            assertEq(token.balanceOf(bob), amount);
            assertEq(token.allowance(deployer, alice), allowance - amount);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_chainOfTransfersConservesSupply(uint256 a, uint256 b, uint256 c) public {
        a = bound(a, 0, SUPPLY);
        b = bound(b, 0, a);
        c = bound(c, 0, b);
        vm.prank(deployer);
        token.transfer(alice, a);
        vm.prank(alice);
        token.transfer(bob, b);
        vm.prank(bob);
        token.transfer(stranger, c);
        uint256 sum =
            token.balanceOf(deployer) + token.balanceOf(alice) + token.balanceOf(bob) + token.balanceOf(stranger);
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
