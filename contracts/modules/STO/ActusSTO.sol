pragma solidity ^0.4.24;

import "../../interfaces/IACTUSPaymentRouter.sol";

import "./CappedSTO.sol";


/**
 * @title ACTUS STO module
 */
contract ActusSTO is CappedSTO {


    // ACTUS protocol related
    int8 constant PRINCIPAL_CASHFLOW_ID = -4;
    uint256 constant PRINCIPAL_EVENT_ID = 0;

    bytes32 assetId;
    address paymentRouter;


    constructor(address _securityToken, address _polyAddress)
        CappedSTO(_securityToken, _polyAddress)
        public
    {
    }

    /**
     * (overridden function)
     */
    function () external payable {}

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
        super.configure(_startTime, _endTime, _cap, _rate, _fundRaiseTypes, address(this));

        // pause STO until an ACTUS is linked to the STO (buyer protection)
        // super.pause();
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
        require(assetId == bytes32(0), "ActusSTO.linkAsset: STO is already linked with asset.");

        assetId = _assetId;
        paymentRouter = _paymentRouter;

        // super.unpause();
    }

    /**
     * @notice pay principal for the linked ACTUS asset (anyone should be able to call this method)
     */
    function payPrincipal() external payable {
        require(isAssetLinked(), "ActusSTO.payPrincipal: STO is not linked to any asset.");
        require(capReached(), "ActusSTO.payPrincipal: Cap not reached yet");

        IACTUSPaymentRouter(paymentRouter).settlePayment.value(cap)(
            assetId,
            PRINCIPAL_CASHFLOW_ID,
            PRINCIPAL_EVENT_ID,
            address(0),
            cap
        );
    }

    /**
     * @notice Checks wether the STO is linked to an ACTUS asset
     */
    function isAssetLinked() public view returns (bool) {
        return (assetId != bytes32(0) && paymentRouter != address(0));
    }
}
