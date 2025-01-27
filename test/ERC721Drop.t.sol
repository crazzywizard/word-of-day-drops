// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Test} from "forge-std/Test.sol";
import {IERC721AUpgradeable} from "erc721a-upgradeable/IERC721AUpgradeable.sol";

import {ERC721Drop} from "../src/ERC721Drop.sol";
import {ZoraFeeManager} from "../src/ZoraFeeManager.sol";
import {DummyMetadataRenderer} from "./utils/DummyMetadataRenderer.sol";
import {MockUser} from "./utils/MockUser.sol";
import {IOperatorFilterRegistry} from "../src/interfaces/IOperatorFilterRegistry.sol";
import {IMetadataRenderer} from "../src/interfaces/IMetadataRenderer.sol";
import {IERC721Drop} from "../src/interfaces/IERC721Drop.sol";
import {FactoryUpgradeGate} from "../src/FactoryUpgradeGate.sol";
import {ERC721DropProxy} from "../src/ERC721DropProxy.sol";
import {OperatorFilterRegistry} from "./filter/OperatorFilterRegistry.sol";
import {OperatorFilterRegistryErrorsAndEvents} from "./filter/OperatorFilterRegistryErrorsAndEvents.sol";
import {OwnedSubscriptionManager} from "../src/filter/OwnedSubscriptionManager.sol";


// contract TestEventEmitter {
//     function emitFundsWithdrawn(
//         address withdrawnBy,
//         address withdrawnTo,
//         uint256 amount,
//         address feeRecipient,
//         uint256 feeAmount
//     ) external {
//         emit FundsWithdrawn(
//             withdrawnBy,
//             withdrawnTo,
//             amount,
//             feeRecipient,
//             feeAmount
//         );
//     }
// }

