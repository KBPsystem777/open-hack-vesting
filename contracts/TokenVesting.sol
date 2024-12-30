// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract TokenVesting is Ownable, Pausable, ReentrancyGuard {
    struct VestingSchedule {
        uint256 totalAmount; // Total tokens to be vested
        uint256 startTime; // Start time of the vesting schedule
        uint256 cliff; // Cliff duration in seconds
        uint256 duration; // Total vesting duration in seconds
        uint256 amountClaimed; // Amount of tokens claimed
        bool revoked; // Is the schedule revoked
    }

    // Token being vested
    IERC20 public token;

    // Mapping of beneficiary address to vesting schedule
    mapping(address => VestingSchedule) public vestingSchedules;

    // Whitelist of beneficiaries
    mapping(address => bool) public whitelist;

    // Events
    event VestingScheduleCreated(address indexed beneficiary, uint256 amount);
    event TokensClaimed(address indexed beneficiary, uint256 amount);
    event VestingRevoked(address indexed beneficiary);
    event BeneficiaryWhitelisted(address indexed beneficiary);
    event BeneficiaryRemovedFromWhitelist(address indexed beneficiary);

    constructor(
        address tokenAddress
    ) Ownable(msg.sender) ReentrancyGuard() Pausable() {
        require(tokenAddress != address(0), "Token address is invalid");
        token = IERC20(tokenAddress);
    }

    // Modifier to check if beneficiary is whitelisted
    modifier onlyWhitelisted(address beneficiary) {
        require(whitelist[beneficiary], "Beneficiary not whitelisted");
        _;
    }

    function addToWhitelist(address beneficiary) external onlyOwner {
        require(beneficiary != address(0), "Invalid address");
        whitelist[beneficiary] = true;
        emit BeneficiaryWhitelisted(beneficiary);
    }

    function removeFromWhitelist(address beneficiary) external onlyOwner {
        whitelist[beneficiary] = false;
        emit BeneficiaryRemovedFromWhitelist(beneficiary);
    }

    function createVestingSchedule(
        address beneficiary,
        uint256 amount,
        uint256 cliffDuration,
        uint256 vestingDuration,
        uint256 startTime
    ) external onlyOwner onlyWhitelisted(beneficiary) whenNotPaused {
        require(beneficiary != address(0), "Invalid beneficiary address");
        require(amount > 0, "Amount must be greater than zero");
        require(
            vestingDuration > cliffDuration,
            "Vesting duration must be greater than cliff duration"
        );
        require(
            vestingSchedules[beneficiary].totalAmount == 0,
            "Vesting schedule already exists"
        );

        vestingSchedules[beneficiary] = VestingSchedule({
            totalAmount: amount,
            startTime: startTime,
            cliff: cliffDuration,
            duration: vestingDuration,
            amountClaimed: 0,
            revoked: false
        });

        require(
            token.transferFrom(msg.sender, address(this), amount),
            "Token transfer failed"
        );

        emit VestingScheduleCreated(beneficiary, amount);
    }

    function calculateVestedAmount(
        address beneficiary
    ) public view returns (uint256) {
        VestingSchedule memory schedule = vestingSchedules[beneficiary];

        if (
            block.timestamp < schedule.startTime + schedule.cliff ||
            schedule.revoked
        ) {
            return 0;
        }

        uint256 elapsedTime = block.timestamp - schedule.startTime;
        uint256 totalVestableTime = schedule.duration;

        if (elapsedTime >= totalVestableTime) {
            return schedule.totalAmount;
        }

        return (schedule.totalAmount * elapsedTime) / totalVestableTime;
    }

    function claimVestedTokens() external nonReentrant whenNotPaused {
        VestingSchedule storage schedule = vestingSchedules[msg.sender];
        require(schedule.totalAmount > 0, "No vesting schedule found");
        require(!schedule.revoked, "Vesting schedule is revoked");

        // Ensure the cliff period has passed
        require(
            block.timestamp >= schedule.startTime + schedule.cliff,
            "No tokens to claim"
        );

        uint256 vestedAmount = calculateVestedAmount(msg.sender);
        uint256 claimableAmount = vestedAmount - schedule.amountClaimed;

        require(claimableAmount > 0, "No tokens available for claim");

        schedule.amountClaimed += claimableAmount;

        require(
            token.transfer(msg.sender, claimableAmount),
            "Token transfer failed"
        );

        emit TokensClaimed(msg.sender, claimableAmount);
    }

    function revokeVesting(
        address beneficiary
    ) external onlyOwner whenNotPaused {
        VestingSchedule storage schedule = vestingSchedules[beneficiary];
        require(schedule.totalAmount > 0, "No vesting schedule found");
        require(!schedule.revoked, "Vesting schedule already revoked");

        uint256 vestedAmount = calculateVestedAmount(beneficiary);
        uint256 unvestedAmount = schedule.totalAmount - vestedAmount;

        schedule.revoked = true;

        if (unvestedAmount > 0) {
            require(
                token.transfer(owner(), unvestedAmount),
                "Token transfer failed"
            );
        }

        emit VestingRevoked(beneficiary);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }
}
