// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import { CyberEngine } from "../../src/CyberEngine.sol";

contract MockEngineV2 is CyberEngine {
    function version() external pure override returns (uint256) {
        return 2;
    }
}