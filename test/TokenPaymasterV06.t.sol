// SPDX-License-Identifier:MIT
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import "account-abstraction-v6/samples/SimpleAccountFactory.sol";
import "account-abstraction-v6/core/EntryPoint.sol";
import "account-abstraction-v6/samples/SimpleAccount.sol";
import "account-abstraction-v6/interfaces/UserOperation.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../utils/PaymasterFactoryV06.sol";

contract TestTokenPaymasterV06 is Test {
    TokenPaymaster paymaster;
    SimpleAccountFactory accountfactory;
    EntryPoint entryPoint;
    SimpleAccount account;
    ERC20 token;
    PaymasterFactoryV06 paymasterFactory;

    address payable beneficiary;
    address payable bundler;
    address paymasterOwner;
    address user;
    uint256 userKey;

    function setUp() external {
        beneficiary = payable(makeAddr("beneficiary"));
        bundler = payable(makeAddr("bundler"));
        paymasterOwner = makeAddr("paymasterOwner");
        (user, userKey) = makeAddrAndKey("user");
        bundler = payable(makeAddr("bundler"));

        entryPoint = new EntryPoint();
        accountfactory = new SimpleAccountFactory(entryPoint);
        account = accountfactory.createAccount(user, 0);

        token = new ERC20("TestToken", "TST");

        vm.startPrank(paymasterOwner);
        paymasterFactory = new PaymasterFactoryV06();

        address _paymaster = paymasterFactory.deployPaymasterV06(
            address(accountfactory),
            "TokenpaymasterV06",
            IEntryPoint(address(entryPoint)),
            0
        );
        paymaster = TokenPaymaster(_paymaster);

        vm.stopPrank();
    }

    function test() external {}
}
