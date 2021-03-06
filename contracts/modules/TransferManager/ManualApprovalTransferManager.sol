pragma solidity ^0.4.24;

import "./ITransferManager.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";

/**
 * @title Transfer Manager module for manually approving transactions between accounts
 */
contract ManualApprovalTransferManager is ITransferManager {
    using SafeMath for uint256;

    bytes32 public constant TRANSFER_APPROVAL = "TRANSFER_APPROVAL";

    //Manual approval is an allowance (that has been approved) with an expiry time
    struct ManualApproval {
        address from;
        address to;
        uint256 allowance;
        uint256 expiryTime;
        bytes32 description;
    }

    mapping (address => mapping (address => uint256)) public approvalIndex;

    // An array to track all approvals. It is an unbounded array but it's not a problem as
    // it is never looped through in an onchain call. It is defined as an Array instead of mapping
    // just to make it easier for users to fetch list of all approvals through constant functions.
    ManualApproval[] public approvals;

    event AddManualApproval(
        address indexed _from,
        address indexed _to,
        uint256 _allowance,
        uint256 _expiryTime,
        bytes32 _description,
        address indexed _addedBy
    );

    event ModifyManualApproval(
        address indexed _from,
        address indexed _to,
        uint256 _expiryTime,
        uint256 _allowance,
        bytes32 _description,
        address indexed _edittedBy
    );

    event RevokeManualApproval(
        address indexed _from,
        address indexed _to,
        address indexed _addedBy
    );

    /**
     * @notice Constructor
     * @param _securityToken Address of the security token
     * @param _polyAddress Address of the polytoken
     */
    constructor (address _securityToken, address _polyAddress)
    public
    Module(_securityToken, _polyAddress)
    {
    }

    /**
     * @notice This function returns the signature of configure function
     */
    function getInitFunction() public pure returns (bytes4) {
        return bytes4(0);
    }

    /**
     * @notice Used to verify the transfer transaction and allow a manually approved transqaction to bypass other restrictions
     * @param _from Address of the sender
     * @param _to Address of the receiver
     * @param _amount The amount of tokens to transfer
     * @param _isTransfer Whether or not this is an actual transfer or just a test to see if the tokens would be transferrable
     */
    function verifyTransfer(address _from, address _to, uint256 _amount, bytes /* _data */, bool _isTransfer) public returns(Result) {
        // function must only be called by the associated security token if _isTransfer == true
        require(_isTransfer == false || msg.sender == securityToken, "Sender is not the owner");
        uint256 index = approvalIndex[_from][_to];
        if (!paused && index != 0) {
            index--; //Actual index is stored index - 1.
            ManualApproval storage approval = approvals[index];
            uint256 allowance = approval.allowance;
            if ((approval.expiryTime >= now) && (allowance >= _amount)) {
                if (_isTransfer) {
                    approval.allowance = allowance - _amount;
                }
                return Result.VALID;
            }
        }
        return Result.NA;
    }

    /**
    * @notice Adds a pair of addresses to manual approvals
    * @param _from is the address from which transfers are approved
    * @param _to is the address to which transfers are approved
    * @param _allowance is the approved amount of tokens
    * @param _expiryTime is the time until which the transfer is allowed
    * @param _description Description about the manual approval
    */
    function addManualApproval(
        address _from,
        address _to,
        uint256 _allowance,
        uint256 _expiryTime,
        bytes32 _description
    )
        external
        withPerm(TRANSFER_APPROVAL)
    {
        _addManualApproval(_from, _to, _allowance, _expiryTime, _description);
    }

    function _addManualApproval(address _from, address _to, uint256 _allowance, uint256 _expiryTime, bytes32 _description) internal {
        require(_to != address(0), "Invalid to address");
        require(_expiryTime > now, "Invalid expiry time");
        require(_allowance > 0, "Invalid allowance");
        uint256 index = approvalIndex[_from][_to];
        if (index != 0) {
            index--; //Actual index is stored index - 1.
            require(approvals[index].expiryTime < now || approvals[index].allowance == 0, "Approval already exists");
            _revokeManualApproval(_from, _to);
        }
        approvals.push(ManualApproval(_from, _to, _allowance, _expiryTime, _description));
        approvalIndex[_from][_to] = approvals.length;
        emit AddManualApproval(_from, _to, _allowance, _expiryTime, _description, msg.sender);
    }

    /**
    * @notice Adds mutiple manual approvals in batch
    * @param _from is the address array from which transfers are approved
    * @param _to is the address array to which transfers are approved
    * @param _allowances is the array of approved amounts
    * @param _expiryTimes is the array of the times until which eath transfer is allowed
    * @param _descriptions is the description array for these manual approvals
    */
    function addManualApprovalMulti(
        address[] _from,
        address[] _to,
        uint256[] _allowances,
        uint256[] _expiryTimes,
        bytes32[] _descriptions
    )
        external
        withPerm(TRANSFER_APPROVAL)
    {
        _checkInputLengthArray(_from, _to, _allowances, _expiryTimes, _descriptions);
        for (uint256 i = 0; i < _from.length; i++){
            _addManualApproval(_from[i], _to[i], _allowances[i], _expiryTimes[i], _descriptions[i]);
        }
    }

    /**
    * @notice Modify the existing manual approvals
    * @param _from is the address from which transfers are approved
    * @param _to is the address to which transfers are approved
    * @param _expiryTime is the time until which the transfer is allowed
    * @param _changeInAllowance is the change in allowance
    * @param _description Description about the manual approval
    * @param _increase tells whether the allowances will be increased (true) or decreased (false).
    * or any value when there is no change in allowances
    */
    function modifyManualApproval(
        address _from,
        address _to,
        uint256 _expiryTime,
        uint256 _changeInAllowance,
        bytes32 _description,
        bool _increase
    )
        external
        withPerm(TRANSFER_APPROVAL)
    {
        _modifyManualApproval(_from, _to, _expiryTime, _changeInAllowance, _description, _increase);
    }

    function _modifyManualApproval(
        address _from,
        address _to,
        uint256 _expiryTime,
        uint256 _changeInAllowance,
        bytes32 _description,
        bool _increase
    )
        internal
    {
        require(_to != address(0), "Invalid to address");
        /*solium-disable-next-line security/no-block-members*/
        require(_expiryTime > now, "Invalid expiry time");
        uint256 index = approvalIndex[_from][_to];
        require(index != 0, "Approval not present");
        index--; //Index is stored in an incremented form. 0 represnts non existant.
        ManualApproval storage approval = approvals[index];
        uint256 allowance = approval.allowance;
        uint256 expiryTime = approval.expiryTime;
        require(allowance != 0 && expiryTime > now, "Not allowed");

        if (_changeInAllowance > 0) {
            if (_increase) {
                // Allowance get increased
                allowance = allowance.add(_changeInAllowance);
            } else {
                // Allowance get decreased
                if (_changeInAllowance >= allowance) {
                    allowance = 0;
                } else {
                    allowance = allowance - _changeInAllowance;
                }
            }
            approval.allowance = allowance;
        }

        // Greedy storage technique
        if (expiryTime != _expiryTime) {
            approval.expiryTime = _expiryTime;
        }
        if (approval.description != _description) {
            approval.description = _description;
        }

        emit ModifyManualApproval(_from, _to, _expiryTime, allowance, _description, msg.sender);
    }

    /**
     * @notice Adds mutiple manual approvals in batch
     * @param _from is the address array from which transfers are approved
     * @param _to is the address array to which transfers are approved
     * @param _expiryTimes is the array of the times until which eath transfer is allowed
     * @param _changedAllowances is the array of approved amounts
     * @param _descriptions is the description array for these manual approvals
     * @param _increase Array of bool values which tells whether the allowances will be increased (true) or decreased (false)
     * or any value when there is no change in allowances
     */
    function modifyManualApprovalMulti(
        address[] _from,
        address[] _to,
        uint256[] _expiryTimes,
        uint256[] _changedAllowances,
        bytes32[] _descriptions,
        bool[] _increase
    )
        public
        withPerm(TRANSFER_APPROVAL)
    {
        _checkInputLengthArray(_from, _to, _changedAllowances, _expiryTimes, _descriptions);
        require(_increase.length == _changedAllowances.length, "Input length array mismatch");
        for (uint256 i = 0; i < _from.length; i++) {
            _modifyManualApproval(_from[i], _to[i], _expiryTimes[i], _changedAllowances[i], _descriptions[i], _increase[i]);
        }
    }

    /**
    * @notice Removes a pairs of addresses from manual approvals
    * @param _from is the address from which transfers are approved
    * @param _to is the address to which transfers are approved
    */
    function revokeManualApproval(address _from, address _to) external withPerm(TRANSFER_APPROVAL) {
        _revokeManualApproval(_from, _to);
    }

    function _revokeManualApproval(address _from, address _to) internal {
        uint256 index = approvalIndex[_from][_to];
        require(index != 0, "Approval does not exist");
        index--; //Actual index is stored index - 1.
        uint256 lastApprovalIndex = approvals.length - 1;
        // find the record in active approvals array & delete it
        if (index != lastApprovalIndex) {
            approvals[index] = approvals[lastApprovalIndex];
            approvalIndex[approvals[index].from][approvals[index].to] = index + 1;
        }
        delete approvalIndex[_from][_to];
        approvals.length--;
        emit RevokeManualApproval(_from, _to, msg.sender);
    }

    /**
    * @notice Removes mutiple pairs of addresses from manual approvals
    * @param _from is the address array from which transfers are approved
    * @param _to is the address array to which transfers are approved
    */
    function revokeManualApprovalMulti(address[] _from, address[] _to) external withPerm(TRANSFER_APPROVAL) {
        require(_from.length == _to.length, "Input array length mismatch");
        for(uint256 i = 0; i < _from.length; i++){
            _revokeManualApproval(_from[i], _to[i]);
        }
    }

    function _checkInputLengthArray(
        address[] _from,
        address[] _to,
        uint256[] _expiryTimes,
        uint256[] _allowances,
        bytes32[] _descriptions
    )
        internal
        pure
    {
        require(_from.length == _to.length &&
        _to.length == _allowances.length &&
        _allowances.length == _expiryTimes.length &&
        _expiryTimes.length == _descriptions.length,
        "Input array length mismatch"
        );
    }

    /**
     * @notice Returns the all active approvals corresponds to an address
     * @param _user Address of the holder corresponds to whom list of manual approvals
     * need to return
     * @return address[] addresses from
     * @return address[] addresses to
     * @return uint256[] allowances provided to the approvals
     * @return uint256[] expiry times provided to the approvals
     * @return bytes32[] descriptions provided to the approvals
     */
    function getActiveApprovalsToUser(address _user) external view returns(address[], address[], uint256[], uint256[], bytes32[]) {
        uint256 counter = 0;
        uint256 approvalsLength = approvals.length;
        for (uint256 i = 0; i < approvalsLength; i++) {
            if ((approvals[i].from == _user || approvals[i].to == _user)
                && approvals[i].expiryTime >= now)
                counter ++;
        }

        address[] memory from = new address[](counter);
        address[] memory to = new address[](counter);
        uint256[] memory allowance = new uint256[](counter);
        uint256[] memory expiryTime = new uint256[](counter);
        bytes32[] memory description = new bytes32[](counter);

        counter = 0;
        for (i = 0; i < approvalsLength; i++) {
            if ((approvals[i].from == _user || approvals[i].to == _user)
                && approvals[i].expiryTime >= now) {

                from[counter]=approvals[i].from;
                to[counter]=approvals[i].to;
                allowance[counter]=approvals[i].allowance;
                expiryTime[counter]=approvals[i].expiryTime;
                description[counter]=approvals[i].description;
                counter ++;
            }
        }
        return (from, to, allowance, expiryTime, description);
    }

    /**
     * @notice Get the details of the approval corresponds to _from & _to addresses
     * @param _from Address of the sender
     * @param _to Address of the receiver
     * @return uint256 expiryTime of the approval
     * @return uint256 allowance provided to the approval
     * @return uint256 Description provided to the approval
     */
    function getApprovalDetails(address _from, address _to) external view returns(uint256, uint256, bytes32) {
        uint256 index = approvalIndex[_from][_to];
        if (index != 0) {
            index--;
            if (index < approvals.length) {
                ManualApproval storage approval = approvals[index];
                return(
                    approval.expiryTime,
                    approval.allowance,
                    approval.description
                );
            }
        }
    }

    /**
    * @notice Returns the current number of active approvals
    */
    function getTotalApprovalsLength() external view returns(uint256) {
        return approvals.length;
    }

    /**
     * @notice Get the details of all approvals
     * @return address[] addresses from
     * @return address[] addresses to
     * @return uint256[] allowances provided to the approvals
     * @return uint256[] expiry times provided to the approvals
     * @return bytes32[] descriptions provided to the approvals
     */
    function getAllApprovals() external view returns(address[], address[], uint256[], uint256[], bytes32[]) {
        address[] memory from = new address[](approvals.length);
        address[] memory to = new address[](approvals.length);
        uint256[] memory allowance = new uint256[](approvals.length);
        uint256[] memory expiryTime = new uint256[](approvals.length);
        bytes32[] memory description = new bytes32[](approvals.length);
        uint256 approvalsLength = approvals.length;

        for (uint256 i = 0; i < approvalsLength; i++) {

            from[i]=approvals[i].from;
            to[i]=approvals[i].to;
            allowance[i]=approvals[i].allowance;
            expiryTime[i]=approvals[i].expiryTime;
            description[i]=approvals[i].description;

        }

        return (from, to, allowance, expiryTime, description);

    }

    /**
     * @notice Returns the permissions flag that are associated with ManualApproval transfer manager
     */
    function getPermissions() public view returns(bytes32[]) {
        bytes32[] memory allPermissions = new bytes32[](1);
        allPermissions[0] = TRANSFER_APPROVAL;
        return allPermissions;
    }
}
