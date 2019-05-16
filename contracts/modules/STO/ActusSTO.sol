pragma solidity ^0.4.24;

import "./ActusSTOObligor.sol";
import "./CappedSTO.sol";


/**
 * @title ACTUS STO module
 */
contract ActusSTO is CappedSTO {

    ActusSTOObligor public obligor;


    constructor(address _securityToken, address _polyAddress)
        CappedSTO(_securityToken, _polyAddress)
        public
    {
        obligor = new ActusSTOObligor();
    }

    /**
     * @notice Function used to intialize the contract variables (overridden function)
     * @param _startTime Unix timestamp at which offering get started
     * @param _endTime Unix timestamp at which offering get ended
     * @param _cap Maximum No. of token base units for sale
     * @param _rate Token units a buyer gets multiplied by 10^18 per wei / base unit of POLY
     * @param _fundRaiseTypes Type of currency used to collect the funds
     */
    function configure(
        uint256 _startTime,
        uint256 _endTime,
        uint256 _cap,
        uint256 _rate,
        FundRaiseType[] _fundRaiseTypes
    )
        public
        onlyFactory
    {
        super.configure(_startTime, _endTime, _cap, _rate, _fundRaiseTypes, address(obligor));
    }

    /**
     * @notice This function returns the signature of configure function (overridden function)
     */
    function getInitFunction() public pure returns (bytes4) {
        return bytes4(keccak256("configure(uint256,uint256,uint256,uint256,uint8[])"));
    }

    /**
     * @notice links an ACTUS asset to the STO
     * @param _assetId id of the ACTUS asset
     */
    function linkAsset(bytes32 _assetId, address _paymentRouter) external onlyOwner {
        require(obligor.isAssetLinked() == false, "ActusSTO.linkAsset: STO is already linked with asset.");

        obligor.linkAsset(_assetId, _paymentRouter);
    }

    function payPrincipal() external payable {
        require(obligor.isAssetLinked(), "ActusSTO.finalize: STO is not linked to any asset.");
        require(capReached(), "ActusSTO.finalize: Cap not reached yet.");

        obligor.payPrincipal();
    }
}
