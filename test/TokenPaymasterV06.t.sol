// SPDX-License-Identifier:MIT
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import "account-abstraction-v6/samples/SimpleAccountFactory.sol";
import "account-abstraction-v6/core/EntryPoint.sol";
import "account-abstraction-v6/samples/SimpleAccount.sol";
import "account-abstraction-v6/interfaces/UserOperation.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../utils/PaymasterFactoryV06.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract TestTokenPaymasterV06 is Test {
    TokenPaymaster paymaster;
    SimpleAccountFactory accountfactory;
    EntryPoint entryPoint;
    SimpleAccount account;
    PaymasterFactoryV06 paymasterFactory;

    address payable beneficiary;
    address payable bundler;
    address paymasterFactoryOwner;
    address paymasterOwner;
    address user;
    uint256 userKey;
    address receiver;

    function setUp() external {
        beneficiary = payable(makeAddr("beneficiary"));
        bundler = payable(makeAddr("bundler"));
        (user, userKey) = makeAddrAndKey("user");
        bundler = payable(makeAddr("bundler"));
        paymasterFactoryOwner = makeAddr("paymasterFactoryOwner");
        receiver = makeAddr("receiver");

        entryPoint = new EntryPoint();
        accountfactory = new SimpleAccountFactory(entryPoint);
        account = accountfactory.createAccount(user, 0);

        vm.startPrank(paymasterFactoryOwner);
        paymasterFactory = new PaymasterFactoryV06();

        // TokenPaymasterv06 만을 위한 배포 코드
        address _paymaster = paymasterFactory.deployPaymasterV06(
            address(accountfactory),
            "TestERC20",
            IEntryPoint(address(entryPoint)),
            0
        );
        // 여기를 사용자 interface로 바꿔야함
        paymaster = TokenPaymaster(_paymaster);
        paymasterOwner = paymaster.owner();
        vm.stopPrank();
    }

    function testGetFundInValidation() external {
        uint256 initBalance = 1e10;
        vm.startPrank(paymasterOwner);
        paymaster.mintTokens(user, initBalance);
        vm.stopPrank();

        vm.startPrank(user);
        paymaster.approve(address(paymaster), type(uint256).max);
        vm.stopPrank();

        uint256 costOfPostop = paymaster.COST_OF_POST();
        UserOperation memory userOp = fillUserOp(
            user,
            userKey,
            address(0),
            0,
            "",
            address(paymaster),
            50000,
            costOfPostop + 1
        );

        vm.startPrank(address(entryPoint));
        bytes memory context;
        uint256 validationData;
        (context, validationData) = paymaster.validatePaymasterUserOp(
            userOp,
            keccak256(abi.encode(userOp)),
            1e8
        );
        vm.stopPrank();

        uint256 balance = paymaster.balanceOf(address(user));
        console.log(balance, initBalance);
        assert(initBalance > balance);
    }

    function testAfterBalances() external {
        vm.deal(paymasterOwner, 10e18);
        vm.startPrank(paymasterOwner);
        entryPoint.depositTo{value: 10e18}(address(paymaster));
        vm.stopPrank();

        uint256 initBalance = 10e18;

        vm.deal(user, 2e18);
        SimpleAccount userAccount = accountfactory.createAccount(user, 0);
        vm.stopPrank();

        vm.startPrank(paymasterOwner);
        paymaster.mintTokens(address(userAccount), initBalance);
        vm.stopPrank();

        vm.startPrank(address(userAccount));
        paymaster.approve(address(paymaster), initBalance);
        vm.stopPrank();

        // generate userOp, dummy userOp
        uint256 costOfPostop = paymaster.COST_OF_POST();
        UserOperation memory userOp = fillUserOp(
            address(userAccount),
            userKey,
            address(0),
            0,
            "",
            address(paymaster),
            50000,
            costOfPostop + 20000 // == 60000 is pass value
        );

        UserOperation[] memory ops = new UserOperation[](1);
        ops[0] = userOp;

        vm.deal(bundler, 10e18);

        vm.startPrank(bundler);
        entryPoint.handleOps(ops, beneficiary);

        UserOperation memory userOp2 = fillUserOp(
            address(userAccount),
            userKey,
            receiver,
            1e18,
            "",
            address(paymaster),
            50000,
            costOfPostop * 10
        );
        ops[0] = userOp2;
        uint256 gas1 = paymaster.balanceOf(address(userAccount));
        entryPoint.handleOps(ops, beneficiary);
        uint256 gas2 = paymaster.balanceOf(address(userAccount));

        uint256 useGas1 = gas1 - gas2;

        UserOperation memory userOp3 = fillUserOp(
            address(userAccount),
            userKey,
            receiver,
            1e18,
            "",
            address(paymaster),
            5000000, // *= 100 from userOp 2
            costOfPostop * 10
        );

        ops[0] = userOp3;
        entryPoint.handleOps(ops, beneficiary);
        uint256 gas3 = paymaster.balanceOf(address(userAccount));

        uint256 useGas2 = gas2 - gas3;
        vm.stopPrank();

        uint256 balance = paymaster.balanceOf(address(userAccount));
        assert(initBalance > balance);

        assertEq(useGas1, useGas2);
    }

    function testRefillFund() external {
        uint256 initBalance = 10e18;

        vm.startPrank(paymasterOwner);
        paymaster.mintTokens(address(user), initBalance);
        vm.stopPrank();

        vm.startPrank(address(user));
        paymaster.approve(address(paymaster), initBalance);
        vm.stopPrank();

        vm.startPrank(address(entryPoint));

        bytes memory context = abi.encode(address(user));
        uint256 actualGasCost = 1e10;

        uint256 initPaymasterBalance = paymaster.balanceOf(address(paymaster));
        paymaster.postOp(
            IPaymaster.PostOpMode.postOpReverted,
            context,
            actualGasCost
        );

        assert(initPaymasterBalance < paymaster.balanceOf(address(paymaster)));
        vm.stopPrank();
    }

    function signUserOp(
        UserOperation memory op,
        uint256 _key
    ) public view returns (bytes memory signature) {
        bytes32 hash = entryPoint.getUserOpHash(op);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            _key,
            ECDSA.toEthSignedMessageHash(hash)
        );
        signature = abi.encodePacked(r, s, v);
    }

    function check(address userAccount) public view {
        console.log("bundler balance :", bundler.balance);
        console.log("paymaster balance :", address(paymaster).balance);
        console.log("user balance :", user.balance);
        console.log(
            "paymaster's deposit to EP :",
            entryPoint.balanceOf(address(paymaster))
        );
        console.log(
            "userAccount token :",
            paymaster.balanceOf(address(userAccount))
        );
        console.log("beneficiary balance :", beneficiary.balance);
        console.log("");
    }

    function fillUserOp(
        address _sender,
        uint256 _key,
        address _to,
        uint256 _value,
        bytes memory _data,
        address _paymaster,
        uint256 _validationGas,
        uint256 _postOpGas
    ) public view returns (UserOperation memory op) {
        op.sender = address(_sender);
        op.nonce = entryPoint.getNonce(address(_sender), 0);
        if (_to == address(0)) {
            op.callData = "";
        } else {
            op.callData = abi.encodeWithSelector(
                SimpleAccount.execute.selector,
                _to,
                _value,
                _data
            );
        }
        op.callGasLimit = 10000;
        op.verificationGasLimit = 50000;
        op.preVerificationGas = 0;
        op.maxFeePerGas = 3000;
        op.maxPriorityFeePerGas = 1000;
        if (_paymaster == address(0)) {
            op.paymasterAndData = "";
        } else {
            op.paymasterAndData = fillpaymasterAndData(
                _paymaster,
                _validationGas,
                _postOpGas
            );
        }
        op.signature = signUserOp(op, _key);
        return op;
    }

    function fillpaymasterAndData(
        address _paymaster,
        uint256 _validationGas,
        uint256 _postOpGas
    ) public view returns (bytes memory paymasterAndDataStatic) {
        paymasterAndDataStatic = abi.encodePacked(
            address(_paymaster),
            uint128(_validationGas), // validation gas
            uint128(_postOpGas), // postOp gas
            uint256(1e26) // clientSuppliedPrice
        );
    }
}
