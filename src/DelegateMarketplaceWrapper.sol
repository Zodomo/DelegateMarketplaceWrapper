// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

// Inheritance and Libraries
import {ERC721Holder} from "../lib/openzeppelin-contracts/contracts/token/ERC721/utils/ERC721Holder.sol";
import {ERC1155Holder} from "../lib/openzeppelin-contracts/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {DelegateTokenStructs as Structs} from "../lib/delegate-market/src/libraries/DelegateTokenLib.sol";
import {EnumerableSet} from "../lib/openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

// Interfaces
import {IERC20} from "../lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {IERC721} from "../lib/openzeppelin-contracts/contracts/interfaces/IERC721.sol";
import {IERC1155} from "../lib/openzeppelin-contracts/contracts/interfaces/IERC1155.sol";
import {IDelegateToken} from "../lib/delegate-market/src/interfaces/IDelegateToken.sol";
import {IDelegateRegistry} from "../lib/delegate-registry/src/IDelegateRegistry.sol";

/**
 * @title DelegateMarketplaceWrapper
 * @notice DelegateToken cannot be enumerated onchain, so this wrapper allows for programmatic onchain enumeration.
 * @dev Determines if/which delegateTokenId corresponds to the target asset if delegated via this wrapper.
 * @author Zodomo.eth (Farcaster/Telegram/Discord/Github: @zodomo, X: @0xZodomo, Email: zodomo@proton.me)
 * @custom:github https://github.com/Zodomo/DelegateMarketplaceWrapper
 * @custom:delegate https://delegate.xyz
 */
