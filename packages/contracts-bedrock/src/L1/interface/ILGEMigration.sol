// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

/// @title  LGE Migration Interface
/// @notice Interface for the LGE Migrator contract to move LGE assets onto Ozean mainnet.
interface ILGEMigration {
    /// @notice This function is called by the LGE Staking contract to facilitate migration of staked tokens from
    ///         the LGE Staking pool to the Ozean L2.
    /// @param _user The address of the user whose staked funds are being migrated to Ozean.
    /// @param _l2Destination The address which will be credited the tokens on Ozean.
    /// @param _tokens The tokens being migrated to Ozean from the LGE Staking contract.
    /// @param _amounts The amounts of each token to be migrated to Ozean for the _user
    function migrate(
        address _user,
        address _l2Destination,
        address[] calldata _tokens,
        uint256[] calldata _amounts
    )
        external;
}
