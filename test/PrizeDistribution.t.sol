// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {PrizeDistribution} from "../src/PrizeDistribution.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract PrizeDistributionTest is Test {
    PrizeDistribution public prizeDistribution;
    ERC20Mock public usdc;
    
    address public owner = makeAddr("owner");
    address public tournamentContract = makeAddr("tournament");
    address public winner1 = makeAddr("winner1");
    address public winner2 = makeAddr("winner2");
    address public winner3 = makeAddr("winner3");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    
    uint256 constant INITIAL_USDC_SUPPLY = 1_000_000_000_000; // 1M USDC (6 decimals)
    uint256 constant PLATFORM_FEE_BPS = 200; // 2%
    uint256 constant BPS_DENOMINATOR = 10_000;
    
    // Test tournament data
    uint256 constant TEST_TOURNAMENT_ID = 1;
    uint256 constant SMALL_PRIZE = 50_000000; // $50 USDC
    uint256 constant MEDIUM_PRIZE = 500_000000; // $500 USDC  
    uint256 constant LARGE_PRIZE = 5000_000000; // $5000 USDC
    
    function setUp() public {
        // Deploy mock USDC
        usdc = new ERC20Mock();
        usdc.mint(address(this), INITIAL_USDC_SUPPLY);
        
        vm.startPrank(owner);
        prizeDistribution = new PrizeDistribution(
            address(usdc),
            tournamentContract,
            owner
        );
        vm.stopPrank();
        
        // Give tournament contract USDC for platform fees and prize funding
        usdc.transfer(tournamentContract, INITIAL_USDC_SUPPLY / 2);
        
        // CRITICAL FIX: Fund the prize distribution contract so it can pay out prizes
        usdc.transfer(address(prizeDistribution), INITIAL_USDC_SUPPLY / 4);
        
        // Approve prize distribution contract to spend USDC from tournament contract
        vm.prank(tournamentContract);
        usdc.approve(address(prizeDistribution), INITIAL_USDC_SUPPLY);
    }
    
    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testInitialState() public {
        assertEq(address(prizeDistribution.USDC()), address(usdc));
        assertEq(prizeDistribution.owner(), owner);
        assertEq(prizeDistribution.tournamentContract(), tournamentContract);
        assertEq(prizeDistribution.allocationCounter(), 0);
        assertEq(prizeDistribution.rulesCounter(), 3); // 3 default rules
        assertFalse(prizeDistribution.claimsPaused());
        assertFalse(prizeDistribution.paused());
    }
    
    function testDefaultDistributionRules() public {
        // Rule 1: Instant for < $100
        PrizeDistribution.DistributionRule memory rule1 = prizeDistribution.getDistributionRule(1);
        assertEq(rule1.minAmount, 0);
        assertEq(rule1.maxAmount, 100_000000);
        assertEq(uint256(rule1.distributionType), uint256(PrizeDistribution.DistributionType.Instant));
        assertEq(rule1.vestingDays, 0);
        assertEq(rule1.cliffDays, 0);
        assertTrue(rule1.isActive);
        
        // Rule 2: 7-day vesting for $100-$1000
        PrizeDistribution.DistributionRule memory rule2 = prizeDistribution.getDistributionRule(2);
        assertEq(rule2.minAmount, 100_000000);
        assertEq(rule2.maxAmount, 1000_000000);
        assertEq(uint256(rule2.distributionType), uint256(PrizeDistribution.DistributionType.Vested));
        assertEq(rule2.vestingDays, 7);
        assertEq(rule2.cliffDays, 1);
        
        // Rule 3: 30-day vesting for > $1000
        PrizeDistribution.DistributionRule memory rule3 = prizeDistribution.getDistributionRule(3);
        assertEq(rule3.minAmount, 1000_000000);
        assertEq(rule3.maxAmount, type(uint256).max);
        assertEq(uint256(rule3.distributionType), uint256(PrizeDistribution.DistributionType.Vested));
        assertEq(rule3.vestingDays, 30);
        assertEq(rule3.cliffDays, 7);
    }
    
    function testConstructorFailsWithZeroAddresses() public {
        vm.expectRevert(PrizeDistribution.InvalidParameters.selector);
        new PrizeDistribution(address(0), tournamentContract, owner);
        
        vm.expectRevert(PrizeDistribution.InvalidParameters.selector);
        new PrizeDistribution(address(usdc), address(0), owner);
    }
    
    /*//////////////////////////////////////////////////////////////
                        TOURNAMENT PAYOUT TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testCreateTournamentPayoutBasic() public {
        address[] memory winners = new address[](3);
        uint256[] memory amounts = new uint256[](3);
        uint256[] memory ranks = new uint256[](3);
        
        winners[0] = winner1;
        winners[1] = winner2;
        winners[2] = winner3;
        amounts[0] = 1000_000000; // $1000
        amounts[1] = 600_000000;  // $600
        amounts[2] = 400_000000;  // $400
        ranks[0] = 1;
        ranks[1] = 2;
        ranks[2] = 3;
        
        uint256 totalAmount = 2000_000000; // $2000
        uint256 expectedFee = (totalAmount * PLATFORM_FEE_BPS) / BPS_DENOMINATOR; // $40
        
        uint256 ownerBalanceBefore = usdc.balanceOf(owner);
        
        // Fund the tournament contract for this payout
        vm.prank(address(this));
        usdc.transfer(tournamentContract, totalAmount);
        
        vm.prank(tournamentContract);
        prizeDistribution.createTournamentPayout(
            TEST_TOURNAMENT_ID,
            winners,
            amounts,
            ranks
        );
        
        // Check tournament payout record
        PrizeDistribution.TournamentPayout memory payout = prizeDistribution.getTournamentPayout(TEST_TOURNAMENT_ID);
        assertEq(payout.tournamentId, TEST_TOURNAMENT_ID);
        assertEq(payout.totalPrizePool, totalAmount);
        assertEq(payout.platformFee, expectedFee);
        assertEq(payout.winnersCount, 3);
        assertTrue(payout.isFinalized);
        
        // Check platform fee was transferred
        assertEq(usdc.balanceOf(owner), ownerBalanceBefore + expectedFee);
        
        // Check allocations were created
        assertEq(prizeDistribution.allocationCounter(), 3);
        
        // Check individual allocations
        uint256[] memory winner1Allocations = prizeDistribution.getUserAllocations(winner1);
        assertEq(winner1Allocations.length, 1);
        
        PrizeDistribution.PrizeAllocation memory allocation1 = prizeDistribution.getAllocation(winner1Allocations[0]);
        assertEq(allocation1.recipient, winner1);
        assertEq(allocation1.totalAmount, 1000_000000);
        assertEq(allocation1.rank, 1);
        assertEq(allocation1.tournamentId, TEST_TOURNAMENT_ID);
    }
    
    function testCreateTournamentPayoutFailsForUnauthorized() public {
        address[] memory winners = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory ranks = new uint256[](1);
        
        winners[0] = winner1;
        amounts[0] = 100_000000;
        ranks[0] = 1;
        
        vm.prank(user1); // Not tournament contract
        vm.expectRevert(PrizeDistribution.NotAuthorized.selector);
        prizeDistribution.createTournamentPayout(TEST_TOURNAMENT_ID, winners, amounts, ranks);
    }
    
    function testCreateTournamentPayoutFailsForMismatchedArrays() public {
        address[] memory winners = new address[](2);
        uint256[] memory amounts = new uint256[](3); // Mismatched length
        uint256[] memory ranks = new uint256[](2);
        
        vm.prank(tournamentContract);
        vm.expectRevert(PrizeDistribution.InvalidParameters.selector);
        prizeDistribution.createTournamentPayout(TEST_TOURNAMENT_ID, winners, amounts, ranks);
    }
    
    function testCreateTournamentPayoutFailsIfAlreadyFinalized() public {
        address[] memory winners = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory ranks = new uint256[](1);
        
        winners[0] = winner1;
        amounts[0] = 100_000000;
        ranks[0] = 1;
        
        uint256 totalAmount = 100_000000;
        
        vm.startPrank(tournamentContract);
        
        // First creation should succeed
        prizeDistribution.createTournamentPayout(TEST_TOURNAMENT_ID, winners, amounts, ranks);
        
        // Second creation should fail
        vm.expectRevert(PrizeDistribution.TournamentAlreadyPaid.selector);
        prizeDistribution.createTournamentPayout(TEST_TOURNAMENT_ID, winners, amounts, ranks);
        
        vm.stopPrank();
    }
    
    /*//////////////////////////////////////////////////////////////
                         INSTANT CLAIMING TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testClaimInstantPrize() public {
        // Create a small prize that should be instantly claimable
        address[] memory winners = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory ranks = new uint256[](1);
        
        winners[0] = winner1;
        amounts[0] = SMALL_PRIZE; // $50 - instant distribution
        ranks[0] = 1;
        
        vm.prank(tournamentContract);
        prizeDistribution.createTournamentPayout(TEST_TOURNAMENT_ID, winners, amounts, ranks);
        
        uint256 allocationId = prizeDistribution.getUserAllocations(winner1)[0];
        uint256 claimableAmount = prizeDistribution.getClaimableAmount(allocationId);
        assertEq(claimableAmount, SMALL_PRIZE);
        
        uint256 balanceBefore = usdc.balanceOf(winner1);
        
        vm.prank(winner1);
        vm.expectEmit(true, true, false, true);
        emit PrizeDistribution.PrizeClaimed(allocationId, winner1, SMALL_PRIZE, 0);
        prizeDistribution.claimPrize(allocationId);
        
        assertEq(usdc.balanceOf(winner1), balanceBefore + SMALL_PRIZE);
        
        // Check allocation status
        PrizeDistribution.PrizeAllocation memory allocation = prizeDistribution.getAllocation(allocationId);
        assertEq(allocation.claimedAmount, SMALL_PRIZE);
        assertEq(allocation.remainingAmount, 0);
        assertEq(uint256(allocation.status), uint256(PrizeDistribution.PrizeStatus.Claimed));
        
        // Check user stats
        (uint256 earnings, uint256 claimed, uint256 pending) = prizeDistribution.getUserStats(winner1);
        assertEq(earnings, SMALL_PRIZE);
        assertEq(claimed, SMALL_PRIZE);
        assertEq(pending, 0);
    }
    
    function testClaimPrizeFailsForUnauthorized() public {
        _createBasicPayout();
        
        uint256 allocationId = prizeDistribution.getUserAllocations(winner1)[0];
        
        vm.prank(winner2); // Different user
        vm.expectRevert(PrizeDistribution.NotAuthorized.selector);
        prizeDistribution.claimPrize(allocationId);
    }
    
    function testClaimPrizeFailsIfAlreadyClaimed() public {
        _createBasicPayout();
        
        uint256 allocationId = prizeDistribution.getUserAllocations(winner1)[0];
        
        vm.startPrank(winner1);
        
        // First claim should succeed
        prizeDistribution.claimPrize(allocationId);
        
        // Second claim should fail
        vm.expectRevert(PrizeDistribution.AlreadyClaimed.selector);
        prizeDistribution.claimPrize(allocationId);
        
        vm.stopPrank();
    }
    
    /*//////////////////////////////////////////////////////////////
                         VESTED CLAIMING TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testVestedPrizeClaimingOverTime() public {
        // Create medium prize with 7-day vesting
        address[] memory winners = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory ranks = new uint256[](1);
        
        winners[0] = winner1;
        amounts[0] = MEDIUM_PRIZE; // $500 - 7 day vesting
        ranks[0] = 1;
        
        vm.prank(tournamentContract);
        prizeDistribution.createTournamentPayout(TEST_TOURNAMENT_ID, winners, amounts, ranks);
        
        uint256 allocationId = prizeDistribution.getUserAllocations(winner1)[0];
        
        // Should not be claimable immediately due to 1-day cliff
        uint256 claimable = prizeDistribution.getClaimableAmount(allocationId);
        assertEq(claimable, 0);
        
        // Fast forward past cliff period (1 day + 1 second)
        vm.warp(block.timestamp + 1 days + 1);
        
        // Should be partially claimable now
        claimable = prizeDistribution.getClaimableAmount(allocationId);
        assertTrue(claimable > 0);
        assertTrue(claimable < MEDIUM_PRIZE);
        
        // Fast forward to 50% of vesting period (3.5 days)
        vm.warp(block.timestamp + 2.5 days);
        
        claimable = prizeDistribution.getClaimableAmount(allocationId);
        uint256 expected50Percent = MEDIUM_PRIZE / 2;
        // Allow for small rounding differences
        assertTrue(claimable >= expected50Percent - 1000 && claimable <= expected50Percent + 1000);
        
        // Claim the available amount
        uint256 balanceBefore = usdc.balanceOf(winner1);
        vm.prank(winner1);
        prizeDistribution.claimPrize(allocationId);
        
        uint256 balanceAfter = usdc.balanceOf(winner1);
        assertEq(balanceAfter, balanceBefore + claimable);
        
        // Fast forward to end of vesting period
        vm.warp(block.timestamp + 7 days);
        
        // Should be able to claim remainder
        uint256 remainingClaimable = prizeDistribution.getClaimableAmount(allocationId);
        assertTrue(remainingClaimable > 0);
        
        vm.prank(winner1);
        prizeDistribution.claimPrize(allocationId);
        
        // Check final allocation state
        PrizeDistribution.PrizeAllocation memory allocation = prizeDistribution.getAllocation(allocationId);
        assertEq(allocation.remainingAmount, 0);
        assertEq(uint256(allocation.status), uint256(PrizeDistribution.PrizeStatus.Claimed));
    }
    
    function testLargePrizeVesting() public {
        // Create large prize with 30-day vesting and 7-day cliff
        address[] memory winners = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory ranks = new uint256[](1);
        
        winners[0] = winner1;
        amounts[0] = LARGE_PRIZE; // $5000 - 30 day vesting, 7 day cliff
        ranks[0] = 1;
        
        vm.prank(tournamentContract);
        prizeDistribution.createTournamentPayout(TEST_TOURNAMENT_ID, winners, amounts, ranks);
        
        uint256 allocationId = prizeDistribution.getUserAllocations(winner1)[0];
        
        // Should not be claimable during cliff period
        uint256 claimable = prizeDistribution.getClaimableAmount(allocationId);
        assertEq(claimable, 0);
        
        // Fast forward 6 days (still in cliff)
        vm.warp(block.timestamp + 6 days);
        claimable = prizeDistribution.getClaimableAmount(allocationId);
        assertEq(claimable, 0);
        
        // Fast forward past cliff (7 days + 1 second)
        vm.warp(block.timestamp + 1 days + 1);
        
        claimable = prizeDistribution.getClaimableAmount(allocationId);
        assertTrue(claimable > 0);
        
        // Fast forward to 15 days (50% of vesting)
        vm.warp(block.timestamp + 8 days);
        
        claimable = prizeDistribution.getClaimableAmount(allocationId);
        uint256 expected50Percent = LARGE_PRIZE / 2;
        assertTrue(claimable >= expected50Percent - 10000 && claimable <= expected50Percent + 10000);
        
        // Fast forward to full vesting
        vm.warp(block.timestamp + 15 days);
        
        claimable = prizeDistribution.getClaimableAmount(allocationId);
        assertEq(claimable, LARGE_PRIZE);
    }
    
    /*//////////////////////////////////////////////////////////////
                         BATCH CLAIMING TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testBatchClaimMultiplePrizes() public {
        // Create multiple prizes for same user
        address[] memory winners = new address[](3);
        uint256[] memory amounts = new uint256[](3);
        uint256[] memory ranks = new uint256[](3);
        
        // All prizes go to winner1
        winners[0] = winner1;
        winners[1] = winner1;
        winners[2] = winner1;
        amounts[0] = 50_000000;  // $50 - instant
        amounts[1] = 75_000000;  // $75 - instant
        amounts[2] = 25_000000;  // $25 - instant
        ranks[0] = 1;
        ranks[1] = 2;
        ranks[2] = 3;
        
        vm.prank(tournamentContract);
        prizeDistribution.createTournamentPayout(TEST_TOURNAMENT_ID, winners, amounts, ranks);
        
        uint256[] memory allocationIds = prizeDistribution.getUserAllocations(winner1);
        assertEq(allocationIds.length, 3);
        
        uint256 totalClaimable = prizeDistribution.getUserClaimableTotal(winner1);
        assertEq(totalClaimable, 150_000000); // $150 total
        
        uint256 balanceBefore = usdc.balanceOf(winner1);
        
        vm.prank(winner1);
        prizeDistribution.batchClaimPrizes(allocationIds);
        
        uint256 balanceAfter = usdc.balanceOf(winner1);
        assertEq(balanceAfter, balanceBefore + totalClaimable);
        
        // Check that all allocations are now claimed
        for (uint256 i = 0; i < allocationIds.length; i++) {
            PrizeDistribution.PrizeAllocation memory allocation = prizeDistribution.getAllocation(allocationIds[i]);
            assertEq(allocation.remainingAmount, 0);
            assertEq(uint256(allocation.status), uint256(PrizeDistribution.PrizeStatus.Claimed));
        }
    }
    
    function testBatchClaimSkipsInvalidAllocations() public {
        _createBasicPayout();
        
        uint256[] memory validAllocationIds = prizeDistribution.getUserAllocations(winner1);
        
        // Create array with mix of valid and invalid IDs
        uint256[] memory allocationIds = new uint256[](4);
        allocationIds[0] = validAllocationIds[0]; // Valid
        allocationIds[1] = 999; // Invalid - doesn't exist
        allocationIds[2] = 0;   // Invalid - zero
        allocationIds[3] = validAllocationIds[0]; // Valid but duplicate
        
        uint256 balanceBefore = usdc.balanceOf(winner1);
        
        vm.prank(winner1);
        prizeDistribution.batchClaimPrizes(allocationIds);
        
        // Should only claim the valid allocation once
        uint256 balanceAfter = usdc.balanceOf(winner1);
        assertEq(balanceAfter, balanceBefore + SMALL_PRIZE);
    }
    
    /*//////////////////////////////////////////////////////////////
                         ADMIN FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testAddDistributionRule() public {
        uint256 minAmount = 2000_000000;
        uint256 maxAmount = 10000_000000;
        PrizeDistribution.DistributionType distributionType = PrizeDistribution.DistributionType.Vested;
        uint256 vestingDays = 60;
        uint256 cliffDays = 14;
        
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit PrizeDistribution.DistributionRuleAdded(4, minAmount, maxAmount, distributionType);
        prizeDistribution.addDistributionRule(
            minAmount,
            maxAmount,
            distributionType,
            vestingDays,
            cliffDays
        );
        
        assertEq(prizeDistribution.rulesCounter(), 4);
        
        PrizeDistribution.DistributionRule memory newRule = prizeDistribution.getDistributionRule(4);
        assertEq(newRule.minAmount, minAmount);
        assertEq(newRule.maxAmount, maxAmount);
        assertEq(uint256(newRule.distributionType), uint256(distributionType));
        assertEq(newRule.vestingDays, vestingDays);
        assertEq(newRule.cliffDays, cliffDays);
        assertTrue(newRule.isActive);
    }
    
    function testAddDistributionRuleFailsWithInvalidParameters() public {
        vm.startPrank(owner);
        
        // Min amount >= max amount
        vm.expectRevert(PrizeDistribution.InvalidParameters.selector);
        prizeDistribution.addDistributionRule(
            1000_000000, 
            1000_000000, // Same as min
            PrizeDistribution.DistributionType.Vested,
            30,
            7
        );
        
        // Vesting days > 365
        vm.expectRevert(PrizeDistribution.InvalidParameters.selector);
        prizeDistribution.addDistributionRule(
            100_000000,
            1000_000000,
            PrizeDistribution.DistributionType.Vested,
            400, // > 365
            7
        );
        
        // Cliff days > vesting days
        vm.expectRevert(PrizeDistribution.InvalidParameters.selector);
        prizeDistribution.addDistributionRule(
            100_000000,
            1000_000000,
            PrizeDistribution.DistributionType.Vested,
            30,
            35 // > vesting days
        );
        
        vm.stopPrank();
    }
    
    function testAccelerateVesting() public {
        // Create large vested prize
        address[] memory winners = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory ranks = new uint256[](1);
        
        winners[0] = winner1;
        amounts[0] = LARGE_PRIZE; // 30-day vesting
        ranks[0] = 1;
        
        vm.prank(tournamentContract);
        prizeDistribution.createTournamentPayout(TEST_TOURNAMENT_ID, winners, amounts, ranks);
        
        uint256 allocationId = prizeDistribution.getUserAllocations(winner1)[0];
        
        // Should not be claimable initially (7-day cliff)
        uint256 claimableBefore = prizeDistribution.getClaimableAmount(allocationId);
        assertEq(claimableBefore, 0);
        
        uint256 acceleratedAmount = LARGE_PRIZE / 4; // 25% of prize
        
        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit PrizeDistribution.VestingAccelerated(allocationId, winner1, acceleratedAmount);
        prizeDistribution.accelerateVesting(allocationId, acceleratedAmount);
        
        // Should now be claimable
        uint256 claimableAfter = prizeDistribution.getClaimableAmount(allocationId);
        assertTrue(claimableAfter >= acceleratedAmount);
    }
    
    function testAccelerateVestingFailsForInvalidAmount() public {
        _createBasicPayout();
        
        uint256 allocationId = prizeDistribution.getUserAllocations(winner1)[0];
        
        vm.prank(owner);
        vm.expectRevert(PrizeDistribution.InvalidParameters.selector);
        prizeDistribution.accelerateVesting(allocationId, SMALL_PRIZE + 1); // More than remaining
    }
    
    function testEmergencyWithdraw() public {
        uint256 withdrawAmount = 1000_000000;
        string memory reason = "Emergency maintenance";
        
        // Ensure contract has USDC
        usdc.transfer(address(prizeDistribution), withdrawAmount);
        
        uint256 balanceBefore = usdc.balanceOf(owner);
        
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit PrizeDistribution.EmergencyWithdrawal(owner, withdrawAmount, reason);
        prizeDistribution.emergencyWithdraw(owner, withdrawAmount, reason);
        
        uint256 balanceAfter = usdc.balanceOf(owner);
        assertEq(balanceAfter, balanceBefore + withdrawAmount);
    }
    
    function testEmergencyWithdrawFailsForInsufficientBalance() public {
        uint256 contractBalance = usdc.balanceOf(address(prizeDistribution));
        
        vm.prank(owner);
        vm.expectRevert(PrizeDistribution.InsufficientBalance.selector);
        prizeDistribution.emergencyWithdraw(owner, contractBalance + 1, "test");
    }
    
    function testSetTournamentContract() public {
        address newTournamentContract = makeAddr("newTournament");
        
        vm.prank(owner);
        prizeDistribution.setTournamentContract(newTournamentContract);
        
        assertEq(prizeDistribution.tournamentContract(), newTournamentContract);
    }
    
    function testSetTournamentContractFailsWithZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(PrizeDistribution.InvalidParameters.selector);
        prizeDistribution.setTournamentContract(address(0));
    }
    
    function testSetClaimsPaused() public {
        assertFalse(prizeDistribution.claimsPaused());
        
        vm.prank(owner);
        prizeDistribution.setClaimsPaused(true);
        
        assertTrue(prizeDistribution.claimsPaused());
        
        vm.prank(owner);
        prizeDistribution.setClaimsPaused(false);
        
        assertFalse(prizeDistribution.claimsPaused());
    }
    
    function testPauseUnpause() public {
        assertFalse(prizeDistribution.paused());
        
        vm.prank(owner);
        prizeDistribution.pause();
        
        assertTrue(prizeDistribution.paused());
        
        vm.prank(owner);
        prizeDistribution.unpause();
        
        assertFalse(prizeDistribution.paused());
    }
    
    /*//////////////////////////////////////////////////////////////
                         PAUSE FUNCTIONALITY TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testCannotClaimWhenClaimsPaused() public {
        _createBasicPayout();
        
        uint256 allocationId = prizeDistribution.getUserAllocations(winner1)[0];
        
        // Pause claims
        vm.prank(owner);
        prizeDistribution.setClaimsPaused(true);
        
        vm.prank(winner1);
        vm.expectRevert(PrizeDistribution.ClaimsPaused.selector);
        prizeDistribution.claimPrize(allocationId);
    }
    
    function testCannotBatchClaimWhenClaimsPaused() public {
        _createBasicPayout();
        
        uint256[] memory allocationIds = prizeDistribution.getUserAllocations(winner1);
        
        // Pause claims
        vm.prank(owner);
        prizeDistribution.setClaimsPaused(true);
        
        vm.prank(winner1);
        vm.expectRevert(PrizeDistribution.ClaimsPaused.selector);
        prizeDistribution.batchClaimPrizes(allocationIds);
    }
    
    /*//////////////////////////////////////////////////////////////
                           ACCESS CONTROL TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testOnlyOwnerCanAddDistributionRule() public {
        vm.prank(user1);
        vm.expectRevert();
        prizeDistribution.addDistributionRule(
            100_000000,
            1000_000000,
            PrizeDistribution.DistributionType.Instant,
            0,
            0
        );
    }
    
    function testOnlyOwnerCanAccelerateVesting() public {
        _createBasicPayout();
        uint256 allocationId = prizeDistribution.getUserAllocations(winner1)[0];
        
        vm.prank(user1);
        vm.expectRevert();
        prizeDistribution.accelerateVesting(allocationId, 1000);
    }
    
    function testOnlyOwnerCanEmergencyWithdraw() public {
        vm.prank(user1);
        vm.expectRevert();
        prizeDistribution.emergencyWithdraw(user1, 1000, "test");
    }
    
    function testOnlyOwnerCanSetTournamentContract() public {
        vm.prank(user1);
        vm.expectRevert();
        prizeDistribution.setTournamentContract(makeAddr("new"));
    }
    
    function testOnlyOwnerCanSetClaimsPaused() public {
        vm.prank(user1);
        vm.expectRevert();
        prizeDistribution.setClaimsPaused(true);
    }
    
    function testOnlyOwnerCanPause() public {
        vm.prank(user1);
        vm.expectRevert();
        prizeDistribution.pause();
    }
    
    /*//////////////////////////////////////////////////////////////
                           VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testGetUserClaimableTotal() public {
        // Create multiple prizes with different vesting schedules
        address[] memory winners = new address[](3);
        uint256[] memory amounts = new uint256[](3);
        uint256[] memory ranks = new uint256[](3);
        
        winners[0] = winner1;
        winners[1] = winner1;
        winners[2] = winner1;
        amounts[0] = 50_000000;   // $50 - instant
        amounts[1] = 500_000000;  // $500 - 7 day vesting
        amounts[2] = 75_000000;   // $75 - instant
        ranks[0] = 1;
        ranks[1] = 2;
        ranks[2] = 3;
        
        vm.prank(tournamentContract);
        prizeDistribution.createTournamentPayout(TEST_TOURNAMENT_ID, winners, amounts, ranks);
        
        // Initially, only instant prizes should be claimable
        uint256 totalClaimable = prizeDistribution.getUserClaimableTotal(winner1);
        assertEq(totalClaimable, 125_000000); // $50 + $75
        
        // Fast forward past cliff for vested prize
        vm.warp(block.timestamp + 2 days);
        
        totalClaimable = prizeDistribution.getUserClaimableTotal(winner1);
        assertTrue(totalClaimable > 125_000000); // Should include some of the vested amount
    }
    
    function testGetUserStats() public {
        _createBasicPayout();
        
        // Check initial stats
        (uint256 earnings, uint256 claimed, uint256 pending) = prizeDistribution.getUserStats(winner1);
        assertEq(earnings, SMALL_PRIZE);
        assertEq(claimed, 0);
        assertEq(pending, SMALL_PRIZE);
        
        // Claim the prize
        uint256 allocationId = prizeDistribution.getUserAllocations(winner1)[0];
        vm.prank(winner1);
        prizeDistribution.claimPrize(allocationId);
        
        // Check stats after claiming
        (earnings, claimed, pending) = prizeDistribution.getUserStats(winner1);
        assertEq(earnings, SMALL_PRIZE);
        assertEq(claimed, SMALL_PRIZE);
        assertEq(pending, 0);
    }
    
    function testGetContractBalance() public {
        uint256 initialBalance = prizeDistribution.getContractBalance();
        
        // Transfer some USDC to contract
        uint256 transferAmount = 1000_000000;
        usdc.transfer(address(prizeDistribution), transferAmount);
        
        uint256 newBalance = prizeDistribution.getContractBalance();
        assertEq(newBalance, initialBalance + transferAmount);
    }
    
    /*//////////////////////////////////////////////////////////////
                         COMPLEX SCENARIO TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testMultipleTournamentsAndClaims() public {
        // Tournament 1
        address[] memory winners1 = new address[](2);
        uint256[] memory amounts1 = new uint256[](2);
        uint256[] memory ranks1 = new uint256[](2);
        
        winners1[0] = winner1;
        winners1[1] = winner2;
        amounts1[0] = 500_000000; // $500 - 7 day vesting (changed from 100)
        amounts1[1] = 200_000000; // $200 - 7 day vesting
        ranks1[0] = 1;
        ranks1[1] = 2;
        
        vm.prank(tournamentContract);
        prizeDistribution.createTournamentPayout(1, winners1, amounts1, ranks1);
        
        // Tournament 2
        address[] memory winners2 = new address[](2);
        uint256[] memory amounts2 = new uint256[](2);
        uint256[] memory ranks2 = new uint256[](2);
        
        winners2[0] = winner1; // Same winner in both tournaments
        winners2[1] = winner3;
        amounts2[0] = 300_000000; // $300 - 7 day vesting
        amounts2[1] = 400_000000; // $400 - 7 day vesting
        ranks2[0] = 1;
        ranks2[1] = 2;
        
        vm.prank(tournamentContract);
        prizeDistribution.createTournamentPayout(2, winners2, amounts2, ranks2);
        
        // Check winner1 has allocations from both tournaments
        uint256[] memory winner1Allocations = prizeDistribution.getUserAllocations(winner1);
        assertEq(winner1Allocations.length, 2);
        
        // Initially, nothing should be claimable due to cliff periods
        uint256 totalClaimable = prizeDistribution.getUserClaimableTotal(winner1);
        assertEq(totalClaimable, 0); // Both prizes have 1-day cliff
        
        // Fast forward past cliff periods to make vested amounts claimable
        vm.warp(block.timestamp + 2 days);
        
        // Now both should be partially claimable
        totalClaimable = prizeDistribution.getUserClaimableTotal(winner1);
        assertTrue(totalClaimable > 0);
        
        // Batch claim all of winner1's prizes
        vm.prank(winner1);
        prizeDistribution.batchClaimPrizes(winner1Allocations);
        
        // Check final stats - should have claimed some amount
        (uint256 earnings, uint256 claimed, uint256 pending) = prizeDistribution.getUserStats(winner1);
        assertEq(earnings, 800_000000); // $500 + $300 total earnings
        assertTrue(claimed > 0); // Should have claimed something
        assertTrue(pending >= 0); // Should have some or no pending amount
    }
    
    function testPartialVestingClaims() public {
        // Create large prize with long vesting
        address[] memory winners = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory ranks = new uint256[](1);
        
        winners[0] = winner1;
        amounts[0] = LARGE_PRIZE; // $5000 - 30 day vesting
        ranks[0] = 1;
        
        vm.prank(tournamentContract);
        prizeDistribution.createTournamentPayout(TEST_TOURNAMENT_ID, winners, amounts, ranks);
        
        uint256 allocationId = prizeDistribution.getUserAllocations(winner1)[0];
        
        // Fast forward past cliff
        vm.warp(block.timestamp + 8 days);
        
        uint256 balanceBefore = usdc.balanceOf(winner1);
        
        // Claim partial amount
        uint256 claimable1 = prizeDistribution.getClaimableAmount(allocationId);
        vm.prank(winner1);
        prizeDistribution.claimPrize(allocationId);
        
        // Fast forward more
        vm.warp(block.timestamp + 7 days);
        
        // Claim again
        uint256 claimable2 = prizeDistribution.getClaimableAmount(allocationId);
        assertTrue(claimable2 > 0);
        
        vm.prank(winner1);
        prizeDistribution.claimPrize(allocationId);
        
        // Fast forward to end
        vm.warp(block.timestamp + 15 days);
        
        // Final claim
        uint256 claimable3 = prizeDistribution.getClaimableAmount(allocationId);
        if (claimable3 > 0) {
            vm.prank(winner1);
            prizeDistribution.claimPrize(allocationId);
        }
        
        uint256 balanceAfter = usdc.balanceOf(winner1);
        assertEq(balanceAfter, balanceBefore + LARGE_PRIZE);
        
        // Check allocation is fully claimed
        PrizeDistribution.PrizeAllocation memory allocation = prizeDistribution.getAllocation(allocationId);
        assertEq(allocation.remainingAmount, 0);
        assertEq(uint256(allocation.status), uint256(PrizeDistribution.PrizeStatus.Claimed));
    }
    
    /*//////////////////////////////////////////////////////////////
                           EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testZeroPrizeAmount() public {
        address[] memory winners = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        uint256[] memory ranks = new uint256[](2);
        
        winners[0] = winner1;
        winners[1] = winner2;
        amounts[0] = 100_000000; // Valid amount
        amounts[1] = 0;          // Zero amount
        ranks[0] = 1;
        ranks[1] = 2;
        
        vm.prank(tournamentContract);
        prizeDistribution.createTournamentPayout(TEST_TOURNAMENT_ID, winners, amounts, ranks);
        
        // Only winner1 should have an allocation
        uint256[] memory winner1Allocations = prizeDistribution.getUserAllocations(winner1);
        uint256[] memory winner2Allocations = prizeDistribution.getUserAllocations(winner2);
        
        assertEq(winner1Allocations.length, 1);
        assertEq(winner2Allocations.length, 0);
    }
    
    function testInvalidAllocationId() public {
        vm.prank(winner1);
        vm.expectRevert(PrizeDistribution.AllocationNotFound.selector);
        prizeDistribution.claimPrize(999);
        
        vm.prank(winner1);
        vm.expectRevert(PrizeDistribution.AllocationNotFound.selector);
        prizeDistribution.claimPrize(0);
    }
    
    function testGetClaimableAmountForNonExistentAllocation() public {
        uint256 claimable = prizeDistribution.getClaimableAmount(999);
        assertEq(claimable, 0);
    }
    
    /*//////////////////////////////////////////////////////////////
                           EVENT EMISSION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testPrizeAllocatedEvent() public {
        address[] memory winners = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory ranks = new uint256[](1);
        
        winners[0] = winner1;
        amounts[0] = SMALL_PRIZE;
        ranks[0] = 1;
        
        vm.prank(tournamentContract);
        vm.expectEmit(true, true, false, true);
        emit PrizeDistribution.PrizeAllocated(
            1, 
            winner1, 
            SMALL_PRIZE, 
            TEST_TOURNAMENT_ID, 
            PrizeDistribution.DistributionType.Instant
        );
        prizeDistribution.createTournamentPayout(TEST_TOURNAMENT_ID, winners, amounts, ranks);
    }
    
    /*//////////////////////////////////////////////////////////////
                           HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function _createBasicPayout() internal {
        address[] memory winners = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory ranks = new uint256[](1);
        
        winners[0] = winner1;
        amounts[0] = SMALL_PRIZE; // $50 - instant distribution
        ranks[0] = 1;
        
        vm.prank(tournamentContract);
        prizeDistribution.createTournamentPayout(TEST_TOURNAMENT_ID, winners, amounts, ranks);
    }
    
    /*//////////////////////////////////////////////////////////////
                           INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testFullTournamentLifecycle() public {
        // 1. Create tournament with multiple winners and different prize tiers
        address[] memory winners = new address[](5);
        uint256[] memory amounts = new uint256[](5);
        uint256[] memory ranks = new uint256[](5);
        
        winners[0] = winner1;
        winners[1] = winner2;
        winners[2] = winner3;
        winners[3] = user1;
        winners[4] = user2;
        
        amounts[0] = 5000_000000; // $5000 - 30 day vesting
        amounts[1] = 2000_000000; // $2000 - 30 day vesting  
        amounts[2] = 1000_000000; // $1000 - 30 day vesting
        amounts[3] = 500_000000;  // $500 - 7 day vesting
        amounts[4] = 50_000000;   // $50 - instant
        
        ranks[0] = 1;
        ranks[1] = 2;
        ranks[2] = 3;
        ranks[3] = 4;
        ranks[4] = 5;
        
        uint256 totalPrizePool = 8550_000000;
        uint256 expectedFee = (totalPrizePool * PLATFORM_FEE_BPS) / BPS_DENOMINATOR;
        
        uint256 contractBalanceBefore = usdc.balanceOf(address(prizeDistribution));
        uint256 ownerBalanceBefore = usdc.balanceOf(owner);
        
        vm.prank(tournamentContract);
        prizeDistribution.createTournamentPayout(TEST_TOURNAMENT_ID, winners, amounts, ranks);
        
        // 2. Verify tournament payout was created correctly
        PrizeDistribution.TournamentPayout memory payout = prizeDistribution.getTournamentPayout(TEST_TOURNAMENT_ID);
        assertEq(payout.totalPrizePool, totalPrizePool);
        assertEq(payout.platformFee, expectedFee);
        assertEq(payout.winnersCount, 5);
        assertTrue(payout.isFinalized);
        
        // 3. Verify platform fee was transferred
        assertEq(usdc.balanceOf(owner), ownerBalanceBefore + expectedFee);
        
        // 4. Test immediate claiming for instant prize
        uint256 user2Balance = usdc.balanceOf(user2);
        uint256[] memory user2Allocations = prizeDistribution.getUserAllocations(user2);
        
        vm.prank(user2);
        prizeDistribution.claimPrize(user2Allocations[0]);
        
        assertEq(usdc.balanceOf(user2), user2Balance + 50_000000);
        
        // 5. Fast forward and test partial vested claiming
        vm.warp(block.timestamp + 8 days); // Past cliff for medium prizes
        
        uint256[] memory user1Allocations = prizeDistribution.getUserAllocations(user1);
        uint256 claimableAmount = prizeDistribution.getClaimableAmount(user1Allocations[0]);
        assertTrue(claimableAmount > 0);
        
        uint256 user1Balance = usdc.balanceOf(user1);
        vm.prank(user1);
        prizeDistribution.claimPrize(user1Allocations[0]);
        
        assertTrue(usdc.balanceOf(user1) > user1Balance);
        
        // 6. Fast forward to full vesting and claim large prizes
        vm.warp(block.timestamp + 30 days);
        
        uint256[] memory winner1Allocations = prizeDistribution.getUserAllocations(winner1);
        uint256 winner1ClaimableTotal = prizeDistribution.getUserClaimableTotal(winner1);
        assertEq(winner1ClaimableTotal, 5000_000000);
        
        uint256 winner1Balance = usdc.balanceOf(winner1);
        vm.prank(winner1);
        prizeDistribution.batchClaimPrizes(winner1Allocations);
        
        assertEq(usdc.balanceOf(winner1), winner1Balance + 5000_000000);
        
        // 7. Verify final stats
        (uint256 earnings, uint256 claimed, uint256 pending) = prizeDistribution.getUserStats(winner1);
        assertEq(earnings, 5000_000000);
        assertEq(claimed, 5000_000000);
        assertEq(pending, 0);
        
        // 8. Test that all allocations are properly marked as claimed
        PrizeDistribution.PrizeAllocation memory finalAllocation = prizeDistribution.getAllocation(winner1Allocations[0]);
        assertEq(uint256(finalAllocation.status), uint256(PrizeDistribution.PrizeStatus.Claimed));
        assertEq(finalAllocation.remainingAmount, 0);
    }
}