contract ERC721DropTest is Test {
    /// @notice Event emitted when the funds are withdrawn from the minting contract
    /// @param withdrawnBy address that issued the withdraw
    /// @param withdrawnTo address that the funds were withdrawn to
    /// @param amount amount that was withdrawn
    /// @param feeRecipient user getting withdraw fee (if any)
    /// @param feeAmount amount of the fee getting sent (if any)
    event FundsWithdrawn(
        address indexed withdrawnBy,
        address indexed withdrawnTo,
        uint256 amount,
        address feeRecipient,
        uint256 feeAmount
    );

    ERC721Drop zoraNFTBase;
    MockUser mockUser;
    DummyMetadataRenderer public dummyRenderer = new DummyMetadataRenderer();
    ZoraFeeManager public feeManager;
    FactoryUpgradeGate public factoryUpgradeGate;
    address public constant DEFAULT_OWNER_ADDRESS = address(0x23499);
    address payable public constant DEFAULT_FUNDS_RECIPIENT_ADDRESS =
        payable(address(0x21303));
    address payable public constant DEFAULT_ZORA_DAO_ADDRESS =
        payable(address(0x999));
    address public constant UPGRADE_GATE_ADMIN_ADDRESS = address(0x942924224);
    address public constant mediaContract = address(0x123456);
    address public impl;
    address public ownedSubscriptionManager;

    struct Configuration {
        IMetadataRenderer metadataRenderer;
        uint64 editionSize;
        uint16 royaltyBPS;
        address payable fundsRecipient;
    }

    modifier setupZoraNFTBase(uint64 editionSize) {
        bytes[] memory setupCalls = new bytes[](0);
        zoraNFTBase.initialize({
            _contractName: "Test NFT",
            _contractSymbol: "TNFT",
            _initialOwner: DEFAULT_OWNER_ADDRESS,
            _fundsRecipient: payable(DEFAULT_FUNDS_RECIPIENT_ADDRESS),
            _editionSize: editionSize,
            _royaltyBPS: 800,
            _setupCalls: setupCalls,
            _metadataRenderer: dummyRenderer,
            _metadataRendererInit: ""
        });

        _;
    }

    function setUp() public {
        vm.prank(DEFAULT_ZORA_DAO_ADDRESS);
        feeManager = new ZoraFeeManager(500, DEFAULT_ZORA_DAO_ADDRESS);
        factoryUpgradeGate = new FactoryUpgradeGate(UPGRADE_GATE_ADMIN_ADDRESS);
        vm.etch(
            address(0x000000000000AAeB6D7670E522A718067333cd4E),
            address(new OperatorFilterRegistry()).code
        );
        ownedSubscriptionManager = address(
            new OwnedSubscriptionManager(address(0x123456))
        );

        vm.prank(DEFAULT_ZORA_DAO_ADDRESS);
        impl = address(
            new ERC721Drop(
                feeManager,
                address(0x1234),
                factoryUpgradeGate,
                address(0x0)
            )
        );
        address payable newDrop = payable(
            address(new ERC721DropProxy(impl, ""))
        );
        zoraNFTBase = ERC721Drop(newDrop);
    }

    modifier factoryWithSubscriptionAddress(address subscriptionAddress) {
        vm.prank(DEFAULT_ZORA_DAO_ADDRESS);
        impl = address(
            new ERC721Drop(
                feeManager,
                address(0x1234),
                factoryUpgradeGate,
                address(subscriptionAddress)
            )
        );
        address payable newDrop = payable(
            address(new ERC721DropProxy(impl, ""))
        );
        zoraNFTBase = ERC721Drop(newDrop);

        _;
    }

    function test_Init() public setupZoraNFTBase(10) {
        require(
            zoraNFTBase.owner() == DEFAULT_OWNER_ADDRESS,
            "Default owner set wrong"
        );

        (
            IMetadataRenderer renderer,
            uint64 editionSize,
            uint16 royaltyBPS,
            address payable fundsRecipient
        ) = zoraNFTBase.config();

        require(address(renderer) == address(dummyRenderer));
        require(editionSize == 10, "EditionSize is wrong");
        require(royaltyBPS == 800, "RoyaltyBPS is wrong");
        require(
            fundsRecipient == payable(DEFAULT_FUNDS_RECIPIENT_ADDRESS),
            "FundsRecipient is wrong"
        );

        string memory name = zoraNFTBase.name();
        string memory symbol = zoraNFTBase.symbol();
        require(keccak256(bytes(name)) == keccak256(bytes("Test NFT")));
        require(keccak256(bytes(symbol)) == keccak256(bytes("TNFT")));

        vm.expectRevert("Initializable: contract is already initialized");
        bytes[] memory setupCalls = new bytes[](0);
        zoraNFTBase.initialize({
            _contractName: "Test NFT",
            _contractSymbol: "TNFT",
            _initialOwner: DEFAULT_OWNER_ADDRESS,
            _fundsRecipient: payable(DEFAULT_FUNDS_RECIPIENT_ADDRESS),
            _editionSize: 10,
            _royaltyBPS: 800,
            _setupCalls: setupCalls,
            _metadataRenderer: dummyRenderer,
            _metadataRendererInit: ""
        });
    }

    function test_SubscriptionEnabled()
        public
        factoryWithSubscriptionAddress(ownedSubscriptionManager)
        setupZoraNFTBase(10)
    {
        IOperatorFilterRegistry operatorFilterRegistry = IOperatorFilterRegistry(
                0x000000000000AAeB6D7670E522A718067333cd4E
            );
        vm.startPrank(address(0x123456));
        operatorFilterRegistry.updateOperator(
            ownedSubscriptionManager,
            address(0xcafeea3),
            true
        );
        vm.stopPrank();
        vm.startPrank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.manageMarketFilterDAOSubscription(true);
        zoraNFTBase.adminMint(DEFAULT_OWNER_ADDRESS, 10);
        zoraNFTBase.setApprovalForAll(address(0xcafeea3), true);
        vm.stopPrank();
        vm.prank(address(0xcafeea3));
        vm.expectRevert(
            abi.encodeWithSelector(
                OperatorFilterRegistryErrorsAndEvents.AddressFiltered.selector,
                address(0xcafeea3)
            )
        );
        zoraNFTBase.transferFrom(DEFAULT_OWNER_ADDRESS, address(0x123456), 1);
        vm.prank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.manageMarketFilterDAOSubscription(false);
        vm.prank(address(0xcafeea3));
        zoraNFTBase.transferFrom(DEFAULT_OWNER_ADDRESS, address(0x123456), 1);
    }

    function test_OnlyAdminEnableSubscription()
        public
        factoryWithSubscriptionAddress(ownedSubscriptionManager)
        setupZoraNFTBase(10)
    {
        vm.startPrank(address(0xcafecafe));
        vm.expectRevert(IERC721Drop.Access_OnlyAdmin.selector);
        zoraNFTBase.manageMarketFilterDAOSubscription(true);
        vm.stopPrank();
    }

    function test_ProxySubscriptionAccessOnlyAdmin()
        public
        factoryWithSubscriptionAddress(ownedSubscriptionManager)
        setupZoraNFTBase(10)
    {
        bytes memory baseCall = abi.encodeWithSelector(
            IOperatorFilterRegistry.register.selector,
            address(zoraNFTBase)
        );
        vm.startPrank(address(0xcafecafe));
        vm.expectRevert(IERC721Drop.Access_OnlyAdmin.selector);
        zoraNFTBase.updateMarketFilterSettings(baseCall);
        vm.stopPrank();
    }

    function test_ProxySubscriptionAccess()
        public
        factoryWithSubscriptionAddress(ownedSubscriptionManager)
        setupZoraNFTBase(10)
    {
        vm.startPrank(address(DEFAULT_OWNER_ADDRESS));
        bytes memory baseCall = abi.encodeWithSelector(
            IOperatorFilterRegistry.register.selector,
            address(zoraNFTBase)
        );
        zoraNFTBase.updateMarketFilterSettings(baseCall);
        vm.stopPrank();
    }

    function test_Purchase(uint64 amount) public setupZoraNFTBase(10) {
        vm.prank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.setSaleConfiguration({
            publicSaleStart: 0,
            publicSaleEnd: type(uint64).max,
            presaleStart: 0,
            presaleEnd: 0,
            publicSalePrice: amount,
            maxSalePurchasePerAddress: 2,
            presaleMerkleRoot: bytes32(0)
        });

        vm.deal(address(456), uint256(amount) * 2);
        vm.prank(address(456));
        zoraNFTBase.purchase{value: amount}(1);

        assertEq(zoraNFTBase.saleDetails().maxSupply, 10);
        assertEq(zoraNFTBase.saleDetails().totalMinted, 1);
        require(
            zoraNFTBase.ownerOf(1) == address(456),
            "owner is wrong for new minted token"
        );
        assertEq(address(zoraNFTBase).balance, amount);
    }

    function test_UpgradeApproved() public setupZoraNFTBase(10) {
        address newImpl = address(
            new ERC721Drop(
                ZoraFeeManager(address(0xadadad)),
                address(0x3333),
                factoryUpgradeGate,
                address(0x0)
            )
        );

        address[] memory lastImpls = new address[](1);
        lastImpls[0] = impl;
        vm.prank(UPGRADE_GATE_ADMIN_ADDRESS);
        factoryUpgradeGate.registerNewUpgradePath({
            _newImpl: newImpl,
            _supportedPrevImpls: lastImpls
        });
        vm.prank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.upgradeTo(newImpl);
        assertEq(address(zoraNFTBase.zoraFeeManager()), address(0xadadad));
    }

    function test_PurchaseTime() public setupZoraNFTBase(10) {
        vm.prank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.setSaleConfiguration({
            publicSaleStart: 0,
            publicSaleEnd: 0,
            presaleStart: 0,
            presaleEnd: 0,
            publicSalePrice: 0.1 ether,
            maxSalePurchasePerAddress: 2,
            presaleMerkleRoot: bytes32(0)
        });

        assertTrue(!zoraNFTBase.saleDetails().publicSaleActive);

        vm.deal(address(456), 1 ether);
        vm.prank(address(456));
        vm.expectRevert(IERC721Drop.Sale_Inactive.selector);
        zoraNFTBase.purchase{value: 0.1 ether}(1);

        assertEq(zoraNFTBase.saleDetails().maxSupply, 10);
        assertEq(zoraNFTBase.saleDetails().totalMinted, 0);

        vm.prank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.setSaleConfiguration({
            publicSaleStart: 9 * 3600,
            publicSaleEnd: 11 * 3600,
            presaleStart: 0,
            presaleEnd: 0,
            maxSalePurchasePerAddress: 20,
            publicSalePrice: 0.1 ether,
            presaleMerkleRoot: bytes32(0)
        });

        assertTrue(!zoraNFTBase.saleDetails().publicSaleActive);
        // jan 1st 1980
        vm.warp(10 * 3600);
        assertTrue(zoraNFTBase.saleDetails().publicSaleActive);
        assertTrue(!zoraNFTBase.saleDetails().presaleActive);

        vm.prank(address(456));
        zoraNFTBase.purchase{value: 0.1 ether}(1);

        assertEq(zoraNFTBase.saleDetails().totalMinted, 1);
        assertEq(zoraNFTBase.ownerOf(1), address(456));
    }

    function test_Mint() public setupZoraNFTBase(10) {
        vm.prank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.adminMint(DEFAULT_OWNER_ADDRESS, 1);
        assertEq(zoraNFTBase.saleDetails().maxSupply, 10);
        assertEq(zoraNFTBase.saleDetails().totalMinted, 1);
        require(
            zoraNFTBase.ownerOf(1) == DEFAULT_OWNER_ADDRESS,
            "Owner is wrong for new minted token"
        );
    }

    function test_MintMulticall() public setupZoraNFTBase(10) {
        vm.startPrank(DEFAULT_OWNER_ADDRESS);
        bytes[] memory calls = new bytes[](3);
        calls[0] = abi.encodeWithSelector(
            IERC721Drop.adminMint.selector,
            DEFAULT_OWNER_ADDRESS,
            5 
        );
        calls[1] = abi.encodeWithSelector(
            IERC721Drop.adminMint.selector,
            address(0x123),
            3
        );
        calls[2] = abi.encodeWithSelector(
            IERC721Drop.saleDetails.selector
        );
        bytes[] memory results = zoraNFTBase.multicall(calls);

        (bool saleActive, bool presaleActive, uint256 publicSalePrice, , , , , , , ,) = abi.decode(results[2], (bool, bool, uint256, uint64, uint64, uint64, uint64, bytes32, uint256, uint256, uint256));
        assertTrue(!saleActive);
        assertTrue(!presaleActive);
        assertEq(publicSalePrice, 0);
        (uint256 firstMintedId) = abi.decode(results[0], (uint256));
        (uint256 secondMintedId) = abi.decode(results[1], (uint256));
        assertEq(firstMintedId, 5);
        assertEq(secondMintedId, 8);
    }

    function test_UpdatePriceMulticall() public setupZoraNFTBase(10) {
       vm.startPrank(DEFAULT_OWNER_ADDRESS);
        bytes[] memory calls = new bytes[](3);
        calls[0] = abi.encodeWithSelector(
            IERC721Drop.setSaleConfiguration.selector,
            0.1 ether,
            2,
            0,
            type(uint64).max,
            0,
            0,
            bytes32(0)
        );
        calls[1] = abi.encodeWithSelector(
            IERC721Drop.adminMint.selector,
            address(0x123),
            3
        );
        calls[2] = abi.encodeWithSelector(
            IERC721Drop.adminMint.selector,
            address(0x123),
            3
        );
        bytes[] memory results = zoraNFTBase.multicall(calls);

        IERC721Drop.SaleDetails memory saleDetails = zoraNFTBase.saleDetails();

        assertTrue(saleDetails.publicSaleActive);
        assertTrue(!saleDetails.presaleActive);
        assertEq(saleDetails.publicSalePrice, 0.1 ether);
        (uint256 firstMintedId) = abi.decode(results[1], (uint256));
        (uint256 secondMintedId) = abi.decode(results[2], (uint256));
        assertEq(firstMintedId, 3);
        assertEq(secondMintedId, 6); 
        vm.stopPrank();
        vm.startPrank(address(0x111));
        vm.deal(address(0x111), 0.3 ether);
        zoraNFTBase.purchase{value: 0.2 ether}(2);
        assertEq(zoraNFTBase.balanceOf(address(0x111)), 2);
        vm.stopPrank();
    }

    function test_MintWrongValue() public setupZoraNFTBase(10) {
        vm.deal(address(456), 1 ether);
        vm.prank(address(456));
        vm.expectRevert(IERC721Drop.Sale_Inactive.selector);
        zoraNFTBase.purchase{value: 0.12 ether}(1);
        vm.prank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.setSaleConfiguration({
            publicSaleStart: 0,
            publicSaleEnd: type(uint64).max,
            presaleStart: 0,
            presaleEnd: 0,
            publicSalePrice: 0.15 ether,
            maxSalePurchasePerAddress: 2,
            presaleMerkleRoot: bytes32(0)
        });
        vm.prank(address(456));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC721Drop.Purchase_WrongPrice.selector,
                0.15 ether
            )
        );
        zoraNFTBase.purchase{value: 0.12 ether}(1);
    }

    function test_Withdraw(uint128 amount) public setupZoraNFTBase(10) {
        vm.assume(amount > 0.01 ether);
        vm.deal(address(zoraNFTBase), amount);
        vm.prank(DEFAULT_OWNER_ADDRESS);
        vm.expectEmit(true, true, true, true);
        uint256 leftoverFunds = amount - (amount * 1) / 20;
        emit FundsWithdrawn(
            DEFAULT_OWNER_ADDRESS,
            DEFAULT_FUNDS_RECIPIENT_ADDRESS,
            leftoverFunds,
            DEFAULT_ZORA_DAO_ADDRESS,
            (amount * 1) / 20
        );
        zoraNFTBase.withdraw();

        (, uint256 feeBps) = feeManager.getZORAWithdrawFeesBPS(
            address(zoraNFTBase)
        );
        assertEq(feeBps, 500);

        assertTrue(
            DEFAULT_ZORA_DAO_ADDRESS.balance <
                ((uint256(amount) * 1_000 * 5) / 100000) + 2 ||
                DEFAULT_ZORA_DAO_ADDRESS.balance >
                ((uint256(amount) * 1_000 * 5) / 100000) + 2
        );
        assertTrue(
            DEFAULT_FUNDS_RECIPIENT_ADDRESS.balance >
                ((uint256(amount) * 1_000 * 95) / 100000) - 2 ||
                DEFAULT_FUNDS_RECIPIENT_ADDRESS.balance <
                ((uint256(amount) * 1_000 * 95) / 100000) + 2
        );
    }

    function test_MintLimit(uint8 limit) public setupZoraNFTBase(5000) {
        // set limit to speed up tests
        vm.assume(limit > 0 && limit < 50);
        vm.prank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.setSaleConfiguration({
            publicSaleStart: 0,
            publicSaleEnd: type(uint64).max,
            presaleStart: 0,
            presaleEnd: 0,
            publicSalePrice: 0.1 ether,
            maxSalePurchasePerAddress: limit,
            presaleMerkleRoot: bytes32(0)
        });
        vm.deal(address(456), 1_000_000 ether);
        vm.prank(address(456));
        zoraNFTBase.purchase{value: 0.1 ether * uint256(limit)}(limit);

        assertEq(zoraNFTBase.saleDetails().totalMinted, limit);

        vm.deal(address(444), 1_000_000 ether);
        vm.prank(address(444));
        vm.expectRevert(IERC721Drop.Purchase_TooManyForAddress.selector);
        zoraNFTBase.purchase{value: 0.1 ether * (uint256(limit) + 1)}(
            uint256(limit) + 1
        );

        assertEq(zoraNFTBase.saleDetails().totalMinted, limit);
    }

    function testSetSalesConfiguration() public setupZoraNFTBase(10) {
        vm.prank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.setSaleConfiguration({
            publicSaleStart: 0,
            publicSaleEnd: type(uint64).max,
            presaleStart: 0,
            presaleEnd: 100,
            publicSalePrice: 0.1 ether,
            maxSalePurchasePerAddress: 10,
            presaleMerkleRoot: bytes32(0)
        });

        (, , , , , uint64 presaleEndLookup, ) = zoraNFTBase.salesConfig();
        assertEq(presaleEndLookup, 100);

        address SALES_MANAGER_ADDR = address(0x11002);
        vm.startPrank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.grantRole(
            zoraNFTBase.SALES_MANAGER_ROLE(),
            SALES_MANAGER_ADDR
        );
        vm.stopPrank();
        vm.prank(SALES_MANAGER_ADDR);
        zoraNFTBase.setSaleConfiguration({
            publicSaleStart: 0,
            publicSaleEnd: type(uint64).max,
            presaleStart: 100,
            presaleEnd: 0,
            publicSalePrice: 0.1 ether,
            maxSalePurchasePerAddress: 1003,
            presaleMerkleRoot: bytes32(0)
        });

        (
            ,
            ,
            ,
            ,
            uint64 presaleStartLookup2,
            uint64 presaleEndLookup2,

        ) = zoraNFTBase.salesConfig();
        assertEq(presaleEndLookup2, 0);
        assertEq(presaleStartLookup2, 100);
    }

    function test_GlobalLimit(uint16 limit)
        public
        setupZoraNFTBase(uint64(limit))
    {
        vm.assume(limit > 0);
        vm.startPrank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.adminMint(DEFAULT_OWNER_ADDRESS, limit);
        vm.expectRevert(IERC721Drop.Mint_SoldOut.selector);
        zoraNFTBase.adminMint(DEFAULT_OWNER_ADDRESS, 1);
    }

    function test_WithdrawNotAllowed() public setupZoraNFTBase(10) {
        vm.expectRevert(IERC721Drop.Access_WithdrawNotAllowed.selector);
        zoraNFTBase.withdraw();
    }

    function test_InvalidFinalizeOpenEdition() public setupZoraNFTBase(5) {
        vm.prank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.setSaleConfiguration({
            publicSaleStart: 0,
            publicSaleEnd: type(uint64).max,
            presaleStart: 0,
            presaleEnd: 0,
            publicSalePrice: 0.2 ether,
            presaleMerkleRoot: bytes32(0),
            maxSalePurchasePerAddress: 5
        });
        zoraNFTBase.purchase{value: 0.6 ether}(3);
        vm.prank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.adminMint(address(0x1234), 2);
        vm.prank(DEFAULT_OWNER_ADDRESS);
        vm.expectRevert(
            IERC721Drop.Admin_UnableToFinalizeNotOpenEdition.selector
        );
        zoraNFTBase.finalizeOpenEdition();
    }

    function test_ValidFinalizeOpenEdition()
        public
        setupZoraNFTBase(type(uint64).max)
    {
        vm.prank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.setSaleConfiguration({
            publicSaleStart: 0,
            publicSaleEnd: type(uint64).max,
            presaleStart: 0,
            presaleEnd: 0,
            publicSalePrice: 0.2 ether,
            presaleMerkleRoot: bytes32(0),
            maxSalePurchasePerAddress: 10
        });
        zoraNFTBase.purchase{value: 0.6 ether}(3);
        vm.prank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.adminMint(address(0x1234), 2);
        vm.prank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.finalizeOpenEdition();
        vm.expectRevert(IERC721Drop.Mint_SoldOut.selector);
        vm.prank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.adminMint(address(0x1234), 2);
        vm.expectRevert(IERC721Drop.Mint_SoldOut.selector);
        zoraNFTBase.purchase{value: 0.6 ether}(3);
    }

    function test_AdminMint() public setupZoraNFTBase(10) {
        address minter = address(0x32402);
        vm.startPrank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.adminMint(DEFAULT_OWNER_ADDRESS, 1);
        require(
            zoraNFTBase.balanceOf(DEFAULT_OWNER_ADDRESS) == 1,
            "Wrong balance"
        );
        zoraNFTBase.grantRole(zoraNFTBase.MINTER_ROLE(), minter);
        vm.stopPrank();
        vm.prank(minter);
        zoraNFTBase.adminMint(minter, 1);
        require(zoraNFTBase.balanceOf(minter) == 1, "Wrong balance");
        assertEq(zoraNFTBase.saleDetails().totalMinted, 2);
    }

    function test_EditionSizeZero() public setupZoraNFTBase(0) {
        address minter = address(0x32402);
        vm.startPrank(DEFAULT_OWNER_ADDRESS);
        vm.expectRevert(IERC721Drop.Mint_SoldOut.selector);
        zoraNFTBase.adminMint(DEFAULT_OWNER_ADDRESS, 1);
        zoraNFTBase.grantRole(zoraNFTBase.MINTER_ROLE(), minter);
        vm.stopPrank();
        vm.prank(minter);
        vm.expectRevert(IERC721Drop.Mint_SoldOut.selector);
        zoraNFTBase.adminMint(minter, 1);

        vm.prank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.setSaleConfiguration({
            publicSaleStart: 0,
            publicSaleEnd: type(uint64).max,
            presaleStart: 0,
            presaleEnd: 0,
            publicSalePrice: 1,
            maxSalePurchasePerAddress: 2,
            presaleMerkleRoot: bytes32(0)
        });

        vm.deal(address(456), uint256(1) * 2);
        vm.prank(address(456));
        vm.expectRevert(IERC721Drop.Mint_SoldOut.selector);
        zoraNFTBase.purchase{value: 1}(1);
    }

    // test Admin airdrop
    function test_AdminMintAirdrop() public setupZoraNFTBase(1000) {
        vm.startPrank(DEFAULT_OWNER_ADDRESS);
        address[] memory toMint = new address[](4);
        toMint[0] = address(0x10);
        toMint[1] = address(0x11);
        toMint[2] = address(0x12);
        toMint[3] = address(0x13);
        zoraNFTBase.adminMintAirdrop(toMint);
        assertEq(zoraNFTBase.saleDetails().totalMinted, 4);
        assertEq(zoraNFTBase.balanceOf(address(0x10)), 1);
        assertEq(zoraNFTBase.balanceOf(address(0x11)), 1);
        assertEq(zoraNFTBase.balanceOf(address(0x12)), 1);
        assertEq(zoraNFTBase.balanceOf(address(0x13)), 1);
    }

    function test_AdminMintAirdropFails() public setupZoraNFTBase(1000) {
        vm.startPrank(address(0x10));
        address[] memory toMint = new address[](4);
        toMint[0] = address(0x10);
        toMint[1] = address(0x11);
        toMint[2] = address(0x12);
        toMint[3] = address(0x13);
        bytes32 minterRole = zoraNFTBase.MINTER_ROLE();
        vm.expectRevert(
            abi.encodeWithSignature(
                "Access_MissingRoleOrAdmin(bytes32)",
                minterRole
            )
        );
        zoraNFTBase.adminMintAirdrop(toMint);
    }

    // test admin mint non-admin permissions
    function test_AdminMintBatch() public setupZoraNFTBase(1000) {
        vm.startPrank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.adminMint(DEFAULT_OWNER_ADDRESS, 100);
        assertEq(zoraNFTBase.saleDetails().totalMinted, 100);
        assertEq(zoraNFTBase.balanceOf(DEFAULT_OWNER_ADDRESS), 100);
    }

    function test_AdminMintBatchFails() public setupZoraNFTBase(1000) {
        vm.startPrank(address(0x10));
        bytes32 role = zoraNFTBase.MINTER_ROLE();
        vm.expectRevert(
            abi.encodeWithSignature("Access_MissingRoleOrAdmin(bytes32)", role)
        );
        zoraNFTBase.adminMint(address(0x10), 100);
    }

    function test_Burn() public setupZoraNFTBase(10) {
        address minter = address(0x32402);
        vm.startPrank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.grantRole(zoraNFTBase.MINTER_ROLE(), minter);
        vm.stopPrank();
        vm.startPrank(minter);
        address[] memory airdrop = new address[](1);
        airdrop[0] = minter;
        zoraNFTBase.adminMintAirdrop(airdrop);
        zoraNFTBase.burn(1);
        vm.stopPrank();
    }

    function test_BurnNonOwner() public setupZoraNFTBase(10) {
        address minter = address(0x32402);
        vm.startPrank(DEFAULT_OWNER_ADDRESS);
        zoraNFTBase.grantRole(zoraNFTBase.MINTER_ROLE(), minter);
        vm.stopPrank();
        vm.startPrank(minter);
        address[] memory airdrop = new address[](1);
        airdrop[0] = minter;
        zoraNFTBase.adminMintAirdrop(airdrop);
        vm.stopPrank();

        vm.prank(address(1));
        vm.expectRevert(
            IERC721AUpgradeable.TransferCallerNotOwnerNorApproved.selector
        );
        zoraNFTBase.burn(1);
    }

    // Add test burn failure state for users that don't own the token

    function test_EIP165() public view {
        require(zoraNFTBase.supportsInterface(0x01ffc9a7), "supports 165");
        require(zoraNFTBase.supportsInterface(0x80ac58cd), "supports 721");
        require(
            zoraNFTBase.supportsInterface(0x5b5e139f),
            "supports 721-metdata"
        );
        require(zoraNFTBase.supportsInterface(0x2a55205a), "supports 2981");
        require(
            !zoraNFTBase.supportsInterface(0x0000000),
            "doesnt allow non-interface"
        );
    }
}
