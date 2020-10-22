pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./IAToken.sol";
import "./ILendingPool.sol";
import "./ILendingPoolCore.sol";
import "./ILendingPoolAddressesProvider.sol";
import "./FlashLoanReceiverBase.sol";
import "../HandlerBase.sol";
import "../../interface/IProxy.sol";

contract HAaveProtocol is HandlerBase, FlashLoanReceiverBase {
    using SafeERC20 for IERC20;

    uint16 constant REFERRAL_CODE = 56;

    function flashLoan(
        address _reserve,
        uint256 _amount,
        bytes calldata _params
    ) external payable {
        ILendingPool lendingPool = ILendingPool(
            ILendingPoolAddressesProvider(PROVIDER).getLendingPool()
        );
        lendingPool.flashLoan(address(this), _reserve, _amount, _params);

        // Update involved token
        if (_reserve != ETHADDRESS) _updateToken(_reserve);
    }

    function executeOperation(
        address _reserve,
        uint256 _amount,
        uint256 _fee,
        bytes calldata _params
    ) external payable {
        (address[] memory tos, bytes[] memory datas) = abi.decode(
            _params,
            (address[], bytes[])
        );
        IProxy(address(this)).execs(tos, datas);
        transferFundsBackToPoolInternal(_reserve, _amount.add(_fee));
    }

    function deposit(address _reserve, uint256 _amount)
        external
        payable
        returns (uint256 atoken_amount)
    {
        ILendingPool lendingPool = ILendingPool(
            ILendingPoolAddressesProvider(PROVIDER).getLendingPool()
        );

        // Get AToken before depositing
        address aToken = _getAToken(_reserve);
        uint256 beforeATokenBalance = IERC20(aToken).balanceOf(address(this));

        if (_reserve == ETHADDRESS) {
            lendingPool.deposit.value(_amount)(
                _reserve,
                _amount,
                REFERRAL_CODE
            );
        } else {
            address lendingPoolCore = ILendingPoolAddressesProvider(PROVIDER)
                .getLendingPoolCore();
            IERC20(_reserve).safeApprove(lendingPoolCore, _amount);
            lendingPool.deposit(_reserve, _amount, REFERRAL_CODE);
            IERC20(_reserve).safeApprove(lendingPoolCore, 0);
        }

        // Get AToken after depositing
        uint256 afterATokenBalance = IERC20(aToken).balanceOf(address(this));
        _updateToken(aToken);
        return (afterATokenBalance - beforeATokenBalance);
    }

    function redeem(address _aToken, uint256 _amount) external payable {
        IAToken(_aToken).redeem(_amount);
        address underlyingAsset = IAToken(_aToken).underlyingAssetAddress();
        if (underlyingAsset != ETHADDRESS) _updateToken(underlyingAsset);
    }

    function _getAToken(address _reserve) internal view returns (address) {
        ILendingPoolCore lendingPoolCore = ILendingPoolCore(
            ILendingPoolAddressesProvider(PROVIDER).getLendingPoolCore()
        );
        address aToken = lendingPoolCore.getReserveATokenAddress(_reserve);
        require(aToken != address(0), "aToken should not be zero address");

        return aToken;
    }
}
