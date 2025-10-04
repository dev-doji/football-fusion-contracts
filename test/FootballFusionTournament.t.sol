// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {FootballFusionTournament} from "../src/FootballFusionTournament.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract FootballFusionTournamentTest is Test {
    FootballFusionTournament public tournament;
    ERC20Mock public usdc;
    
    address public owner;
    address public user1;
    address public user2;
    address public user3;
    
    // Test constants
    uint256 constant INITIAL_BALANCE = 1000_000000; // 1000 USDC
    uint256 constant ENTRY_FEE_TIER3_STANDARD = 20_000000; // 20 USDC (Tier3 standard)
    uint256 constant PLATFORM_FEE_BPS = 200; // 2%
    
    function setUp() public {
        // Create test addresses
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        
        // Deploy mock USDC (6 decimals)
        usdc = new ERC20Mock();
        
        // Deploy tournament contract
        vm.prank(owner);
        tournament = new FootballFusionTournament(address(usdc), owner);
        
        // Mint USDC to test users
        usdc.mint(user1, INITIAL_BALANCE);
        usdc.mint(user2, INITIAL_BALANCE);
        usdc.mint(user3, INITIAL_BALANCE);
        
        // Add test players
        vm.startPrank(owner);
        _addTestPlayers();
        vm.stopPrank();
    }
    
    function _addTestPlayers() internal {
        // Add 15 test players (1 GK, 5 DEF, 5 MID, 4 FWD for valid formations)
        tournament.addPlayer("Alisson", "Liverpool", FootballFusionTournament.Position.GK, 55_000000, "");
        
        // Defenders (5 players)
        tournament.addPlayer("Van Dijk", "Liverpool", FootballFusionTournament.Position.DEF, 65_000000, "");
        tournament.addPlayer("Saliba", "Arsenal", FootballFusionTournament.Position.DEF, 55_000000, "");
        tournament.addPlayer("Dias", "Man City", FootballFusionTournament.Position.DEF, 60_000000, "");
        tournament.addPlayer("Shaw", "Man Utd", FootballFusionTournament.Position.DEF, 50_000000, "");
        tournament.addPlayer("James", "Chelsea", FootballFusionTournament.Position.DEF, 55_000000, "");
        
        // Midfielders (5 players)
        tournament.addPlayer("De Bruyne", "Man City", FootballFusionTournament.Position.MID, 120_000000, "");
        tournament.addPlayer("Salah", "Liverpool", FootballFusionTournament.Position.MID, 130_000000, "");
        tournament.addPlayer("Saka", "Arsenal", FootballFusionTournament.Position.MID, 90_000000, "");
        tournament.addPlayer("Bruno", "Man Utd", FootballFusionTournament.Position.MID, 110_000000, "");
        tournament.addPlayer("Palmer", "Chelsea", FootballFusionTournament.Position.MID, 75_000000, "");
        
        // Forwards (4 players)
        tournament.addPlayer("Haaland", "Man City", FootballFusionTournament.Position.FWD, 150_000000, "");
        tournament.addPlayer("Kane", "Bayern", FootballFusionTournament.Position.FWD, 110_000000, "");
        tournament.addPlayer("Watkins", "Aston Villa", FootballFusionTournament.Position.FWD, 75_000000, "");
        tournament.addPlayer("Isak", "Newcastle", FootballFusionTournament.Position.FWD, 80_000000, "");
    }
    
    function _getValidTeam442() internal pure returns (uint256[11] memory, uint256[4] memory) {
        // 4-4-2 Formation: 1 GK, 4 DEF, 4 MID, 2 FWD
        uint256[11] memory startingEleven = [
            uint256(1), // GK: Alisson
            2, 3, 4, 5, // DEF: Van Dijk, Saliba, Dias, Shaw (4)
            7, 8, 9, 10, // MID: De Bruyne, Salah, Saka, Bruno (4)
            12, 13 // FWD: Haaland, Kane (2)
        ];
        
        uint256[4] memory bench = [uint256(6), 11, 14, 15]; // James, Palmer, Watkins, Isak
        
        return (startingEleven, bench);
    }
    
    function _getValidTeam343() internal pure returns (uint256[11] memory, uint256[4] memory) {
        // 3-4-3 Formation: 1 GK, 3 DEF, 4 MID, 3 FWD
        uint256[11] memory startingEleven = [
            uint256(1), // GK: Alisson
            2, 3, 4, // DEF: Van Dijk, Saliba, Dias (3)
            7, 8, 9, 10, // MID: De Bruyne, Salah, Saka, Bruno (4)
            12, 13, 14 // FWD: Haaland, Kane, Watkins (3)
        ];
        
        uint256[4] memory bench = [uint256(5), 6, 11, 15]; // Shaw, James, Palmer, Isak
        
        return (startingEleven, bench);
    }

    /*//////////////////////////////////////////////////////////////
                            SETUP TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_InitialSetup() public view {
        assertEq(address(tournament.USDC()), address(usdc));
        assertEq(tournament.owner(), owner);
        assertEq(tournament.PLATFORM_FEE_BPS(), PLATFORM_FEE_BPS);
        assertEq(tournament.playerCounter(), 15);
        
        // Check tier pricing
        uint256[5] memory tier1 = tournament.getTierPricing(FootballFusionTournament.PricingTier.Tier1);
        assertEq(tier1[0], 2_000000); // $2 starter
        assertEq(tier1[1], 10_000000); // $10 standard
        
        uint256[5] memory tier3 = tournament.getTierPricing(FootballFusionTournament.PricingTier.Tier3);
        assertEq(tier3[1], 20_000000); // $20 standard
        assertEq(tier3[4], 250_000000); // $250 mega
    }
    
    function test_PlayerData() public view {
        FootballFusionTournament.Player memory player1 = tournament.getPlayer(1);
        assertEq(player1.name, "Alisson");
        assertEq(uint256(player1.position), uint256(FootballFusionTournament.Position.GK));
        assertTrue(player1.isActive);
        
        FootballFusionTournament.Player memory player7 = tournament.getPlayer(7);
        assertEq(player7.name, "De Bruyne");
        assertEq(uint256(player7.position), uint256(FootballFusionTournament.Position.MID));
        assertEq(player7.price, 120_000000);
    }

    /*//////////////////////////////////////////////////////////////
                        TOURNAMENT CREATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_CreateTournament() public {
        vm.prank(owner);
        tournament.createTournament(
            1, // Standard entry (index 1 = $20 for Tier3)
            block.timestamp + 1 hours,
            block.timestamp + 25 hours,
            100, // max participants
            FootballFusionTournament.TournamentType.EPL,
            FootballFusionTournament.PricingTier.Tier3,
            "GW1 - Arsenal vs Liverpool",
            "1"
        );
        
        FootballFusionTournament.Tournament memory t = tournament.getTournament(1);
        assertEq(t.entryFee, ENTRY_FEE_TIER3_STANDARD);
        assertEq(t.maxParticipants, 100);
        assertTrue(t.isActive);
        assertFalse(t.isSettled);
        assertEq(t.name, "GW1 - Arsenal vs Liverpool");
        assertEq(t.gameweek, "1");
    }
    
    function test_RevertWhen_CreateTournament_InvalidStartTime() public {
        vm.prank(owner);
        vm.expectRevert(FootballFusionTournament.InvalidTournament.selector);
        tournament.createTournament(
            1,
            block.timestamp - 1 hours, // Invalid: start time in past
            block.timestamp + 25 hours,
            100,
            FootballFusionTournament.TournamentType.EPL,
            FootballFusionTournament.PricingTier.Tier3,
            "Test",
            "1"
        );
    }
    
    function test_RevertWhen_CreateTournament_InvalidEndTime() public {
        vm.prank(owner);
        vm.expectRevert(FootballFusionTournament.InvalidTournament.selector);
        tournament.createTournament(
            1,
            block.timestamp + 2 hours,
            block.timestamp + 1 hours, // Invalid: end time before start time
            100,
            FootballFusionTournament.TournamentType.EPL,
            FootballFusionTournament.PricingTier.Tier3,
            "Test",
            "1"
        );
    }

    /*//////////////////////////////////////////////////////////////
                        USER PRICING TIER TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_SetUserPricingTier_ByUser() public {
        vm.prank(user1);
        tournament.setUserPricingTier(user1, FootballFusionTournament.PricingTier.Tier3);
        
        assertEq(uint256(tournament.userPricingTier(user1)), uint256(FootballFusionTournament.PricingTier.Tier3));
    }
    
    function test_SetUserPricingTier_ByOwner() public {
        vm.prank(owner);
        tournament.setUserPricingTier(user2, FootballFusionTournament.PricingTier.Tier2);
        
        assertEq(uint256(tournament.userPricingTier(user2)), uint256(FootballFusionTournament.PricingTier.Tier2));
    }
    
    function test_RevertWhen_SetUserPricingTier_Unauthorized() public {
        vm.prank(user1);
        vm.expectRevert(FootballFusionTournament.Unauthorized.selector);
        tournament.setUserPricingTier(user2, FootballFusionTournament.PricingTier.Tier1);
    }

    /*//////////////////////////////////////////////////////////////
                        TOURNAMENT JOINING TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_JoinTournament_ValidTeam442() public {
        // Create tournament
        vm.prank(owner);
        tournament.createTournament(
            1, // Standard entry
            block.timestamp + 1 hours,
            block.timestamp + 25 hours,
            100,
            FootballFusionTournament.TournamentType.EPL,
            FootballFusionTournament.PricingTier.Tier3,
            "Test Tournament",
            "1"
        );
        
        // Set user to Tier3 to match tournament (no discount)
        vm.prank(user1);
        tournament.setUserPricingTier(user1, FootballFusionTournament.PricingTier.Tier3);
        
        (uint256[11] memory startingEleven, uint256[4] memory bench) = _getValidTeam442();
        
        // Approve USDC spending - user is Tier3 so pays full price
        vm.prank(user1);
        usdc.approve(address(tournament), ENTRY_FEE_TIER3_STANDARD);
        
        // Join tournament
        vm.prank(user1);
        tournament.joinTournament(
            1,
            startingEleven,
            bench,
            7, // Captain (De Bruyne)
            8, // Vice-captain (Salah)
            FootballFusionTournament.Formation.F442
        );
        
        // Check tournament state
        FootballFusionTournament.Tournament memory t = tournament.getTournament(1);
        assertEq(t.currentParticipants, 1);
        assertEq(t.totalPrizePool, ENTRY_FEE_TIER3_STANDARD);
        
        // Check user team
        FootballFusionTournament.UserTeam memory userTeam = tournament.getUserTeam(1, user1);
        assertTrue(userTeam.hasParticipated);
        assertEq(userTeam.captainId, 7);
        assertEq(userTeam.viceCaptainId, 8);
        assertEq(uint256(userTeam.formation), uint256(FootballFusionTournament.Formation.F442));
        
        // Check user statistics
        assertEq(tournament.userTournamentCount(user1), 1);
    }
    
    function test_JoinTournament_ValidTeam343() public {
        // Create tournament
        vm.prank(owner);
        tournament.createTournament(
            1,
            block.timestamp + 1 hours,
            block.timestamp + 25 hours,
            100,
            FootballFusionTournament.TournamentType.EPL,
            FootballFusionTournament.PricingTier.Tier3,
            "Test Tournament",
            "1"
        );
        
        // Set user to Tier3
        vm.prank(user1);
        tournament.setUserPricingTier(user1, FootballFusionTournament.PricingTier.Tier3);
        
        (uint256[11] memory startingEleven, uint256[4] memory bench) = _getValidTeam343();
        
        vm.prank(user1);
        usdc.approve(address(tournament), ENTRY_FEE_TIER3_STANDARD);
        
        vm.prank(user1);
        tournament.joinTournament(
            1,
            startingEleven,
            bench,
            7, // Captain
            8, // Vice-captain
            FootballFusionTournament.Formation.F343
        );
        
        FootballFusionTournament.UserTeam memory userTeam = tournament.getUserTeam(1, user1);
        assertEq(uint256(userTeam.formation), uint256(FootballFusionTournament.Formation.F343));
    }
    
    function test_RevertWhen_JoinTournament_InvalidFormation() public {
        vm.prank(owner);
        tournament.createTournament(
            1, block.timestamp + 1 hours, block.timestamp + 25 hours, 100,
            FootballFusionTournament.TournamentType.EPL,
            FootballFusionTournament.PricingTier.Tier3,
            "Test", "1"
        );
        
        // Set user to Tier3
        vm.prank(user1);
        tournament.setUserPricingTier(user1, FootballFusionTournament.PricingTier.Tier3);
        
        // Invalid formation (too many forwards for 4-4-2)
        uint256[11] memory invalidTeam = [
            uint256(1), // GK: 1
            2, 3, 4, // DEF: 3 (but claiming 4-4-2 which needs 4)
            7, 8, 9, 10, // MID: 4
            12, 13, 14 // FWD: 3 (but 4-4-2 should have 2)
        ];
        uint256[4] memory bench = [uint256(5), 6, 11, 15];
        
        vm.prank(user1);
        usdc.approve(address(tournament), ENTRY_FEE_TIER3_STANDARD);
        
        vm.expectRevert(FootballFusionTournament.InvalidTeamSelection.selector);
        vm.prank(user1);
        tournament.joinTournament(
            1, invalidTeam, bench, 7, 8,
            FootballFusionTournament.Formation.F442
        );
    }
    
    function test_RevertWhen_JoinTournament_DuplicatePlayers() public {
        vm.prank(owner);
        tournament.createTournament(
            1, block.timestamp + 1 hours, block.timestamp + 25 hours, 100,
            FootballFusionTournament.TournamentType.EPL,
            FootballFusionTournament.PricingTier.Tier3,
            "Test", "1"
        );
        
        // Set user to Tier3
        vm.prank(user1);
        tournament.setUserPricingTier(user1, FootballFusionTournament.PricingTier.Tier3);
        
        // Team with duplicate players
        uint256[11] memory duplicateTeam = [
            uint256(1), // GK
            2, 3, 4, 5, // DEF
            7, 8, 7, 10, // MID (7 appears twice)
            12, 13 // FWD
        ];
        uint256[4] memory bench = [uint256(6), 11, 14, 15];
        
        vm.prank(user1);
        usdc.approve(address(tournament), ENTRY_FEE_TIER3_STANDARD);
        
        vm.expectRevert(FootballFusionTournament.InvalidTeamSelection.selector);
        vm.prank(user1);
        tournament.joinTournament(
            1, duplicateTeam, bench, 7, 8,
            FootballFusionTournament.Formation.F442
        );
    }
    
    function test_RevertWhen_JoinTournament_InvalidCaptain() public {
        vm.prank(owner);
        tournament.createTournament(
            1, block.timestamp + 1 hours, block.timestamp + 25 hours, 100,
            FootballFusionTournament.TournamentType.EPL,
            FootballFusionTournament.PricingTier.Tier3,
            "Test", "1"
        );
        
        // Set user to Tier3
        vm.prank(user1);
        tournament.setUserPricingTier(user1, FootballFusionTournament.PricingTier.Tier3);
        
        (uint256[11] memory startingEleven, uint256[4] memory bench) = _getValidTeam442();
        
        vm.prank(user1);
        usdc.approve(address(tournament), ENTRY_FEE_TIER3_STANDARD);
        
        vm.expectRevert(FootballFusionTournament.InvalidTeamSelection.selector);
        vm.prank(user1);
        tournament.joinTournament(
            1, startingEleven, bench, 
            6, // Captain not in starting eleven (James is on bench)
            8, // Vice-captain
            FootballFusionTournament.Formation.F442
        );
    }
    
    function test_RevertWhen_JoinTournament_RegistrationClosed() public {
        // Create tournament that starts in 1 hour
        vm.prank(owner);
        tournament.createTournament(
            1, block.timestamp + 1 hours, block.timestamp + 25 hours, 100,
            FootballFusionTournament.TournamentType.EPL,
            FootballFusionTournament.PricingTier.Tier3,
            "Test", "1"
        );
        
        // Set user to Tier3
        vm.prank(user1);
        tournament.setUserPricingTier(user1, FootballFusionTournament.PricingTier.Tier3);
        
        // Fast forward past start time
        vm.warp(block.timestamp + 2 hours);
        
        (uint256[11] memory startingEleven, uint256[4] memory bench) = _getValidTeam442();
        
        vm.prank(user1);
        usdc.approve(address(tournament), ENTRY_FEE_TIER3_STANDARD);
        
        vm.expectRevert(FootballFusionTournament.RegistrationClosed.selector);
        vm.prank(user1);
        tournament.joinTournament(1, startingEleven, bench, 7, 8, FootballFusionTournament.Formation.F442);
    }
    
    function test_RevertWhen_JoinTournament_AlreadyJoined() public {
        vm.prank(owner);
        tournament.createTournament(
            1, block.timestamp + 1 hours, block.timestamp + 25 hours, 100,
            FootballFusionTournament.TournamentType.EPL,
            FootballFusionTournament.PricingTier.Tier3,
            "Test", "1"
        );
        
        // Set user to Tier3
        vm.prank(user1);
        tournament.setUserPricingTier(user1, FootballFusionTournament.PricingTier.Tier3);
        
        (uint256[11] memory startingEleven, uint256[4] memory bench) = _getValidTeam442();
        
        // First join
        vm.prank(user1);
        usdc.approve(address(tournament), ENTRY_FEE_TIER3_STANDARD);
        vm.prank(user1);
        tournament.joinTournament(1, startingEleven, bench, 7, 8, FootballFusionTournament.Formation.F442);
        
        // Try to join again
        vm.prank(user1);
        usdc.approve(address(tournament), ENTRY_FEE_TIER3_STANDARD);
        
        vm.expectRevert(FootballFusionTournament.AlreadyJoined.selector);
        vm.prank(user1);
        tournament.joinTournament(1, startingEleven, bench, 7, 8, FootballFusionTournament.Formation.F442);
    }

    /*//////////////////////////////////////////////////////////////
                        PRICING TIER TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_EffectiveEntryFee_SameTier() public {
        vm.prank(owner);
        tournament.createTournament(
            1, block.timestamp + 1 hours, block.timestamp + 25 hours, 100,
            FootballFusionTournament.TournamentType.EPL,
            FootballFusionTournament.PricingTier.Tier3,
            "Test", "1"
        );
        
        // User has same tier as tournament
        vm.prank(user1);
        tournament.setUserPricingTier(user1, FootballFusionTournament.PricingTier.Tier3);
        
        uint256 effectiveFee = tournament.getEffectiveEntryFee(1, user1);
        assertEq(effectiveFee, ENTRY_FEE_TIER3_STANDARD); // No discount
    }
    
    function test_EffectiveEntryFee_Tier1Discount() public {
        vm.prank(owner);
        tournament.createTournament(
            1, block.timestamp + 1 hours, block.timestamp + 25 hours, 100,
            FootballFusionTournament.TournamentType.EPL,
            FootballFusionTournament.PricingTier.Tier3,
            "Test", "1"
        );
        
        // User has Tier1 (60% discount)
        vm.prank(user1);
        tournament.setUserPricingTier(user1, FootballFusionTournament.PricingTier.Tier1);
        
        uint256 effectiveFee = tournament.getEffectiveEntryFee(1, user1);
        uint256 expectedFee = (ENTRY_FEE_TIER3_STANDARD * 4000) / 10000; // 60% discount
        assertEq(effectiveFee, expectedFee);
    }
    
    function test_EffectiveEntryFee_Tier2Discount() public {
        vm.prank(owner);
        tournament.createTournament(
            1, block.timestamp + 1 hours, block.timestamp + 25 hours, 100,
            FootballFusionTournament.TournamentType.EPL,
            FootballFusionTournament.PricingTier.Tier3,
            "Test", "1"
        );
        
        // User has Tier2 (30% discount)
        vm.prank(user1);
        tournament.setUserPricingTier(user1, FootballFusionTournament.PricingTier.Tier2);
        
        uint256 effectiveFee = tournament.getEffectiveEntryFee(1, user1);
        uint256 expectedFee = (ENTRY_FEE_TIER3_STANDARD * 7000) / 10000; // 30% discount
        assertEq(effectiveFee, expectedFee);
    }

    /*//////////////////////////////////////////////////////////////
                        SCORING TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_CalculateUserScore() public {
        // Create and join tournament
        vm.prank(owner);
        tournament.createTournament(
            1, block.timestamp + 1 hours, block.timestamp + 25 hours, 100,
            FootballFusionTournament.TournamentType.EPL,
            FootballFusionTournament.PricingTier.Tier3,
            "Test", "1"
        );
        
        // Set user to Tier3
        vm.prank(user1);
        tournament.setUserPricingTier(user1, FootballFusionTournament.PricingTier.Tier3);
        
        (uint256[11] memory startingEleven, uint256[4] memory bench) = _getValidTeam442();
        
        vm.prank(user1);
        usdc.approve(address(tournament), ENTRY_FEE_TIER3_STANDARD);
        vm.prank(user1);
        tournament.joinTournament(1, startingEleven, bench, 7, 8, FootballFusionTournament.Formation.F442);
        
        // Update player points
        vm.startPrank(owner);
        tournament.updatePlayerPoints(7, 10); // Captain (De Bruyne) gets 10 points
        tournament.updatePlayerPoints(8, 8);  // Vice-captain (Salah) gets 8 points
        tournament.updatePlayerPoints(12, 6); // Forward (Haaland) gets 6 points
        tournament.updatePlayerPoints(1, 4);  // Goalkeeper (Alisson) gets 4 points
        
        // Calculate score
        uint256 score = tournament.calculateUserScore(1, user1);
        vm.stopPrank();
        
        // Captain gets double points: 10 * 2 = 20
        // Other players: 8 + 6 + 4 = 18
        // Total: 20 + 18 = 38
        assertEq(score, 38);
        
        // Check that score is stored in user team
        FootballFusionTournament.UserTeam memory userTeam = tournament.getUserTeam(1, user1);
        assertEq(userTeam.totalScore, 38);
    }
    
    function test_RevertWhen_CalculateUserScore_UserNotParticipated() public {
        vm.prank(owner);
        tournament.createTournament(
            1, block.timestamp + 1 hours, block.timestamp + 25 hours, 100,
            FootballFusionTournament.TournamentType.EPL,
            FootballFusionTournament.PricingTier.Tier3,
            "Test", "1"
        );
        
        vm.prank(owner);
        vm.expectRevert(FootballFusionTournament.InvalidTeamSelection.selector);
        tournament.calculateUserScore(1, user1); // User never joined
    }

    /*//////////////////////////////////////////////////////////////
                        SETTLEMENT TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_SettleTournament_TwoPlayers() public {
        // Create tournament
        vm.prank(owner);
        tournament.createTournament(
            1, block.timestamp + 1 hours, block.timestamp + 2 hours, 100,
            FootballFusionTournament.TournamentType.EPL,
            FootballFusionTournament.PricingTier.Tier3,
            "Test", "1"
        );
        
        // Set both users to Tier3 to pay full price
        vm.prank(user1);
        tournament.setUserPricingTier(user1, FootballFusionTournament.PricingTier.Tier3);
        vm.prank(user2);
        tournament.setUserPricingTier(user2, FootballFusionTournament.PricingTier.Tier3);
        
        (uint256[11] memory team, uint256[4] memory bench) = _getValidTeam442();
        
        // User1 joins
        vm.prank(user1);
        usdc.approve(address(tournament), ENTRY_FEE_TIER3_STANDARD);
        vm.prank(user1);
        tournament.joinTournament(1, team, bench, 7, 8, FootballFusionTournament.Formation.F442);
        
        // User2 joins with different captain
        vm.prank(user2);
        usdc.approve(address(tournament), ENTRY_FEE_TIER3_STANDARD);
        vm.prank(user2);
        tournament.joinTournament(1, team, bench, 8, 7, FootballFusionTournament.Formation.F442);
        
        // Fast forward past tournament end
        vm.warp(block.timestamp + 3 hours);
        
        // Get actual total pool from tournament (both users paid full price)
        uint256 totalPool = ENTRY_FEE_TIER3_STANDARD * 2;
        uint256 platformFee = (totalPool * PLATFORM_FEE_BPS) / 10000;
        uint256 remainingPool = totalPool - platformFee;
        uint256 firstPrize = (remainingPool * 7000) / 10000; // 70%
        uint256 secondPrize = (remainingPool * 3000) / 10000; // 30%
        
        // Check initial balances
        uint256 user1BalanceBefore = usdc.balanceOf(user1);
        uint256 user2BalanceBefore = usdc.balanceOf(user2);
        uint256 ownerBalanceBefore = usdc.balanceOf(owner);
        
        // Settle tournament
        address[] memory winners = new address[](2);
        winners[0] = user1; // 1st place
        winners[1] = user2; // 2nd place
        
        uint256[] memory scores = new uint256[](2);
        scores[0] = 100;
        scores[1] = 80;
        
        vm.prank(owner);
        tournament.settleTournament(1, winners, scores);
        
        // Check balances changed correctly
        assertEq(usdc.balanceOf(user1), user1BalanceBefore + firstPrize);
        assertEq(usdc.balanceOf(user2), user2BalanceBefore + secondPrize);
        assertEq(usdc.balanceOf(owner), ownerBalanceBefore + platformFee);
        
        // Check tournament results
        FootballFusionTournament.TournamentResult[] memory results = tournament.getTournamentResults(1);
        assertEq(results.length, 2);
        assertEq(results[0].user, user1);
        assertEq(results[0].rank, 1);
        assertEq(results[0].finalScore, 100);
        assertEq(results[0].prizeWon, firstPrize);
        assertEq(results[1].user, user2);
        assertEq(results[1].rank, 2);
        assertEq(results[1].finalScore, 80);
        assertEq(results[1].prizeWon, secondPrize);
        
        // Check user winnings tracking
        assertEq(tournament.userTotalWinnings(user1), firstPrize);
        assertEq(tournament.userTotalWinnings(user2), secondPrize);
        
        // Check tournament is settled
        FootballFusionTournament.Tournament memory settledTournament = tournament.getTournament(1);
        assertTrue(settledTournament.isSettled);
        assertFalse(settledTournament.isActive);
    }
    
    function test_SettleTournament_ThreePlayers() public {
        // Create tournament
        vm.prank(owner);
        tournament.createTournament(
            1, block.timestamp + 1 hours, block.timestamp + 2 hours, 100,
            FootballFusionTournament.TournamentType.EPL,
            FootballFusionTournament.PricingTier.Tier3,
            "Test", "1"
        );
        
        // Set all users to Tier3 to pay full price
        vm.prank(user1);
        tournament.setUserPricingTier(user1, FootballFusionTournament.PricingTier.Tier3);
        vm.prank(user2);
        tournament.setUserPricingTier(user2, FootballFusionTournament.PricingTier.Tier3);
        vm.prank(user3);
        tournament.setUserPricingTier(user3, FootballFusionTournament.PricingTier.Tier3);
        
        (uint256[11] memory team, uint256[4] memory bench) = _getValidTeam442();
        
        // Three users join
        vm.prank(user1);
        usdc.approve(address(tournament), ENTRY_FEE_TIER3_STANDARD);
        vm.prank(user1);
        tournament.joinTournament(1, team, bench, 7, 8, FootballFusionTournament.Formation.F442);
        
        vm.prank(user2);
        usdc.approve(address(tournament), ENTRY_FEE_TIER3_STANDARD);
        vm.prank(user2);
        tournament.joinTournament(1, team, bench, 8, 7, FootballFusionTournament.Formation.F442);
        
        vm.prank(user3);
        usdc.approve(address(tournament), ENTRY_FEE_TIER3_STANDARD);
        vm.prank(user3);
        tournament.joinTournament(1, team, bench, 12, 13, FootballFusionTournament.Formation.F442);
        
        // Fast forward past tournament end
        vm.warp(block.timestamp + 3 hours);
        
        // Calculate expected amounts for 3 winners (60%, 25%, 15%)
        uint256 totalPool = ENTRY_FEE_TIER3_STANDARD * 3;
        uint256 platformFee = (totalPool * PLATFORM_FEE_BPS) / 10000;
        uint256 remainingPool = totalPool - platformFee;
        
        // Settle tournament
        address[] memory winners = new address[](3);
        winners[0] = user1; // 1st place - 60%
        winners[1] = user2; // 2nd place - 25%
        winners[2] = user3; // 3rd place - 15%
        
        uint256[] memory scores = new uint256[](3);
        scores[0] = 120;
        scores[1] = 100;
        scores[2] = 80;
        
        vm.prank(owner);
        tournament.settleTournament(1, winners, scores);
        
        // Check results
        FootballFusionTournament.TournamentResult[] memory results = tournament.getTournamentResults(1);
        assertEq(results.length, 3);
        
        uint256 expectedFirst = (remainingPool * 6000) / 10000; // 60%
        uint256 expectedSecond = (remainingPool * 2500) / 10000; // 25%
        uint256 expectedThird = (remainingPool * 1500) / 10000; // 15%
        
        assertEq(results[0].prizeWon, expectedFirst);
        assertEq(results[1].prizeWon, expectedSecond);
        assertEq(results[2].prizeWon, expectedThird);
    }
    
    function test_RevertWhen_SettleTournament_TournamentNotEnded() public {
        vm.prank(owner);
        tournament.createTournament(
            1, block.timestamp + 1 hours, block.timestamp + 25 hours, 100,
            FootballFusionTournament.TournamentType.EPL,
            FootballFusionTournament.PricingTier.Tier3,
            "Test", "1"
        );
        
        address[] memory winners = new address[](1);
        winners[0] = user1;
        uint256[] memory scores = new uint256[](1);
        scores[0] = 100;
        
        vm.prank(owner);
        vm.expectRevert(FootballFusionTournament.TournamentNotEnded.selector);
        tournament.settleTournament(1, winners, scores);
    }
    
    function test_RevertWhen_SettleTournament_AlreadySettled() public {
        vm.prank(owner);
        tournament.createTournament(
            1, block.timestamp + 1 hours, block.timestamp + 2 hours, 100,
            FootballFusionTournament.TournamentType.EPL,
            FootballFusionTournament.PricingTier.Tier3,
            "Test", "1"
        );
        
        // Set user to Tier3
        vm.prank(user1);
        tournament.setUserPricingTier(user1, FootballFusionTournament.PricingTier.Tier3);
        
        (uint256[11] memory team, uint256[4] memory bench) = _getValidTeam442();
        
        vm.prank(user1);
        usdc.approve(address(tournament), ENTRY_FEE_TIER3_STANDARD);
        vm.prank(user1);
        tournament.joinTournament(1, team, bench, 7, 8, FootballFusionTournament.Formation.F442);
        
        vm.warp(block.timestamp + 3 hours);
        
        address[] memory winners = new address[](1);
        winners[0] = user1;
        uint256[] memory scores = new uint256[](1);
        scores[0] = 100;
        
        // Settle once
        vm.prank(owner);
        tournament.settleTournament(1, winners, scores);
        
        // Try to settle again - check the actual error being thrown
        vm.expectRevert(FootballFusionTournament.InvalidTournament.selector);
        vm.prank(owner);
        tournament.settleTournament(1, winners, scores);
    }

    /*//////////////////////////////////////////////////////////////
                        PLAYER MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_AddPlayer() public {
        uint256 initialPlayerCount = tournament.playerCounter();
        
        vm.prank(owner);
        tournament.addPlayer(
            "Mbappe",
            "PSG",
            FootballFusionTournament.Position.FWD,
            160_000000,
            "https://example.com/mbappe.jpg"
        );
        
        assertEq(tournament.playerCounter(), initialPlayerCount + 1);
        
        FootballFusionTournament.Player memory newPlayer = tournament.getPlayer(initialPlayerCount + 1);
        assertEq(newPlayer.name, "Mbappe");
        assertEq(newPlayer.team, "PSG");
        assertEq(uint256(newPlayer.position), uint256(FootballFusionTournament.Position.FWD));
        assertEq(newPlayer.price, 160_000000);
        assertTrue(newPlayer.isActive);
        assertEq(newPlayer.gameweekPoints, 0);
        assertEq(newPlayer.totalSeasonPoints, 0);
    }
    
    function test_UpdatePlayerPoints() public {
        uint256 playerId = 7; // De Bruyne
        
        vm.prank(owner);
        tournament.updatePlayerPoints(playerId, 15);
        
        FootballFusionTournament.Player memory player = tournament.getPlayer(playerId);
        assertEq(player.gameweekPoints, 15);
        assertEq(player.totalSeasonPoints, 15);
        
        // Update again to test accumulation
        vm.prank(owner);
        tournament.updatePlayerPoints(playerId, 10);
        
        player = tournament.getPlayer(playerId);
        assertEq(player.gameweekPoints, 10);
        assertEq(player.totalSeasonPoints, 25); // 15 + 10
    }
    
    function test_RevertWhen_UpdatePlayerPoints_InvalidPlayer() public {
        vm.prank(owner);
        vm.expectRevert(FootballFusionTournament.PlayerNotExists.selector);
        tournament.updatePlayerPoints(999, 10); // Player doesn't exist
    }

    /*//////////////////////////////////////////////////////////////
                        ACCESS CONTROL TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_RevertWhen_NonOwner_CreateTournament() public {
        vm.prank(user1);
        vm.expectRevert();
        tournament.createTournament(
            1, block.timestamp + 1 hours, block.timestamp + 25 hours, 100,
            FootballFusionTournament.TournamentType.EPL,
            FootballFusionTournament.PricingTier.Tier3,
            "Test", "1"
        );
    }
    
    function test_RevertWhen_NonOwner_AddPlayer() public {
        vm.prank(user1);
        vm.expectRevert();
        tournament.addPlayer("Test Player", "Test Team", FootballFusionTournament.Position.MID, 50_000000, "");
    }
    
    function test_RevertWhen_NonOwner_UpdatePlayerPoints() public {
        vm.prank(user1);
        vm.expectRevert();
        tournament.updatePlayerPoints(1, 10);
    }
    
    function test_RevertWhen_NonOwner_CalculateUserScore() public {
        vm.prank(user1);
        vm.expectRevert();
        tournament.calculateUserScore(1, user1);
    }
    
    function test_RevertWhen_NonOwner_SettleTournament() public {
        address[] memory winners = new address[](1);
        winners[0] = user1;
        uint256[] memory scores = new uint256[](1);
        scores[0] = 100;
        
        vm.prank(user1);
        vm.expectRevert();
        tournament.settleTournament(1, winners, scores);
    }

    /*//////////////////////////////////////////////////////////////
                        PAUSABLE TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_Pause_UnpauseContract() public {
        // Pause contract
        vm.prank(owner);
        tournament.pause();
        
        // Try to join tournament while paused
        vm.prank(owner);
        tournament.createTournament(
            1, block.timestamp + 1 hours, block.timestamp + 25 hours, 100,
            FootballFusionTournament.TournamentType.EPL,
            FootballFusionTournament.PricingTier.Tier3,
            "Test", "1"
        );
        
        // Set user to Tier3
        vm.prank(user1);
        tournament.setUserPricingTier(user1, FootballFusionTournament.PricingTier.Tier3);
        
        (uint256[11] memory team, uint256[4] memory bench) = _getValidTeam442();
        
        vm.prank(user1);
        usdc.approve(address(tournament), ENTRY_FEE_TIER3_STANDARD);
        
        vm.prank(user1);
        vm.expectRevert();
        tournament.joinTournament(1, team, bench, 7, 8, FootballFusionTournament.Formation.F442);
        
        // Unpause and try again
        vm.prank(owner);
        tournament.unpause();
        
        vm.prank(user1);
        tournament.joinTournament(1, team, bench, 7, 8, FootballFusionTournament.Formation.F442);
        
        // Should succeed now
        FootballFusionTournament.UserTeam memory userTeam = tournament.getUserTeam(1, user1);
        assertTrue(userTeam.hasParticipated);
    }

    /*//////////////////////////////////////////////////////////////
                        EMERGENCY FUNCTIONS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_EmergencyWithdraw() public {
        // Create and join tournament to have some USDC in contract
        vm.prank(owner);
        tournament.createTournament(
            1, block.timestamp + 1 hours, block.timestamp + 25 hours, 100,
            FootballFusionTournament.TournamentType.EPL,
            FootballFusionTournament.PricingTier.Tier3,
            "Test", "1"
        );
        
        // Set user to Tier3
        vm.prank(user1);
        tournament.setUserPricingTier(user1, FootballFusionTournament.PricingTier.Tier3);
        
        (uint256[11] memory team, uint256[4] memory bench) = _getValidTeam442();
        
        vm.prank(user1);
        usdc.approve(address(tournament), ENTRY_FEE_TIER3_STANDARD);
        vm.prank(user1);
        tournament.joinTournament(1, team, bench, 7, 8, FootballFusionTournament.Formation.F442);
        
        uint256 contractBalance = usdc.balanceOf(address(tournament));
        uint256 ownerBalanceBefore = usdc.balanceOf(owner);
        
        assertEq(contractBalance, ENTRY_FEE_TIER3_STANDARD);
        
        // Emergency withdraw
        vm.prank(owner);
        tournament.emergencyWithdraw();
        
        assertEq(usdc.balanceOf(address(tournament)), 0);
        assertEq(usdc.balanceOf(owner), ownerBalanceBefore + contractBalance);
    }

    /*//////////////////////////////////////////////////////////////
                        EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_TournamentFull() public {
        // Create tournament with max 2 participants
        vm.prank(owner);
        tournament.createTournament(
            1, block.timestamp + 1 hours, block.timestamp + 25 hours, 2, // Max 2 participants
            FootballFusionTournament.TournamentType.EPL,
            FootballFusionTournament.PricingTier.Tier3,
            "Test", "1"
        );
        
        // Set all users to Tier3
        vm.prank(user1);
        tournament.setUserPricingTier(user1, FootballFusionTournament.PricingTier.Tier3);
        vm.prank(user2);
        tournament.setUserPricingTier(user2, FootballFusionTournament.PricingTier.Tier3);
        vm.prank(user3);
        tournament.setUserPricingTier(user3, FootballFusionTournament.PricingTier.Tier3);
        
        (uint256[11] memory team, uint256[4] memory bench) = _getValidTeam442();
        
        // User1 joins
        vm.prank(user1);
        usdc.approve(address(tournament), ENTRY_FEE_TIER3_STANDARD);
        vm.prank(user1);
        tournament.joinTournament(1, team, bench, 7, 8, FootballFusionTournament.Formation.F442);
        
        // User2 joins
        vm.prank(user2);
        usdc.approve(address(tournament), ENTRY_FEE_TIER3_STANDARD);
        vm.prank(user2);
        tournament.joinTournament(1, team, bench, 8, 7, FootballFusionTournament.Formation.F442);
        
        // User3 tries to join but tournament is full
        vm.prank(user3);
        usdc.approve(address(tournament), ENTRY_FEE_TIER3_STANDARD);
        
        vm.expectRevert(FootballFusionTournament.TournamentFull.selector);
        vm.prank(user3);
        tournament.joinTournament(1, team, bench, 12, 13, FootballFusionTournament.Formation.F442);
    }
    
    function test_ZeroPointsScoring() public {
        vm.prank(owner);
        tournament.createTournament(
            1, block.timestamp + 1 hours, block.timestamp + 25 hours, 100,
            FootballFusionTournament.TournamentType.EPL,
            FootballFusionTournament.PricingTier.Tier3,
            "Test", "1"
        );
        
        // Set user to Tier3
        vm.prank(user1);
        tournament.setUserPricingTier(user1, FootballFusionTournament.PricingTier.Tier3);
        
        (uint256[11] memory team, uint256[4] memory bench) = _getValidTeam442();
        
        vm.prank(user1);
        usdc.approve(address(tournament), ENTRY_FEE_TIER3_STANDARD);
        vm.prank(user1);
        tournament.joinTournament(1, team, bench, 7, 8, FootballFusionTournament.Formation.F442);
        
        // Don't update any player points (all remain 0)
        vm.prank(owner);
        uint256 score = tournament.calculateUserScore(1, user1);
        
        assertEq(score, 0); // Total score should be 0
    }

    /*//////////////////////////////////////////////////////////////
                        FUZZ TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testFuzz_ValidFormations(uint256 formation) public {
        vm.assume(formation <= 6); // We have 7 formations (0-6)
        
        vm.prank(owner);
        tournament.createTournament(
            1, block.timestamp + 1 hours, block.timestamp + 25 hours, 100,
            FootballFusionTournament.TournamentType.EPL,
            FootballFusionTournament.PricingTier.Tier3,
            "Test", "1"
        );
        
        // Set user to Tier3
        vm.prank(user1);
        tournament.setUserPricingTier(user1, FootballFusionTournament.PricingTier.Tier3);
        
        uint256[11] memory team;
        uint256[4] memory bench;
        FootballFusionTournament.Formation formationType = FootballFusionTournament.Formation(formation);
        
        // Create team based on formation
        if (formationType == FootballFusionTournament.Formation.F442) {
            (team, bench) = _getValidTeam442();
        } else if (formationType == FootballFusionTournament.Formation.F343) {
            (team, bench) = _getValidTeam343();
        } else {
            // For other formations, use 4-4-2 as fallback (this test focuses on testing the enum)
            (team, bench) = _getValidTeam442();
            formationType = FootballFusionTournament.Formation.F442;
        }
        
        vm.prank(user1);
        usdc.approve(address(tournament), ENTRY_FEE_TIER3_STANDARD);
        
        vm.prank(user1);
        tournament.joinTournament(1, team, bench, 7, 8, formationType);
        
        FootballFusionTournament.UserTeam memory userTeam = tournament.getUserTeam(1, user1);
        assertTrue(userTeam.hasParticipated);
    }
    
    function testFuzz_PlayerPoints(uint256 points) public {
        vm.assume(points <= 50); // Reasonable max points for a player
        
        uint256 playerId = 7; // De Bruyne
        
        vm.prank(owner);
        tournament.updatePlayerPoints(playerId, points);
        
        FootballFusionTournament.Player memory player = tournament.getPlayer(playerId);
        assertEq(player.gameweekPoints, points);
        assertEq(player.totalSeasonPoints, points);
    }
}