// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {StoryPreDepositVault} from "../src/StoryPreDepositVault.sol";
import {Token} from "../src/Token.sol";
import "../src/Errors.sol";

import {MockToken} from "./MockToken.sol";

contract StoryPreDepositVaultTest is Test {
    MockToken public USDT;
    MockToken public USDC;
    MockToken public USDX;

    Token public receiptToken;

    StoryPreDepositVault public storyPreDepositVault;

    address alice;
    address bob;

    address admin;

    function setUp() public {
        alice = address(0xA11CE);
        bob = address(0xB0B);

        admin = address(0xAD);

        receiptToken = new Token("Receipt Token", "RT", admin);

        USDT = new MockToken(6);
        USDC = new MockToken(6);
        USDX = new MockToken(6);

        USDT.mint(alice, 10000 * 1e6);
        USDT.mint(bob, 10000 * 1e6);
        USDC.mint(alice, 10000 * 1e6);
        USDC.mint(bob, 10000 * 1e6);
        USDX.mint(alice, 10000 * 1e6);

        address[] memory tokens = new address[](2);
        tokens[0] = address(USDT);
        tokens[1] = address(USDC);
        storyPreDepositVault = new StoryPreDepositVault(
            address(receiptToken),
            admin,
            tokens
        );

        vm.startPrank(admin);
        storyPreDepositVault.grantRole(
            storyPreDepositVault.ASSETS_MANAGEMENT_ROLE(),
            admin
        );
        storyPreDepositVault.grantRole(
            storyPreDepositVault.VAULT_OPERATOR_ROLE(),
            admin
        );
        receiptToken.grantRole(
            receiptToken.MINTER_ROLE(),
            address(storyPreDepositVault)
        );
        vm.stopPrank();
    }

    function test_basic() public {
        vm.startPrank(alice);
        USDT.approve(address(storyPreDepositVault), 10000 * 1e6);
        USDC.approve(address(storyPreDepositVault), 10000 * 1e6);
        storyPreDepositVault.deposit(address(USDT), 100 * 1e6, alice);
        assertEq(receiptToken.balanceOf(alice), 100 * 1e18);
        storyPreDepositVault.deposit(address(USDT), 100 * 1e6, bob);
        assertEq(receiptToken.balanceOf(bob), 100 * 1e18);
        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectRevert(InvalidAmount.selector);
        storyPreDepositVault.deposit(address(USDC), 1e5, alice);
        USDT.approve(address(storyPreDepositVault), 10000 * 1e6);
        USDC.approve(address(storyPreDepositVault), 10000 * 1e6);
        storyPreDepositVault.deposit(address(USDC), 10000 * 1e6, bob);
        assertEq(receiptToken.balanceOf(bob), 10100 * 1e18);
        vm.stopPrank();

        vm.startPrank(admin);
        storyPreDepositVault.setMinDeposit(10 * 1e6);
        storyPreDepositVault.setMaxDeposit(10000 * 1e6);
        storyPreDepositVault.setCap(15000 * 1e6);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(InvalidAmount.selector);
        storyPreDepositVault.deposit(address(USDC), 10000 * 1e6, alice);
        vm.expectRevert(ExceedCap.selector);
        storyPreDepositVault.deposit(address(USDC), 5000 * 1e6, alice);
        vm.expectRevert(UnsupportedToken.selector);
        storyPreDepositVault.deposit(address(USDX), 100 * 1e6, alice);
        vm.stopPrank();

        vm.startPrank(admin);
        storyPreDepositVault.setDepositPause(address(USDC), true);
        vm.stopPrank();

        vm.startPrank(alice);
        vm.expectRevert(Paused.selector);
        storyPreDepositVault.deposit(address(USDC), 100 * 1e6, alice);
        vm.stopPrank();

        vm.startPrank(admin);
        storyPreDepositVault.withdrawTokens(address(USDC), 500 * 1e6);
        assertEq(USDC.balanceOf(admin), 500 * 1e6);

        vm.stopPrank();
    }
}
