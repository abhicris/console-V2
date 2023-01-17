//SDPX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IDropProxyFactory {
    event ImplementationSet(address indexed dropImpelmentation);

    /**
     * @dev Emitted when an edition is created.
     * @param consoleDrop The address of the edition.
     * @param deployer     The address of the deployer.
     * @param initData     The calldata to initialize consoleDrop via `abi.encodeWithSelector`.
     * @param contracts    The list of contracts called.
     * @param data         The list of calldata created via `abi.encodeWithSelector`
     * @param results      The results of calling the contracts. Use `abi.decode` to decode them.
     */
    event DropCreated(
        address indexed consoleDrop,
        address indexed deployer,
        bytes initData,
        address[] contracts,
        bytes[] data,
        bytes[] results
    );

    /**
     * @dev Thrown if the lengths of the input arrays are not equal.
     */
    error ArrayLengthsMismatch();

    // =============================================================
    //               PUBLIC / EXTERNAL WRITE FUNCTIONS
    // =============================================================

    function createDrop(
        bytes32 salt,
        bytes calldata initData,
        address[] calldata contracts,
        bytes[] calldata data
    ) external returns (address consoleDrop, bytes[] memory results);

    /**
     * @dev Changes the consoleDrop implementation contract address.
     *
     * Calling conditions:
     * - The caller must be the owner of the contract.
     *
     * @param newImplementation The new implementation address to be set.
     */
    function setNewImplementation(address newImplementation) external;

    // =============================================================
    //               PUBLIC / EXTERNAL VIEW FUNCTIONS
    // =============================================================

    /**
     * @dev The address of the implementation.
     * @return The configured value.
     */
    function dropImplementation() external returns (address);

    
    function consoleDropAddress(address by, bytes32 salt)
        external
        view
        returns (address addr, bool exists);
}
