// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.14;

interface IEssenceNFT {
    /**
     * @notice Mints the Essence NFT.
     *
     * @param to The recipient address.
     * @return uint256 The token id.
     */
    function mint(address to) external returns (uint256);

    /**
     * @notice Initializes the Essence NFT.
     *
     * @param profileId The profile ID for the Essence NFT.
     * @param essenceId The essence ID for the Essence NFT.
     * @param name The name for the Essence NFT.
     * @param symbol The symbol for the Essence NFT.
     */
    function initialize(
        uint256 profileId,
        uint256 essenceId,
        string calldata name,
        string calldata symbol
    ) external;
}