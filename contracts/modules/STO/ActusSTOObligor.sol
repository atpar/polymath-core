pragma solidity ^0.4.24;

import "../../interfaces/IACTUSPaymentRouter.sol";


/**
 * @title ACTUS STO escrow
 */
contract ActusSTOObligor {

    address public actusSTO;

    // ACTUS protocol related
    int8 constant PRINCIPAL_CASHFLOW_ID = -4;
    uint256 constant PRINCIPAL_EVENT_ID = 0;

    bytes32 public assetId;
    address public paymentRouter;


    modifier onlySTO {
        require(msg.sender == address(actusSTO), "ActusSTOObligor.onlySTO: Unauthorized Sender.");
        _;
    }

    constructor() public {
        actusSTO = msg.sender;
    }

    /**
     * @notice pay principal for the linked ACTUS asset (anyone should be able to call this method)
     */
    function payPrincipal() external payable onlySTO {
        require(isAssetLinked(), "ActusSTOObligor.payPrincipal: STO is not linked to any asset.");

        IACTUSPaymentRouter(paymentRouter).settlePayment.value(address(this).balance)(
            assetId,
            PRINCIPAL_CASHFLOW_ID,
            PRINCIPAL_EVENT_ID,
            address(0),
            address(this).balance
        );
    }

    /**
     * @notice links an ACTUS asset to the STO
     * @param _assetId id of the ACTUS asset
     */
    function linkAsset(bytes32 _assetId, address _paymentRouter) external onlySTO {
        require(assetId == bytes32(0), "ActusSTOObligor.linkAsset: STO is already linked with asset.");

        assetId = _assetId;
        paymentRouter = _paymentRouter;
    }

    /**
     * @notice Checks wether the STO is linked to an ACTUS asset
     */
    function isAssetLinked() public view returns (bool) {
        return (assetId != bytes32(0) && paymentRouter != address(0));
    }

    /**
     * @notice Only accept Ether send from STO
     */
    function () external payable onlySTO {
        // require(isAssetLinked(), "Fallback: STO is not linked with asset.");
    }
}