contract DelegateMarketplaceWrapper is ERC721Holder, ERC1155Holder {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    /// @notice Thrown if DelegateInfo contains an incorrect tokenType value.
    error DMW_InvalidDelegationType();

    /// @notice Address for the DelegateToken.sol contract.
    address public constant DELEGATE_TOKEN = 0xC2E257476822377dFB549f001B4cb00103345e66;
    /// @notice Address for the PrincipalToken.sol contract.
    address public constant PRINCIPAL_TOKEN = 0xC73dFD486BC155b8126a366F68A4fefe05CE1dCD;

    /// @dev Used to prevent storage slot collisions if multiple ERC20/ERC1155 delegations happen in a single block.
    uint256 private _internalSalt;

    /// @notice Stores storage slot pointers for delegateTokenIds. Purposefully designed to support ERC20/721/1155.
    mapping(address token => mapping(uint256 tokenId => EnumerableSet.Bytes32Set storageLocations)) private _delegateTokenIds;

    constructor() payable {}

    /// @notice Determines storage location from address, tokenId, and _internalSalt and writes to it + enumerates it.
    /// @param token Contract address of ERC20/721/1155 asset.
    /// @param tokenId Token ID if ERC721/1155 asset. Set '0' if ERC20.
    /// @param delegateTokenId The DelegateToken tokenId being written to storage and enumerated.
    function _writeDelegateTokenId(address token, uint256 tokenId, uint256 delegateTokenId) private {
        uint256 internalSalt = _internalSalt;
        bytes32 storageLocation;
        assembly ("memory-safe") {
            mstore(0, token)
            mstore(32, tokenId)
            mstore(64, internalSalt)
            storageLocation := keccak256(0, 96)
            mstore(storageLocation, delegateTokenId)
        }
        _delegateTokenIds[token][tokenId].add(storageLocation);
        unchecked {
            ++_internalSalt;
        }
    }

    /// @notice Returns tokens to sender if delegateHolder/principalHolder are set to address(this) in DelegateInfo.
    /// @param delegateTokenId The DelegateToken/PrincipalToken tokenId being returned to msg.sender.
    function _returnDelegateTokensIfNecessary(uint256 delegateTokenId) private {
        if (IERC721(DELEGATE_TOKEN).ownerOf(delegateTokenId) == address(this)) {
            IERC721(DELEGATE_TOKEN).transferFrom(address(this), msg.sender, delegateTokenId);
        }
        if (IERC721(PRINCIPAL_TOKEN).ownerOf(delegateTokenId) == address(this)) {
            IERC721(PRINCIPAL_TOKEN).transferFrom(address(this), msg.sender, delegateTokenId);
        }
    }

    /// @notice Returns all delegateTokenIds for any combo of token address and tokenId.
    /// @dev Use '0' for tokenId if checking for ERC20 tokens.
    /// @param token Contract address of ERC20/721/1155 asset.
    /// @param tokenId Token ID if ERC721/1155 asset. Set '0' if ERC20.
    function getDelegateTokenIds(address token, uint256 tokenId) public view returns (uint256[] memory delegateTokenIds) {
        bytes32[] memory storageLocations = _delegateTokenIds[token][tokenId].values();
        delegateTokenIds = new uint256[](storageLocations.length);
        for (uint256 i; i < storageLocations.length; ++i) {
            bytes32 storageLocation = storageLocations[i];
            uint256 delegateTokenId;
            assembly ("memory-safe") {
                delegateTokenId := sload(storageLocation)
            }
            delegateTokenIds[i] = delegateTokenId;
        }
    }

    /// @notice Enumerates storage to find target delegateTokenId held by a target address.
    /// @param token Contract address of ERC20/721/1155 asset.
    /// @param tokenId Token ID if ERC721/1155 asset. Set '0' if ERC20.
    /// @param target The target address to check for ownership.
    function findDelegateTokenForAddress(address token, uint256 tokenId, address target) external view returns (uint256 delegateTokenId) {
        uint256[] memory delegateTokenIds = getDelegateTokenIds(token, tokenId);
        for (uint256 i = delegateTokenIds.length; i > 0; --i) {
            if (IERC721(DELEGATE_TOKEN).ownerOf(delegateTokenIds[i - 1]) == target) return delegateTokenIds[i - 1];
        }
    }

    /// @notice Transfers target asset, deposits it into DelegateToken, updates enumerable state, and returns tokens if needed.
    /// @dev Set principalHolder/delegateHolder properly in delegateInfo! If set to this contract, it sends them to msg.sender!
    /// @param delegateInfo DelegateInfo struct from DelegateTokenLib.sol in delegate-registry.
    /// @param salt Salt used by DelegateToken for delegation purposes.
    function create(Structs.DelegateInfo calldata delegateInfo, uint256 salt) external returns (uint256 delegateTokenId) {
        if (delegateInfo.tokenType == IDelegateRegistry.DelegationType.ERC20) {
            IERC20(delegateInfo.tokenContract).transferFrom(msg.sender, address(this), delegateInfo.amount);
            IERC20(delegateInfo.tokenContract).approve(DELEGATE_TOKEN, type(uint256).max);
        } else if (delegateInfo.tokenType == IDelegateRegistry.DelegationType.ERC721) {
            IERC721(delegateInfo.tokenContract).transferFrom(msg.sender, address(this), delegateInfo.tokenId);
            IERC721(delegateInfo.tokenContract).setApprovalForAll(DELEGATE_TOKEN, true);
        } else if (delegateInfo.tokenType == IDelegateRegistry.DelegationType.ERC1155) {
            IERC1155(delegateInfo.tokenContract).safeTransferFrom(msg.sender, address(this), delegateInfo.tokenId, delegateInfo.amount, "");
            IERC1155(delegateInfo.tokenContract).setApprovalForAll(DELEGATE_TOKEN, true);
        } else revert DMW_InvalidDelegationType();

        uint256 tokenId = delegateInfo.tokenType == IDelegateRegistry.DelegationType.ERC20 ? 0 : delegateInfo.tokenId;
        delegateTokenId = IDelegateToken(DELEGATE_TOKEN).create(delegateInfo, salt);
        _writeDelegateTokenId(delegateInfo.tokenContract, tokenId, delegateTokenId);
        _returnDelegateTokensIfNecessary(delegateTokenId);
    }
}
