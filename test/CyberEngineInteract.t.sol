// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import "forge-std/Test.sol";
import { MockEngine } from "./utils/MockEngine.sol";
import { TestAuthority } from "./utils/TestAuthority.sol";
import { RolesAuthority } from "../src/dependencies/solmate/RolesAuthority.sol";
import { Constants } from "../src/libraries/Constants.sol";
import { IBoxNFT } from "../src/interfaces/IBoxNFT.sol";
import { IProfileNFT } from "../src/interfaces/IProfileNFT.sol";
import { ISubscribeNFT } from "../src/interfaces/ISubscribeNFT.sol";
import { DataTypes } from "../src/libraries/DataTypes.sol";
import { UpgradeableBeacon } from "../src/upgradeability/UpgradeableBeacon.sol";
import { Auth, Authority } from "../src/dependencies/solmate/Auth.sol";
import { SubscribeNFT } from "../src/SubscribeNFT.sol";
import { ProfileNFT } from "../src/ProfileNFT.sol";
import { ERC721 } from "../src/dependencies/solmate/ERC721.sol";
import { ICyberEngineEvents } from "../src/interfaces/ICyberEngineEvents.sol";

contract CyberEngineInteractTest is Test, ICyberEngineEvents {
    MockEngine internal engine;
    RolesAuthority internal authority;
    address internal profileAddress = address(0xA);
    address internal boxAddress = address(0xB);
    address internal subscribeBeacon;
    address internal gov = address(0xCCC);
    uint256 internal bobPk = 1;
    address internal bob = vm.addr(bobPk);
    uint256 internal profileId;
    address internal alice = address(0xA11CE);

    function setUp() public {
        authority = new TestAuthority(address(this));
        engine = new MockEngine();
        // Cannot use vm.mockCall on one address multiple times (1 for getter, 1 for setter); only used in test `testSubscribeDeployProxy`
        // profileAddress = address(new MockProfileGetterSetter());
        // Need beacon proxy to work, must set up fake beacon with fake impl contract
        bytes memory code = address(new ProfileNFT(address(engine))).code;
        vm.etch(profileAddress, code);

        address impl = address(
            new SubscribeNFT(address(engine), profileAddress)
        );
        subscribeBeacon = address(new UpgradeableBeacon(impl, address(engine)));
        engine.initialize(
            address(0),
            profileAddress,
            boxAddress,
            subscribeBeacon,
            authority
        );
        authority.setRoleCapability(
            Constants._ENGINE_GOV_ROLE,
            address(engine),
            Constants._SET_SIGNER,
            true
        );
        authority.setUserRole(gov, Constants._ENGINE_GOV_ROLE, true);
        vm.prank(gov);
        engine.setSigner(bob);

        // register "bob"
        string memory handle = "bob";
        uint256 deadline = 100;
        bytes32 digest = engine.hashTypedDataV4(
            keccak256(
                abi.encode(
                    Constants._REGISTER_TYPEHASH,
                    bob,
                    keccak256(bytes(handle)),
                    0,
                    deadline
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, digest);

        vm.mockCall(
            boxAddress,
            abi.encodeWithSelector(IBoxNFT.mint.selector, address(bob)),
            abi.encode(1)
        );

        vm.mockCall(
            profileAddress,
            abi.encodeWithSelector(
                IProfileNFT.createProfile.selector,
                address(bob),
                DataTypes.CreateProfileParams(handle, "", address(0))
            ),
            abi.encode(1)
        );

        assertEq(engine.nonces(bob), 0);
        profileId = engine.register{ value: Constants._INITIAL_FEE_TIER2 }(
            bob,
            handle,
            DataTypes.EIP712Signature(v, r, s, deadline)
        );
        assertEq(profileId, 1);

        assertEq(engine.nonces(bob), 1);
    }

    function testCannotSubscribeEmptyList() public {
        vm.expectRevert("No profile ids provided");
        uint256[] memory empty;
        bytes[] memory data;
        engine.subscribe(empty, data);
    }

    function testSubscribe() public {
        address subscribeProxy = address(0xC0DE);
        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        bytes[] memory datas = new bytes[](1);
        vm.mockCall(
            profileAddress,
            abi.encodeWithSelector(
                IProfileNFT.getSubscribeAddrAndMwByProfileId.selector,
                1
            ),
            abi.encode(address(subscribeProxy), address(0))
        );

        uint256 result = 100;
        vm.mockCall(
            subscribeProxy,
            abi.encodeWithSelector(ISubscribeNFT.mint.selector, address(this)),
            abi.encode(result)
        );
        uint256[] memory expected = new uint256[](1);
        expected[0] = result;

        vm.expectEmit(true, false, false, true);
        emit Subscribe(address(this), ids, datas);

        uint256[] memory called = engine.subscribe(ids, datas);
        assertEq(called.length, expected.length);
        assertEq(called[0], expected[0]);
    }

    function testSubscribeDeployProxy() public {
        address subscribeProxy = address(0xC0DE);
        uint256[] memory ids = new uint256[](1);
        ids[0] = 1;
        bytes[] memory datas = new bytes[](1);

        vm.mockCall(
            profileAddress,
            abi.encodeWithSelector(
                IProfileNFT.getSubscribeAddrAndMwByProfileId.selector,
                1
            ),
            abi.encode(address(0), address(0))
        );

        uint256 result = 100;

        // Assuming the newly deployed subscribe proxy is always at the same address;
        address proxy = address(0x9cC6334F1A7Bc20c9Dde91Db536E194865Af0067);
        vm.mockCall(
            proxy,
            abi.encodeWithSelector(ISubscribeNFT.mint.selector, address(this)),
            abi.encode(result)
        );

        // This is not used but kept for reference. MockCall cannot set on the same address
        // multiple times, so we used a custom contract `MockProfileGetterSetter`
        vm.mockCall(
            profileAddress,
            abi.encodeWithSelector(
                IProfileNFT.setSubscribeNFTAddress.selector,
                1,
                proxy
            ),
            abi.encode(address(0))
        );

        uint256[] memory expected = new uint256[](1);
        expected[0] = result;
        uint256[] memory called = engine.subscribe(ids, datas);
        assertEq(called.length, expected.length);
        assertEq(called[0], expected[0]);
    }

    // TODO: add test for subscribe to multiple profiles

    // TODO: use integration test instead of mock
    function testCannotSetOperatorIfNotOwner() public {
        vm.mockCall(
            profileAddress,
            abi.encodeWithSelector(ERC721.ownerOf.selector, profileId),
            abi.encode(address(0xDEAD))
        );
        vm.expectRevert("Only owner can set operator");
        engine.setOperatorApproval(profileId, address(0), true);
    }

    function testSetOperatorAsOwner() public {
        vm.mockCall(
            profileAddress,
            abi.encodeWithSelector(ERC721.ownerOf.selector, profileId),
            abi.encode(alice)
        );
        vm.prank(alice);
        engine.setOperatorApproval(profileId, gov, true);
    }

    function testSetMetadataAsOwner() public {
        vm.prank(bob);
        vm.mockCall(
            profileAddress,
            abi.encodeWithSelector(ERC721.ownerOf.selector, profileId),
            abi.encode(bob)
        );
        engine.setMetadata(profileId, "ipfs");
    }

    function testCannotSetMetadataAsNonOwnerAndOperator() public {
        vm.mockCall(
            profileAddress,
            abi.encodeWithSelector(ERC721.ownerOf.selector, profileId),
            abi.encode(address(0xDEAD))
        );
        vm.mockCall(
            profileAddress,
            abi.encodeWithSelector(
                IProfileNFT.getOperatorApproval.selector,
                profileId,
                address(this)
            ),
            abi.encode(false)
        );
        assertEq(ERC721(profileAddress).ownerOf(profileId), address(0xDEAD));
        assertEq(
            IProfileNFT(profileAddress).getOperatorApproval(
                profileId,
                address(this)
            ),
            false
        );
        vm.expectRevert("Only owner or operator can set metadata");
        engine.setMetadata(profileId, "ipfs");
    }

    function testSetMetadataAsOperator() public {
        vm.mockCall(
            profileAddress,
            abi.encodeWithSelector(ERC721.ownerOf.selector, profileId),
            abi.encode(address(0xDEAD))
        );
        vm.mockCall(
            profileAddress,
            abi.encodeWithSelector(
                IProfileNFT.getOperatorApproval.selector,
                profileId,
                address(this)
            ),
            abi.encode(true)
        );
        assertEq(ERC721(profileAddress).ownerOf(profileId), address(0xDEAD));
        assertEq(
            IProfileNFT(profileAddress).getOperatorApproval(
                profileId,
                address(this)
            ),
            true
        );
        string memory metadata = "ipfs";
        vm.mockCall(
            profileAddress,
            abi.encodeWithSelector(
                IProfileNFT.setMetadata.selector,
                profileId,
                metadata
            ),
            abi.encode(0)
        );
        engine.setMetadata(profileId, metadata);
    }
}