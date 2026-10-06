// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.28;

/// @notice Target of proposal actions: records calls, can fail, and can call back into another contract.
contract ActionTarget {
    uint256 public value;
    address public lastCaller;

    error ActionReverted();

    event ValueSet(uint256 value, address caller);

    function setValue(uint256 _value) external payable {
        value = _value;
        lastCaller = msg.sender;
        emit ValueSet(_value, msg.sender);
    }

    function fail() external pure {
        revert ActionReverted();
    }

    /// @dev Calls `_target` with `_data` and bubbles up any revert, to test reentrancy from an action.
    function callBack(address _target, bytes calldata _data) external {
        (bool ok, bytes memory ret) = _target.call(_data);
        if (!ok) {
            assembly {
                revert(add(ret, 32), mload(ret))
            }
        }
    }
}
