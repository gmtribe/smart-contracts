// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "./CampaignRegistryUpgradeable.sol";

contract CampaignRegistryProxyFactory {
    address public immutable implementationAddress;
    
    event ProxyDeployed(address proxyAddress);
    
    constructor(address _implementationAddress) {
        implementationAddress = _implementationAddress;
    }
    
    function deployProxy(
        address initialOwner,
        address signerAddress
    ) external returns (address) {
        bytes memory initData = abi.encodeWithSelector(
            CampaignRegistryUpgradeable.initialize.selector,
            initialOwner,
            signerAddress
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(
            implementationAddress,
            initData
        );
        
        emit ProxyDeployed(address(proxy));
        return address(proxy);
    }
}