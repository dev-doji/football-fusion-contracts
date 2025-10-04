// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title FootballFusion Prize Distribution Contract
 * @dev Automated prize distribution with vesting and anti-dump mechanisms
 * @author FootballFusion Team
 * @notice Handles tournament prize payouts with configurable distribution schedules
 */
contract PrizeDistribution is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/
    
    enum DistributionType { Instant, Vested, Milestone }
    enum PrizeStatus { Pending, Claimable, Claimed, Expired }

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/
    
    struct PrizeAllocation {
        address recipient;
        uint256 totalAmount;
        uint256 claimedAmount;
        uint256 remainingAmount;
        DistributionType distributionType;
        PrizeStatus status;
        uint256 createdAt;
        uint256 vestingStart;
        uint256 vestingDuration;
        uint256 cliffPeriod;
        uint256 lastClaimTime;
        uint256 tournamentId;
        uint256 rank;
        bool hasCliff;
    }

    struct VestingSchedule {
        uint256 startTime;
        uint256 cliffDuration;
        uint256 vestingDuration;
        uint256 slicePeriodSeconds;
        bool revocable;
    }

    struct DistributionRule {
        uint256 minAmount;          // Minimum prize for this rule
        uint256 maxAmount;          // Maximum prize for this rule
        DistributionType distributionType;
        uint256 vestingDays;        // Vesting period in days
        uint256 cliffDays;          // Cliff period in days
        bool isActive;
    }

    struct TournamentPayout {
        uint256 tournamentId;
        uint256 totalPrizePool;
        uint256 totalDistributed;
        uint256 platformFee;
        uint256 winnersCount;
        uint256 createdAt;
        bool isFinalized;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    
    /// @notice USDC contract on Base
    IERC20 public immutable USDC;
    
    /// @notice Tournament contract address
    address public tournamentContract;
    
    /// @notice Prize allocation counter
    uint256 public allocationCounter;
    
    /// @notice Platform fee (2% = 200/10000)
    uint256 public constant PLATFORM_FEE_BPS = 200;
    uint256 private constant BPS_DENOMINATOR = 10_000;
    
    /// @notice Maximum vesting period (365 days)
    uint256 public constant MAX_VESTING_DURATION = 365 days;
    
    /// @notice Minimum claim interval (1 day)
    uint256 public constant MIN_CLAIM_INTERVAL = 1 days;
    
    /// @notice Main data mappings
    mapping(uint256 => PrizeAllocation) public allocations;
    mapping(address => uint256[]) public userAllocations;
    mapping(uint256 => TournamentPayout) public tournamentPayouts;
    mapping(uint256 => DistributionRule) public distributionRules;
    
    /// @notice User statistics
    mapping(address => uint256) public totalEarnings;
    mapping(address => uint256) public totalClaimed;
    mapping(address => uint256) public totalPending;
    
    /// @notice Distribution rules counter
    uint256 public rulesCounter;
    
    /// @notice Emergency pause for claims
    bool public claimsPaused;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event PrizeAllocated(
        uint256 indexed allocationId,
        address indexed recipient,
        uint256 amount,
        uint256 indexed tournamentId,
        DistributionType distributionType
    );
    
    event PrizeClaimed(
        uint256 indexed allocationId,
        address indexed recipient,
        uint256 amount,
        uint256 remaining
    );
    
    event TournamentPayoutCreated(
        uint256 indexed tournamentId,
        uint256 totalPrizePool,
        uint256 winnersCount
    );
    
    event DistributionRuleAdded(
        uint256 indexed ruleId,
        uint256 minAmount,
        uint256 maxAmount,
        DistributionType distributionType
    );
    
    event VestingAccelerated(
        uint256 indexed allocationId,
        address indexed recipient,
        uint256 acceleratedAmount
    );
    
    event EmergencyWithdrawal(
        address indexed recipient,
        uint256 amount,
        string reason
    );

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    
    error InvalidAllocation();
    error AllocationNotFound();
    error NotAuthorized();
    error InsufficientBalance();
    error ClaimNotReady();
    error AlreadyClaimed();
    error InvalidParameters();
    error VestingNotStarted();
    error CliffPeriodActive();
    error ClaimsPaused();
    error InvalidRule();
    error TournamentAlreadyPaid();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    constructor(
        address _usdcAddress,
        address _tournamentContract,
        address _initialOwner
    ) Ownable(_initialOwner) {
        if (_usdcAddress == address(0) || _tournamentContract == address(0)) {
            revert InvalidParameters();
        }
        
        USDC = IERC20(_usdcAddress);
        tournamentContract = _tournamentContract;
        
        // Initialize default distribution rules
        _initializeDefaultRules();
    }

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    
    modifier onlyTournament() {
        if (msg.sender != tournamentContract) revert NotAuthorized();
        _;
    }
    
    modifier validAllocation(uint256 allocationId) {
        if (allocationId > allocationCounter || allocationId == 0) {
            revert AllocationNotFound();
        }
        _;
    }
    
    modifier claimsNotPaused() {
        if (claimsPaused) revert ClaimsPaused();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            TOURNAMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Create tournament payout and allocate prizes
     * @param tournamentId Tournament ID
     * @param winners Array of winner addresses
     * @param amounts Array of prize amounts
     * @param ranks Array of winner ranks
     */
    function createTournamentPayout(
        uint256 tournamentId,
        address[] calldata winners,
        uint256[] calldata amounts,
        uint256[] calldata ranks
    ) external onlyTournament nonReentrant {
        if (winners.length != amounts.length || winners.length != ranks.length) {
            revert InvalidParameters();
        }
        if (tournamentPayouts[tournamentId].isFinalized) {
            revert TournamentAlreadyPaid();
        }
        
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }
        
        uint256 platformFee = (totalAmount * PLATFORM_FEE_BPS) / BPS_DENOMINATOR;
        uint256 netAmount = totalAmount - platformFee;
        
        // Create tournament payout record
        tournamentPayouts[tournamentId] = TournamentPayout({
            tournamentId: tournamentId,
            totalPrizePool: totalAmount,
            totalDistributed: 0,
            platformFee: platformFee,
            winnersCount: winners.length,
            createdAt: block.timestamp,
            isFinalized: false
        });
        
        // Create individual prize allocations
        for (uint256 i = 0; i < winners.length; i++) {
            uint256 prizeAmount = amounts[i];
            if (prizeAmount > 0) {
                _createPrizeAllocation(
                    winners[i],
                    prizeAmount,
                    tournamentId,
                    ranks[i]
                );
            }
        }
        
        // Transfer platform fee
        if (platformFee > 0) {
            USDC.safeTransfer(owner(), platformFee);
        }
        
        tournamentPayouts[tournamentId].isFinalized = true;
        
        emit TournamentPayoutCreated(tournamentId, totalAmount, winners.length);
    }

    /*//////////////////////////////////////////////////////////////
                            CLAIMING FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Claim available prize amount
     * @param allocationId Prize allocation ID
     */
    function claimPrize(uint256 allocationId) external nonReentrant claimsNotPaused validAllocation(allocationId) {
        PrizeAllocation storage allocation = allocations[allocationId];
        
        if (allocation.recipient != msg.sender) revert NotAuthorized();
        if (allocation.status == PrizeStatus.Claimed) revert AlreadyClaimed();
        if (allocation.status == PrizeStatus.Expired) revert InvalidAllocation();
        
        uint256 claimableAmount = _calculateClaimableAmount(allocationId);
        if (claimableAmount == 0) revert ClaimNotReady();
        
        // Update allocation state
        allocation.claimedAmount += claimableAmount;
        allocation.remainingAmount -= claimableAmount;
        allocation.lastClaimTime = block.timestamp;
        
        // Update user statistics
        totalClaimed[msg.sender] += claimableAmount;
        totalPending[msg.sender] -= claimableAmount;
        
        // Mark as fully claimed if nothing remaining
        if (allocation.remainingAmount == 0) {
            allocation.status = PrizeStatus.Claimed;
        }
        
        // Transfer USDC
        USDC.safeTransfer(msg.sender, claimableAmount);
        
        emit PrizeClaimed(allocationId, msg.sender, claimableAmount, allocation.remainingAmount);
    }
    
    /**
     * @notice Batch claim multiple allocations
     * @param allocationIds Array of allocation IDs
     */
    function batchClaimPrizes(uint256[] calldata allocationIds) external nonReentrant claimsNotPaused {
        uint256 totalClaimable = 0;
        
        for (uint256 i = 0; i < allocationIds.length; i++) {
            uint256 allocationId = allocationIds[i];
            if (allocationId > allocationCounter || allocationId == 0) continue;
            
            PrizeAllocation storage allocation = allocations[allocationId];
            if (allocation.recipient != msg.sender) continue;
            if (allocation.status == PrizeStatus.Claimed || allocation.status == PrizeStatus.Expired) continue;
            
            uint256 claimableAmount = _calculateClaimableAmount(allocationId);
            if (claimableAmount == 0) continue;
            
            // Update allocation state
            allocation.claimedAmount += claimableAmount;
            allocation.remainingAmount -= claimableAmount;
            allocation.lastClaimTime = block.timestamp;
            
            if (allocation.remainingAmount == 0) {
                allocation.status = PrizeStatus.Claimed;
            }
            
            totalClaimable += claimableAmount;
            
            emit PrizeClaimed(allocationId, msg.sender, claimableAmount, allocation.remainingAmount);
        }
        
        if (totalClaimable > 0) {
            // Update user statistics
            totalClaimed[msg.sender] += totalClaimable;
            totalPending[msg.sender] -= totalClaimable;
            
            // Transfer USDC
            USDC.safeTransfer(msg.sender, totalClaimable);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Add new distribution rule
     * @param minAmount Minimum prize amount for this rule
     * @param maxAmount Maximum prize amount for this rule
     * @param distributionType Type of distribution
     * @param vestingDays Vesting period in days
     * @param cliffDays Cliff period in days
     */
    function addDistributionRule(
        uint256 minAmount,
        uint256 maxAmount,
        DistributionType distributionType,
        uint256 vestingDays,
        uint256 cliffDays
    ) external onlyOwner {
        if (minAmount >= maxAmount) revert InvalidParameters();
        if (vestingDays > 365) revert InvalidParameters();
        if (cliffDays > vestingDays) revert InvalidParameters();
        
        rulesCounter++;
        
        distributionRules[rulesCounter] = DistributionRule({
            minAmount: minAmount,
            maxAmount: maxAmount,
            distributionType: distributionType,
            vestingDays: vestingDays,
            cliffDays: cliffDays,
            isActive: true
        });
        
        emit DistributionRuleAdded(rulesCounter, minAmount, maxAmount, distributionType);
    }
    
    /**
     * @notice Accelerate vesting for specific allocation (emergency)
     * @param allocationId Allocation ID
     * @param acceleratedAmount Amount to make immediately claimable
     */
    function accelerateVesting(
        uint256 allocationId,
        uint256 acceleratedAmount
    ) external onlyOwner validAllocation(allocationId) {
        PrizeAllocation storage allocation = allocations[allocationId];
        
        if (acceleratedAmount > allocation.remainingAmount) {
            revert InvalidParameters();
        }
        
        // Make amount immediately claimable by adjusting vesting start
        uint256 totalVested = allocation.totalAmount - allocation.remainingAmount + acceleratedAmount;
        uint256 newVestingProgress = (totalVested * allocation.vestingDuration) / allocation.totalAmount;
        
        if (newVestingProgress > 0) {
            allocation.vestingStart = block.timestamp - newVestingProgress;
        }
        
        emit VestingAccelerated(allocationId, allocation.recipient, acceleratedAmount);
    }
    
    /**
     * @notice Emergency withdrawal (admin only)
     * @param recipient Recipient address
     * @param amount Amount to withdraw
     * @param reason Reason for withdrawal
     */
    function emergencyWithdraw(
        address recipient,
        uint256 amount,
        string calldata reason
    ) external onlyOwner {
        if (amount > USDC.balanceOf(address(this))) {
            revert InsufficientBalance();
        }
        
        USDC.safeTransfer(recipient, amount);
        
        emit EmergencyWithdrawal(recipient, amount, reason);
    }
    
    /**
     * @notice Set tournament contract address
     * @param _tournamentContract New tournament contract address
     */
    function setTournamentContract(address _tournamentContract) external onlyOwner {
        if (_tournamentContract == address(0)) revert InvalidParameters();
        tournamentContract = _tournamentContract;
    }
    
    /**
     * @notice Pause/unpause claims
     * @param _paused Pause state
     */
    function setClaimsPaused(bool _paused) external onlyOwner {
        claimsPaused = _paused;
    }
    
    /**
     * @notice Emergency pause
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @notice Unpause
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function _createPrizeAllocation(
        address recipient,
        uint256 amount,
        uint256 tournamentId,
        uint256 rank
    ) internal {
        allocationCounter++;
        
        // Determine distribution type based on amount and rules
        DistributionRule memory rule = _getDistributionRule(amount);
        
        uint256 vestingStart = block.timestamp;
        uint256 vestingDuration = rule.vestingDays * 1 days;
        uint256 cliffPeriod = rule.cliffDays * 1 days;
        
        // Instant distribution for small amounts
        if (rule.distributionType == DistributionType.Instant) {
            vestingStart = block.timestamp;
            vestingDuration = 0;
            cliffPeriod = 0;
        }
        
        allocations[allocationCounter] = PrizeAllocation({
            recipient: recipient,
            totalAmount: amount,
            claimedAmount: 0,
            remainingAmount: amount,
            distributionType: rule.distributionType,
            status: PrizeStatus.Claimable,
            createdAt: block.timestamp,
            vestingStart: vestingStart,
            vestingDuration: vestingDuration,
            cliffPeriod: cliffPeriod,
            lastClaimTime: 0,
            tournamentId: tournamentId,
            rank: rank,
            hasCliff: cliffPeriod > 0
        });
        
        userAllocations[recipient].push(allocationCounter);
        
        // Update user statistics
        totalEarnings[recipient] += amount;
        totalPending[recipient] += amount;
        
        emit PrizeAllocated(allocationCounter, recipient, amount, tournamentId, rule.distributionType);
    }
    
    function _calculateClaimableAmount(uint256 allocationId) internal view returns (uint256) {
        PrizeAllocation memory allocation = allocations[allocationId];
        
        if (allocation.remainingAmount == 0) return 0;
        if (allocation.distributionType == DistributionType.Instant) {
            return allocation.remainingAmount;
        }
        
        // Check if cliff period has passed
        if (allocation.hasCliff && block.timestamp < allocation.vestingStart + allocation.cliffPeriod) {
            return 0;
        }
        
        // Calculate vested amount
        if (allocation.vestingDuration == 0) {
            return allocation.remainingAmount;
        }
        
        uint256 timeElapsed = block.timestamp - allocation.vestingStart;
        if (timeElapsed >= allocation.vestingDuration) {
            return allocation.remainingAmount;
        }
        
        uint256 totalVested = (allocation.totalAmount * timeElapsed) / allocation.vestingDuration;
        uint256 claimable = totalVested - allocation.claimedAmount;
        
        return claimable > allocation.remainingAmount ? allocation.remainingAmount : claimable;
    }
    
    function _getDistributionRule(uint256 amount) internal view returns (DistributionRule memory) {
        // Default to instant for small amounts
        DistributionRule memory defaultRule = DistributionRule({
            minAmount: 0,
            maxAmount: type(uint256).max,
            distributionType: DistributionType.Instant,
            vestingDays: 0,
            cliffDays: 0,
            isActive: true
        });
        
        for (uint256 i = 1; i <= rulesCounter; i++) {
            DistributionRule memory rule = distributionRules[i];
            if (rule.isActive && amount >= rule.minAmount && amount <= rule.maxAmount) {
                return rule;
            }
        }
        
        return defaultRule;
    }
    
    function _initializeDefaultRules() internal {
        // Rule 1: Instant for small prizes (< $100)
        rulesCounter++;
        distributionRules[rulesCounter] = DistributionRule({
            minAmount: 0,
            maxAmount: 100_000000, // $100 USDC
            distributionType: DistributionType.Instant,
            vestingDays: 0,
            cliffDays: 0,
            isActive: true
        });
        
        // Rule 2: 7-day vesting for medium prizes ($100-$1000)
        rulesCounter++;
        distributionRules[rulesCounter] = DistributionRule({
            minAmount: 100_000000, // $100 USDC
            maxAmount: 1000_000000, // $1000 USDC
            distributionType: DistributionType.Vested,
            vestingDays: 7,
            cliffDays: 1,
            isActive: true
        });
        
        // Rule 3: 30-day vesting for large prizes (> $1000)
        rulesCounter++;
        distributionRules[rulesCounter] = DistributionRule({
            minAmount: 1000_000000, // $1000 USDC
            maxAmount: type(uint256).max,
            distributionType: DistributionType.Vested,
            vestingDays: 30,
            cliffDays: 7,
            isActive: true
        });
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function getAllocation(uint256 allocationId) external view returns (PrizeAllocation memory) {
        return allocations[allocationId];
    }
    
    function getUserAllocations(address user) external view returns (uint256[] memory) {
        return userAllocations[user];
    }
    
    function getClaimableAmount(uint256 allocationId) external view returns (uint256) {
        return _calculateClaimableAmount(allocationId);
    }
    
    function getUserClaimableTotal(address user) external view returns (uint256) {
        uint256[] memory userAllocs = userAllocations[user];
        uint256 total = 0;
        
        for (uint256 i = 0; i < userAllocs.length; i++) {
            total += _calculateClaimableAmount(userAllocs[i]);
        }
        
        return total;
    }
    
    function getTournamentPayout(uint256 tournamentId) external view returns (TournamentPayout memory) {
        return tournamentPayouts[tournamentId];
    }
    
    function getDistributionRule(uint256 ruleId) external view returns (DistributionRule memory) {
        return distributionRules[ruleId];
    }
    
    function getUserStats(address user) external view returns (uint256 earnings, uint256 claimed, uint256 pending) {
        return (totalEarnings[user], totalClaimed[user], totalPending[user]);
    }
    
    function getContractBalance() external view returns (uint256) {
        return USDC.balanceOf(address(this));
    }
}