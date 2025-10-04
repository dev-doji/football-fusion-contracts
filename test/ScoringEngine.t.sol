// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {ScoringEngine} from "../src/ScoringEngine.sol";

contract ScoringEngineTest is Test {
    ScoringEngine public scoringEngine;
    
    address public owner = makeAddr("owner");
    address public tournamentContract = makeAddr("tournament");
    address public playerNFTContract = makeAddr("playerNFT");
    address public authorizedUpdater = makeAddr("updater");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    
    // Test player IDs
    uint256 constant PLAYER_GK = 1;
    uint256 constant PLAYER_DEF1 = 2;
    uint256 constant PLAYER_DEF2 = 3;
    uint256 constant PLAYER_DEF3 = 4;
    uint256 constant PLAYER_MID1 = 5;
    uint256 constant PLAYER_MID2 = 6;
    uint256 constant PLAYER_MID3 = 7;
    uint256 constant PLAYER_MID4 = 8;
    uint256 constant PLAYER_FWD1 = 9;
    uint256 constant PLAYER_FWD2 = 10;
    uint256 constant PLAYER_FWD3 = 11;
    uint256 constant PLAYER_BENCH1 = 12;
    uint256 constant PLAYER_BENCH2 = 13;
    uint256 constant PLAYER_BENCH3 = 14;
    uint256 constant PLAYER_BENCH4 = 15;
    
    uint256 constant TEST_TOURNAMENT_ID = 1;
    uint256 constant TEST_GAMEWEEK = 1;
    
    function setUp() public {
        vm.startPrank(owner);
        scoringEngine = new ScoringEngine(owner);
        scoringEngine.setContractAddresses(tournamentContract, playerNFTContract);
        scoringEngine.setAuthorizedUpdater(authorizedUpdater, true);
        vm.stopPrank();
    }
    
    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testInitialState() public {
        assertEq(scoringEngine.owner(), owner);
        assertEq(scoringEngine.currentGameweek(), 1);
        assertEq(scoringEngine.tournamentContract(), tournamentContract);
        assertEq(scoringEngine.playerNFTContract(), playerNFTContract);
        assertTrue(scoringEngine.authorizedUpdaters(authorizedUpdater));
        
        // Test initial scoring rules
        assertEq(scoringEngine.getScoringRule("minutesPlayed60Plus"), 2);
        assertEq(scoringEngine.getScoringRule("goalGK"), 10);
        assertEq(scoringEngine.getScoringRule("goalDEF"), 6);
        assertEq(scoringEngine.getScoringRule("goalMID"), 5);
        assertEq(scoringEngine.getScoringRule("goalFWD"), 4);
        assertEq(scoringEngine.getScoringRule("assist"), 3);
        assertEq(scoringEngine.getScoringRule("cleanSheet"), 4);
    }
    
    /*//////////////////////////////////////////////////////////////
                         AUTHORIZATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testSetAuthorizedUpdater() public {
        address newUpdater = makeAddr("newUpdater");
        
        vm.prank(owner);
        scoringEngine.setAuthorizedUpdater(newUpdater, true);
        assertTrue(scoringEngine.authorizedUpdaters(newUpdater));
        
        vm.prank(owner);
        scoringEngine.setAuthorizedUpdater(newUpdater, false);
        assertFalse(scoringEngine.authorizedUpdaters(newUpdater));
    }
    
    function testOnlyOwnerCanSetAuthorizedUpdater() public {
        address newUpdater = makeAddr("newUpdater");
        
        vm.prank(user1);
        vm.expectRevert();
        scoringEngine.setAuthorizedUpdater(newUpdater, true);
    }
    
    /*//////////////////////////////////////////////////////////////
                       PLAYER PERFORMANCE TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testUpdatePlayerPerformances() public {
        ScoringEngine.PlayerPerformance[] memory performances = new ScoringEngine.PlayerPerformance[](2);
        
        // Goalkeeper performance
        performances[0] = ScoringEngine.PlayerPerformance({
            playerId: PLAYER_GK,
            position: ScoringEngine.Position.GK,
            minutesPlayed: 90,
            goals: 0,
            assists: 1,
            cleanSheet: 1,
            goalsConceded: 0,
            ownGoals: 0,
            penaltiesSaved: 1,
            penaltiesMissed: 0,
            yellowCards: 0,
            redCards: 0,
            saves: 5,
            bonusPoints: 3,
            clearances: 2,
            blocks: 1,
            interceptions: 3,
            tackles: 1,
            isPenaltyGoal: false
        });
        
        // Forward performance
        performances[1] = ScoringEngine.PlayerPerformance({
            playerId: PLAYER_FWD1,
            position: ScoringEngine.Position.FWD,
            minutesPlayed: 75,
            goals: 2,
            assists: 0,
            cleanSheet: 0,
            goalsConceded: 0,
            ownGoals: 0,
            penaltiesSaved: 0,
            penaltiesMissed: 0,
            yellowCards: 1,
            redCards: 0,
            saves: 0,
            bonusPoints: 2,
            clearances: 0,
            blocks: 0,
            interceptions: 1,
            tackles: 2,
            isPenaltyGoal: false
        });
        
        vm.prank(authorizedUpdater);
        scoringEngine.updatePlayerPerformances(TEST_GAMEWEEK, performances);
        
        // Verify data was stored correctly
        ScoringEngine.PlayerPerformance memory storedGK = scoringEngine.getPlayerPerformance(TEST_GAMEWEEK, PLAYER_GK);
        assertEq(storedGK.playerId, PLAYER_GK);
        assertEq(storedGK.minutesPlayed, 90);
        assertEq(storedGK.goals, 0);
        assertEq(storedGK.assists, 1);
        assertEq(storedGK.cleanSheet, 1);
        assertEq(storedGK.bonusPoints, 3);
        
        ScoringEngine.PlayerPerformance memory storedFWD = scoringEngine.getPlayerPerformance(TEST_GAMEWEEK, PLAYER_FWD1);
        assertEq(storedFWD.playerId, PLAYER_FWD1);
        assertEq(storedFWD.goals, 2);
        assertEq(storedFWD.yellowCards, 1);
    }
    
    function testUpdatePlayerPerformancesFailsForUnauthorized() public {
        ScoringEngine.PlayerPerformance[] memory performances = new ScoringEngine.PlayerPerformance[](1);
        performances[0] = ScoringEngine.PlayerPerformance({
            playerId: PLAYER_GK,
            position: ScoringEngine.Position.GK,
            minutesPlayed: 90,
            goals: 0,
            assists: 0,
            cleanSheet: 1,
            goalsConceded: 0,
            ownGoals: 0,
            penaltiesSaved: 0,
            penaltiesMissed: 0,
            yellowCards: 0,
            redCards: 0,
            saves: 0,
            bonusPoints: 0,
            clearances: 0,
            blocks: 0,
            interceptions: 0,
            tackles: 0,
            isPenaltyGoal: false
        });
        
        vm.prank(user1);
        vm.expectRevert(ScoringEngine.NotAuthorized.selector);
        scoringEngine.updatePlayerPerformances(TEST_GAMEWEEK, performances);
    }
    
    function testUpdatePlayerPerformancesFailsForInvalidGameweek() public {
        ScoringEngine.PlayerPerformance[] memory performances = new ScoringEngine.PlayerPerformance[](1);
        
        vm.prank(authorizedUpdater);
        vm.expectRevert(ScoringEngine.InvalidGameweek.selector);
        scoringEngine.updatePlayerPerformances(0, performances);
        
        vm.prank(authorizedUpdater);
        vm.expectRevert(ScoringEngine.InvalidGameweek.selector);
        scoringEngine.updatePlayerPerformances(51, performances);
    }
    
    /*//////////////////////////////////////////////////////////////
                         BONUS POINTS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testUpdateBonusPoints() public {
        ScoringEngine.BonusPointsData[] memory bonusData = new ScoringEngine.BonusPointsData[](3);
        bonusData[0] = ScoringEngine.BonusPointsData({
            playerId: PLAYER_FWD1,
            bpsScore: 45,
            finalBonusPoints: 3
        });
        bonusData[1] = ScoringEngine.BonusPointsData({
            playerId: PLAYER_MID1,
            bpsScore: 38,
            finalBonusPoints: 2
        });
        bonusData[2] = ScoringEngine.BonusPointsData({
            playerId: PLAYER_DEF1,
            bpsScore: 32,
            finalBonusPoints: 1
        });
        
        vm.prank(authorizedUpdater);
        scoringEngine.updateBonusPoints(TEST_GAMEWEEK, bonusData);
        
        ScoringEngine.BonusPointsData[] memory storedBonus = scoringEngine.getGameweekBonusPoints(TEST_GAMEWEEK);
        assertEq(storedBonus.length, 3);
        assertEq(storedBonus[0].playerId, PLAYER_FWD1);
        assertEq(storedBonus[0].finalBonusPoints, 3);
        assertEq(storedBonus[1].finalBonusPoints, 2);
        assertEq(storedBonus[2].finalBonusPoints, 1);
    }
    
    function testUpdateBonusPointsFailsForInvalidPoints() public {
        ScoringEngine.BonusPointsData[] memory bonusData = new ScoringEngine.BonusPointsData[](1);
        bonusData[0] = ScoringEngine.BonusPointsData({
            playerId: PLAYER_FWD1,
            bpsScore: 45,
            finalBonusPoints: 4 // Invalid - max is 3
        });
        
        vm.prank(authorizedUpdater);
        vm.expectRevert(ScoringEngine.InvalidBonusPoints.selector);
        scoringEngine.updateBonusPoints(TEST_GAMEWEEK, bonusData);
    }
    
    /*//////////////////////////////////////////////////////////////
                       SCORE CALCULATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testCalculateTeamScoreBasic() public {
        // Setup player performances first
        _setupBasicPlayerPerformances();
        
        uint256[11] memory startingEleven = [
            PLAYER_GK, PLAYER_DEF1, PLAYER_DEF2, PLAYER_DEF3,
            PLAYER_MID1, PLAYER_MID2, PLAYER_MID3, PLAYER_MID4,
            PLAYER_FWD1, PLAYER_FWD2, PLAYER_FWD3
        ];
        uint256[4] memory bench = [PLAYER_BENCH1, PLAYER_BENCH2, PLAYER_BENCH3, PLAYER_BENCH4];
        
        vm.prank(tournamentContract);
        uint256 totalScore = scoringEngine.calculateTeamScore(
            TEST_TOURNAMENT_ID,
            user1,
            startingEleven,
            bench,
            PLAYER_FWD1, // Captain
            PLAYER_FWD2, // Vice-captain
            ScoringEngine.Formation.F433,
            ScoringEngine.ChipType.Wildcard,
            TEST_GAMEWEEK
        );
        
        assertTrue(totalScore > 0);
        assertTrue(scoringEngine.isScoreCalculated(TEST_TOURNAMENT_ID, user1));
        
        // Verify team score storage
        ScoringEngine.TeamScore memory teamScore = scoringEngine.getTeamScore(TEST_TOURNAMENT_ID, user1);
        assertEq(teamScore.totalScore, totalScore);
        assertEq(teamScore.captainId, PLAYER_FWD1);
        assertEq(teamScore.viceCaptainId, PLAYER_FWD2);
        assertEq(uint256(teamScore.formation), uint256(ScoringEngine.Formation.F433));
    }
    
    function testCalculateTeamScoreWithTripleCaptain() public {
        _setupBasicPlayerPerformances();
        
        uint256[11] memory startingEleven = [
            PLAYER_GK, PLAYER_DEF1, PLAYER_DEF2, PLAYER_DEF3,
            PLAYER_MID1, PLAYER_MID2, PLAYER_MID3, PLAYER_MID4,
            PLAYER_FWD1, PLAYER_FWD2, PLAYER_FWD3
        ];
        uint256[4] memory bench = [PLAYER_BENCH1, PLAYER_BENCH2, PLAYER_BENCH3, PLAYER_BENCH4];
        
        vm.prank(tournamentContract);
        uint256 totalScore = scoringEngine.calculateTeamScore(
            TEST_TOURNAMENT_ID,
            user1,
            startingEleven,
            bench,
            PLAYER_FWD1, // Captain with 2 goals
            PLAYER_FWD2, // Vice-captain
            ScoringEngine.Formation.F433,
            ScoringEngine.ChipType.TripleCaptain,
            TEST_GAMEWEEK
        );
        
        // Captain should get 3x points for goals (2 goals * 4 points * 3 = 24 points from goals alone)
        ScoringEngine.ScoreBreakdown[] memory breakdown = scoringEngine.getScoreBreakdown(TEST_TOURNAMENT_ID, user1);
        
        // Find captain in breakdown
        bool foundCaptain = false;
        for (uint256 i = 0; i < breakdown.length; i++) {
            if (breakdown[i].playerId == PLAYER_FWD1) {
                assertEq(breakdown[i].captainMultiplier, 3);
                foundCaptain = true;
                break;
            }
        }
        assertTrue(foundCaptain);
    }
    
    function testCalculateTeamScoreWithBenchBoost() public {
        _setupBasicPlayerPerformances();
        _setupBenchPlayerPerformances(); // Add bench performances
        
        uint256[11] memory startingEleven = [
            PLAYER_GK, PLAYER_DEF1, PLAYER_DEF2, PLAYER_DEF3,
            PLAYER_MID1, PLAYER_MID2, PLAYER_MID3, PLAYER_MID4,
            PLAYER_FWD1, PLAYER_FWD2, PLAYER_FWD3
        ];
        uint256[4] memory bench = [PLAYER_BENCH1, PLAYER_BENCH2, PLAYER_BENCH3, PLAYER_BENCH4];
        
        vm.prank(tournamentContract);
        uint256 totalScore = scoringEngine.calculateTeamScore(
            TEST_TOURNAMENT_ID,
            user1,
            startingEleven,
            bench,
            PLAYER_FWD1,
            PLAYER_FWD2,
            ScoringEngine.Formation.F433,
            ScoringEngine.ChipType.BenchBoost,
            TEST_GAMEWEEK
        );
        
        // Should include bench players in breakdown
        ScoringEngine.ScoreBreakdown[] memory breakdown = scoringEngine.getScoreBreakdown(TEST_TOURNAMENT_ID, user1);
        
        uint256 benchPlayersInBreakdown = 0;
        for (uint256 i = 0; i < breakdown.length; i++) {
            if (breakdown[i].isOnBench) {
                benchPlayersInBreakdown++;
            }
        }
        assertEq(benchPlayersInBreakdown, 4); // All 4 bench players should be included
    }
    
    function testCalculateTeamScoreFailsIfAlreadyCalculated() public {
        _setupBasicPlayerPerformances();
        
        uint256[11] memory startingEleven = [
            PLAYER_GK, PLAYER_DEF1, PLAYER_DEF2, PLAYER_DEF3,
            PLAYER_MID1, PLAYER_MID2, PLAYER_MID3, PLAYER_MID4,
            PLAYER_FWD1, PLAYER_FWD2, PLAYER_FWD3
        ];
        uint256[4] memory bench = [PLAYER_BENCH1, PLAYER_BENCH2, PLAYER_BENCH3, PLAYER_BENCH4];
        
        vm.startPrank(tournamentContract);
        
        // First calculation should succeed
        scoringEngine.calculateTeamScore(
            TEST_TOURNAMENT_ID,
            user1,
            startingEleven,
            bench,
            PLAYER_FWD1,
            PLAYER_FWD2,
            ScoringEngine.Formation.F433,
            ScoringEngine.ChipType.Wildcard,
            TEST_GAMEWEEK
        );
        
        // Second calculation should fail
        vm.expectRevert(ScoringEngine.ScoreAlreadyCalculated.selector);
        scoringEngine.calculateTeamScore(
            TEST_TOURNAMENT_ID,
            user1,
            startingEleven,
            bench,
            PLAYER_FWD1,
            PLAYER_FWD2,
            ScoringEngine.Formation.F433,
            ScoringEngine.ChipType.Wildcard,
            TEST_GAMEWEEK
        );
        
        vm.stopPrank();
    }
    
    function testCalculateTeamScoreFailsForUnauthorized() public {
        uint256[11] memory startingEleven = [
            PLAYER_GK, PLAYER_DEF1, PLAYER_DEF2, PLAYER_DEF3,
            PLAYER_MID1, PLAYER_MID2, PLAYER_MID3, PLAYER_MID4,
            PLAYER_FWD1, PLAYER_FWD2, PLAYER_FWD3
        ];
        uint256[4] memory bench = [PLAYER_BENCH1, PLAYER_BENCH2, PLAYER_BENCH3, PLAYER_BENCH4];
        
        vm.prank(user1); // Not tournament contract
        vm.expectRevert(ScoringEngine.NotAuthorized.selector);
        scoringEngine.calculateTeamScore(
            TEST_TOURNAMENT_ID,
            user1,
            startingEleven,
            bench,
            PLAYER_FWD1,
            PLAYER_FWD2,
            ScoringEngine.Formation.F433,
            ScoringEngine.ChipType.Wildcard,
            TEST_GAMEWEEK
        );
    }
    
    /*//////////////////////////////////////////////////////////////
                        PROJECTED SCORE TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testGetProjectedScore() public {
        _setupBasicPlayerPerformances();
        
        uint256[11] memory startingEleven = [
            PLAYER_GK, PLAYER_DEF1, PLAYER_DEF2, PLAYER_DEF3,
            PLAYER_MID1, PLAYER_MID2, PLAYER_MID3, PLAYER_MID4,
            PLAYER_FWD1, PLAYER_FWD2, PLAYER_FWD3
        ];
        uint256[4] memory bench = [PLAYER_BENCH1, PLAYER_BENCH2, PLAYER_BENCH3, PLAYER_BENCH4];
        
        uint256 projectedScore = scoringEngine.getProjectedScore(
            startingEleven,
            bench,
            PLAYER_FWD1, // Captain
            PLAYER_FWD2, // Vice-captain
            ScoringEngine.ChipType.Wildcard,
            TEST_GAMEWEEK
        );
        
        assertTrue(projectedScore > 0);
    }
    
    /*//////////////////////////////////////////////////////////////
                         ADMIN FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testUpdateScoringRule() public {
        string memory rule = "goalFWD";
        uint256 newValue = 5;
        uint256 oldValue = scoringEngine.getScoringRule(rule);
        
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit ScoringEngine.ScoringRuleUpdated(rule, oldValue, newValue);
        scoringEngine.updateScoringRule(rule, newValue);
        
        assertEq(scoringEngine.getScoringRule(rule), newValue);
    }
    
    function testAdvanceGameweek() public {
        uint256 currentGameweek = scoringEngine.currentGameweek();
        
        vm.prank(owner);
        vm.expectEmit(true, true, false, false);
        emit ScoringEngine.GameweekAdvanced(currentGameweek, currentGameweek + 1);
        scoringEngine.advanceGameweek();
        
        assertEq(scoringEngine.currentGameweek(), currentGameweek + 1);
    }
    
    function testSetContractAddresses() public {
        address newTournament = makeAddr("newTournament");
        address newPlayerNFT = makeAddr("newPlayerNFT");
        
        vm.prank(owner);
        scoringEngine.setContractAddresses(newTournament, newPlayerNFT);
        
        assertEq(scoringEngine.tournamentContract(), newTournament);
        assertEq(scoringEngine.playerNFTContract(), newPlayerNFT);
    }
    
    function testSetDataOracle() public {
        string memory source = "FPL";
        address oracle = makeAddr("oracle");
        
        vm.prank(owner);
        scoringEngine.setDataOracle(source, oracle);
        
        assertEq(scoringEngine.dataOracles(source), oracle);
    }
    
    /*//////////////////////////////////////////////////////////////
                           PAUSABLE TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testPauseUnpause() public {
        assertFalse(scoringEngine.paused());
        
        vm.prank(owner);
        scoringEngine.pause();
        assertTrue(scoringEngine.paused());
        
        vm.prank(owner);
        scoringEngine.unpause();
        assertFalse(scoringEngine.paused());
    }
    
    function testCannotUpdateWhenPaused() public {
        vm.prank(owner);
        scoringEngine.pause();
        
        ScoringEngine.PlayerPerformance[] memory performances = new ScoringEngine.PlayerPerformance[](1);
        performances[0] = ScoringEngine.PlayerPerformance({
            playerId: PLAYER_GK,
            position: ScoringEngine.Position.GK,
            minutesPlayed: 90,
            goals: 0,
            assists: 0,
            cleanSheet: 1,
            goalsConceded: 0,
            ownGoals: 0,
            penaltiesSaved: 0,
            penaltiesMissed: 0,
            yellowCards: 0,
            redCards: 0,
            saves: 0,
            bonusPoints: 0,
            clearances: 0,
            blocks: 0,
            interceptions: 0,
            tackles: 0,
            isPenaltyGoal: false
        });
        
        vm.prank(authorizedUpdater);
        vm.expectRevert();
        scoringEngine.updatePlayerPerformances(TEST_GAMEWEEK, performances);
    }
    
    /*//////////////////////////////////////////////////////////////
                         SCORING EDGE CASES
    //////////////////////////////////////////////////////////////*/
    
    function testViceCaptainBecomesCaptainWhenCaptainDoesntPlay() public {
        // Setup where captain doesn't play but vice-captain does
        ScoringEngine.PlayerPerformance[] memory performances = new ScoringEngine.PlayerPerformance[](2);
        
        // Captain - no minutes played
        performances[0] = ScoringEngine.PlayerPerformance({
            playerId: PLAYER_FWD1,
            position: ScoringEngine.Position.FWD,
            minutesPlayed: 0, // Doesn't play
            goals: 0,
            assists: 0,
            cleanSheet: 0,
            goalsConceded: 0,
            ownGoals: 0,
            penaltiesSaved: 0,
            penaltiesMissed: 0,
            yellowCards: 0,
            redCards: 0,
            saves: 0,
            bonusPoints: 0,
            clearances: 0,
            blocks: 0,
            interceptions: 0,
            tackles: 0,
            isPenaltyGoal: false
        });
        
        // Vice-captain - plays and scores
        performances[1] = ScoringEngine.PlayerPerformance({
            playerId: PLAYER_FWD2,
            position: ScoringEngine.Position.FWD,
            minutesPlayed: 90,
            goals: 1,
            assists: 0,
            cleanSheet: 0,
            goalsConceded: 0,
            ownGoals: 0,
            penaltiesSaved: 0,
            penaltiesMissed: 0,
            yellowCards: 0,
            redCards: 0,
            saves: 0,
            bonusPoints: 0,
            clearances: 0,
            blocks: 0,
            interceptions: 0,
            tackles: 0,
            isPenaltyGoal: false
        });
        
        vm.prank(authorizedUpdater);
        scoringEngine.updatePlayerPerformances(TEST_GAMEWEEK, performances);
        
        uint256[11] memory startingEleven = [
            PLAYER_GK, PLAYER_DEF1, PLAYER_DEF2, PLAYER_DEF3,
            PLAYER_MID1, PLAYER_MID2, PLAYER_MID3, PLAYER_MID4,
            PLAYER_FWD1, PLAYER_FWD2, PLAYER_FWD3
        ];
        uint256[4] memory bench = [PLAYER_BENCH1, PLAYER_BENCH2, PLAYER_BENCH3, PLAYER_BENCH4];
        
        // Setup minimal performances for other players
        _setupMinimalPerformances();
        
        vm.prank(tournamentContract);
        scoringEngine.calculateTeamScore(
            TEST_TOURNAMENT_ID,
            user1,
            startingEleven,
            bench,
            PLAYER_FWD1, // Captain (doesn't play)
            PLAYER_FWD2, // Vice-captain (should become captain)
            ScoringEngine.Formation.F433,
            ScoringEngine.ChipType.Wildcard,
            TEST_GAMEWEEK
        );
        
        // Check that vice-captain got captain multiplier
        ScoringEngine.ScoreBreakdown[] memory breakdown = scoringEngine.getScoreBreakdown(TEST_TOURNAMENT_ID, user1);
        
        for (uint256 i = 0; i < breakdown.length; i++) {
            if (breakdown[i].playerId == PLAYER_FWD2 && breakdown[i].playedMinutes) {
                assertEq(breakdown[i].captainMultiplier, 2); // Should be captain now
                break;
            }
        }
    }
    
    /*//////////////////////////////////////////////////////////////
                           HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function _setupBasicPlayerPerformances() internal {
        ScoringEngine.PlayerPerformance[] memory performances = new ScoringEngine.PlayerPerformance[](11);
        
        // Goalkeeper
        performances[0] = ScoringEngine.PlayerPerformance({
            playerId: PLAYER_GK,
            position: ScoringEngine.Position.GK,
            minutesPlayed: 90,
            goals: 0,
            assists: 0,
            cleanSheet: 1,
            goalsConceded: 0,
            ownGoals: 0,
            penaltiesSaved: 0,
            penaltiesMissed: 0,
            yellowCards: 0,
            redCards: 0,
            saves: 3,
            bonusPoints: 1,
            clearances: 2,
            blocks: 1,
            interceptions: 1,
            tackles: 0,
            isPenaltyGoal: false
        });
        
        // Defenders
        for (uint256 i = 1; i <= 3; i++) {
            performances[i] = ScoringEngine.PlayerPerformance({
                playerId: PLAYER_DEF1 + i - 1,
                position: ScoringEngine.Position.DEF,
                minutesPlayed: 90,
                goals: 0,
                assists: 0,
                cleanSheet: 1,
                goalsConceded: 0,
                ownGoals: 0,
                penaltiesSaved: 0,
                penaltiesMissed: 0,
                yellowCards: 0,
                redCards: 0,
                saves: 0,
                bonusPoints: 0,
                clearances: 8,
                blocks: 2,
                interceptions: 3,
                tackles: 2,
                isPenaltyGoal: false
            });
        }
        
        // Midfielders
        for (uint256 i = 4; i <= 7; i++) {
            performances[i] = ScoringEngine.PlayerPerformance({
                playerId: PLAYER_MID1 + i - 4,
                position: ScoringEngine.Position.MID,
                minutesPlayed: 85,
                goals: 0,
                assists: 1,
                cleanSheet: 0,
                goalsConceded: 0,
                ownGoals: 0,
                penaltiesSaved: 0,
                penaltiesMissed: 0,
                yellowCards: 0,
                redCards: 0,
                saves: 0,
                bonusPoints: 0,
                clearances: 1,
                blocks: 0,
                interceptions: 2,
                tackles: 3,
                isPenaltyGoal: false
            });
        }
        
        // Forwards
        for (uint256 i = 8; i <= 10; i++) {
            uint256 goals = (i == 8) ? 2 : 0; // First forward scores 2 goals
            performances[i] = ScoringEngine.PlayerPerformance({
                playerId: PLAYER_FWD1 + i - 8,
                position: ScoringEngine.Position.FWD,
                minutesPlayed: 90,
                goals: goals,
                assists: 0,
                cleanSheet: 0,
                goalsConceded: 0,
                ownGoals: 0,
                penaltiesSaved: 0,
                penaltiesMissed: 0,
                yellowCards: 0,
                redCards: 0,
                saves: 0,
                bonusPoints: (i == 8) ? 2 : 0, // Top scorer gets bonus
                clearances: 0,
                blocks: 0,
                interceptions: 0,
                tackles: 1,
                isPenaltyGoal: false
            });
        }
        
        vm.prank(authorizedUpdater);
        scoringEngine.updatePlayerPerformances(TEST_GAMEWEEK, performances);
    }
    
    function _setupBenchPlayerPerformances() internal {
        ScoringEngine.PlayerPerformance[] memory benchPerfs = new ScoringEngine.PlayerPerformance[](4);
        
        for (uint256 i = 0; i < 4; i++) {
            benchPerfs[i] = ScoringEngine.PlayerPerformance({
                playerId: PLAYER_BENCH1 + i,
                position: ScoringEngine.Position.MID,
                minutesPlayed: 30,
                goals: 0,
                assists: 0,
                cleanSheet: 0,
                goalsConceded: 0,
                ownGoals: 0,
                penaltiesSaved: 0,
                penaltiesMissed: 0,
                yellowCards: 0,
                redCards: 0,
                saves: 0,
                bonusPoints: 0,
                clearances: 1,
                blocks: 0,
                interceptions: 1,
                tackles: 1,
                isPenaltyGoal: false
            });
        }
        
        vm.prank(authorizedUpdater);
        scoringEngine.updatePlayerPerformances(TEST_GAMEWEEK, benchPerfs);
    }
    
    function _setupMinimalPerformances() internal {
        ScoringEngine.PlayerPerformance[] memory performances = new ScoringEngine.PlayerPerformance[](9);
        
        // Setup minimal performances for remaining players
        uint256[9] memory playerIds = [
            PLAYER_GK, PLAYER_DEF1, PLAYER_DEF2, PLAYER_DEF3,
            PLAYER_MID1, PLAYER_MID2, PLAYER_MID3, PLAYER_MID4,
            PLAYER_FWD3
        ];
        
        for (uint256 i = 0; i < 9; i++) {
            ScoringEngine.Position pos;
            if (i == 0) pos = ScoringEngine.Position.GK;
            else if (i <= 3) pos = ScoringEngine.Position.DEF;
            else if (i <= 7) pos = ScoringEngine.Position.MID;
            else pos = ScoringEngine.Position.FWD;
            
            performances[i] = ScoringEngine.PlayerPerformance({
                playerId: playerIds[i],
                position: pos,
                minutesPlayed: 90,
                goals: 0,
                assists: 0,
                cleanSheet: (i <= 3) ? 1 : 0,
                goalsConceded: 0,
                ownGoals: 0,
                penaltiesSaved: 0,
                penaltiesMissed: 0,
                yellowCards: 0,
                redCards: 0,
                saves: 0,
                bonusPoints: 0,
                clearances: 2,
                blocks: 1,
                interceptions: 1,
                tackles: 1,
                isPenaltyGoal: false
            });
        }
        
        vm.prank(authorizedUpdater);
        scoringEngine.updatePlayerPerformances(TEST_GAMEWEEK, performances);
    }
    
    /*//////////////////////////////////////////////////////////////
                    DETAILED SCORING CALCULATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testGoalkeeperScoringDetailed() public {
        ScoringEngine.PlayerPerformance[] memory performances = new ScoringEngine.PlayerPerformance[](1);
        
        // Goalkeeper with goal, assist, clean sheet, penalty save
        performances[0] = ScoringEngine.PlayerPerformance({
            playerId: PLAYER_GK,
            position: ScoringEngine.Position.GK,
            minutesPlayed: 90,
            goals: 1,           // 10 points (GK goal)
            assists: 1,         // 3 points
            cleanSheet: 1,      // 4 points
            goalsConceded: 0,   // No penalty
            ownGoals: 0,
            penaltiesSaved: 1,  // 5 points
            penaltiesMissed: 0,
            yellowCards: 0,
            redCards: 0,
            saves: 0,
            bonusPoints: 3,     // 3 points
            clearances: 5,
            blocks: 2,
            interceptions: 1,
            tackles: 0,
            isPenaltyGoal: false
        });
        
        vm.prank(authorizedUpdater);
        scoringEngine.updatePlayerPerformances(TEST_GAMEWEEK, performances);
        
        ScoringEngine.PlayerPerformance memory perf = scoringEngine.getPlayerPerformance(TEST_GAMEWEEK, PLAYER_GK);
        
        // Expected: 2 (minutes) + 10 (goal) + 3 (assist) + 4 (clean sheet) + 5 (penalty save) + 3 (bonus) = 27 points
        uint256 projectedScore = scoringEngine.getProjectedScore(
            [PLAYER_GK, PLAYER_DEF1, PLAYER_DEF2, PLAYER_DEF3, PLAYER_MID1, PLAYER_MID2, PLAYER_MID3, PLAYER_MID4, PLAYER_FWD1, PLAYER_FWD2, PLAYER_FWD3],
            [PLAYER_BENCH1, PLAYER_BENCH2, PLAYER_BENCH3, PLAYER_BENCH4],
            PLAYER_FWD1,
            PLAYER_FWD2,
            ScoringEngine.ChipType.Wildcard,
            TEST_GAMEWEEK
        );
        
        // GK should contribute 27 points to team total
        assertTrue(projectedScore >= 27);
    }
    
    function testDefenderScoringWithGoalsConceded() public {
        ScoringEngine.PlayerPerformance[] memory performances = new ScoringEngine.PlayerPerformance[](1);
        
        // Defender who concedes 4 goals
        performances[0] = ScoringEngine.PlayerPerformance({
            playerId: PLAYER_DEF1,
            position: ScoringEngine.Position.DEF,
            minutesPlayed: 90,
            goals: 1,           // 6 points (DEF goal)
            assists: 0,
            cleanSheet: 0,      // No clean sheet
            goalsConceded: 4,   // -2 points (2 penalties for 4 goals)
            ownGoals: 0,
            penaltiesSaved: 0,
            penaltiesMissed: 0,
            yellowCards: 1,     // -1 point
            redCards: 0,
            saves: 0,
            bonusPoints: 0,
            clearances: 8,
            blocks: 3,
            interceptions: 4,
            tackles: 3,         // Total 18 defensive actions >= 10 threshold = +2 points
            isPenaltyGoal: false
        });
        
        vm.prank(authorizedUpdater);
        scoringEngine.updatePlayerPerformances(TEST_GAMEWEEK, performances);
        
        // Expected: 2 (minutes) + 6 (goal) - 2 (goals conceded) - 1 (yellow) + 2 (defensive) = 7 points
        uint256 projectedScore = scoringEngine.getProjectedScore(
            [PLAYER_GK, PLAYER_DEF1, PLAYER_DEF2, PLAYER_DEF3, PLAYER_MID1, PLAYER_MID2, PLAYER_MID3, PLAYER_MID4, PLAYER_FWD1, PLAYER_FWD2, PLAYER_FWD3],
            [PLAYER_BENCH1, PLAYER_BENCH2, PLAYER_BENCH3, PLAYER_BENCH4],
            PLAYER_DEF1, // Make this player captain for 2x points
            PLAYER_FWD1,
            ScoringEngine.ChipType.Wildcard,
            TEST_GAMEWEEK
        );
        
        // DEF1 as captain should contribute 7 * 2 = 14 points
        assertTrue(projectedScore >= 14);
    }
    
    function testMidfielderDefensiveContribution() public {
        ScoringEngine.PlayerPerformance[] memory performances = new ScoringEngine.PlayerPerformance[](1);
        
        // Midfielder with high defensive actions
        performances[0] = ScoringEngine.PlayerPerformance({
            playerId: PLAYER_MID1,
            position: ScoringEngine.Position.MID,
            minutesPlayed: 65,  // 2 points (60+ minutes)
            goals: 1,           // 5 points (MID goal)
            assists: 2,         // 6 points (2 assists)
            cleanSheet: 1,      // 1 point (MID clean sheet)
            goalsConceded: 0,
            ownGoals: 0,
            penaltiesSaved: 0,
            penaltiesMissed: 0,
            yellowCards: 0,
            redCards: 0,
            saves: 0,
            bonusPoints: 1,     // 1 point
            clearances: 4,
            blocks: 2,
            interceptions: 3,
            tackles: 5,         // Total 14 >= 12 threshold for MID = +2 points
            isPenaltyGoal: false
        });
        
        vm.prank(authorizedUpdater);
        scoringEngine.updatePlayerPerformances(TEST_GAMEWEEK, performances);
        
        // Expected: 2 + 5 + 6 + 1 + 2 + 1 = 17 points
        uint256 projectedScore = scoringEngine.getProjectedScore(
            [PLAYER_GK, PLAYER_DEF1, PLAYER_DEF2, PLAYER_DEF3, PLAYER_MID1, PLAYER_MID2, PLAYER_MID3, PLAYER_MID4, PLAYER_FWD1, PLAYER_FWD2, PLAYER_FWD3],
            [PLAYER_BENCH1, PLAYER_BENCH2, PLAYER_BENCH3, PLAYER_BENCH4],
            PLAYER_MID1,
            PLAYER_FWD1,
            ScoringEngine.ChipType.Wildcard,
            TEST_GAMEWEEK
        );
        
        assertTrue(projectedScore >= 34); // 17 * 2 for captain
    }
    
    function testRedCardAndOwnGoalPenalties() public {
        ScoringEngine.PlayerPerformance[] memory performances = new ScoringEngine.PlayerPerformance[](1);
        
        // Player with red card, own goal, and penalty miss
        performances[0] = ScoringEngine.PlayerPerformance({
            playerId: PLAYER_FWD1,
            position: ScoringEngine.Position.FWD,
            minutesPlayed: 45,  // 1 point (less than 60 minutes)
            goals: 2,           // 8 points (2 FWD goals)
            assists: 0,
            cleanSheet: 0,
            goalsConceded: 0,
            ownGoals: 1,        // -2 points
            penaltiesSaved: 0,
            penaltiesMissed: 1, // -2 points
            yellowCards: 0,
            redCards: 1,        // -3 points
            saves: 0,
            bonusPoints: 0,
            clearances: 0,
            blocks: 0,
            interceptions: 0,
            tackles: 0,
            isPenaltyGoal: false
        });
        
        vm.prank(authorizedUpdater);
        scoringEngine.updatePlayerPerformances(TEST_GAMEWEEK, performances);
        
        // Expected: 1 + 8 - 2 - 2 - 3 = 2 points
        uint256 projectedScore = scoringEngine.getProjectedScore(
            [PLAYER_GK, PLAYER_DEF1, PLAYER_DEF2, PLAYER_DEF3, PLAYER_MID1, PLAYER_MID2, PLAYER_MID3, PLAYER_MID4, PLAYER_FWD1, PLAYER_FWD2, PLAYER_FWD3],
            [PLAYER_BENCH1, PLAYER_BENCH2, PLAYER_BENCH3, PLAYER_BENCH4],
            PLAYER_FWD1,
            PLAYER_FWD2,
            ScoringEngine.ChipType.Wildcard,
            TEST_GAMEWEEK
        );
        
        assertTrue(projectedScore >= 4); // 2 * 2 for captain
    }
    
    /*//////////////////////////////////////////////////////////////
                         AUTO-SUBSTITUTION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testAutoSubstitutionWhenStarterDoesntPlay() public {
        // Setup where one starter doesn't play but bench player does
        ScoringEngine.PlayerPerformance[] memory performances = new ScoringEngine.PlayerPerformance[](12);
        
        // 10 starters who play
        for (uint256 i = 0; i < 10; i++) {
            uint256[10] memory playerIds = [
                PLAYER_GK, PLAYER_DEF1, PLAYER_DEF2, PLAYER_DEF3,
                PLAYER_MID1, PLAYER_MID2, PLAYER_MID3, PLAYER_MID4,
                PLAYER_FWD1, PLAYER_FWD2
            ];
            
            ScoringEngine.Position pos;
            if (i == 0) pos = ScoringEngine.Position.GK;
            else if (i <= 3) pos = ScoringEngine.Position.DEF;
            else if (i <= 7) pos = ScoringEngine.Position.MID;
            else pos = ScoringEngine.Position.FWD;
            
            performances[i] = ScoringEngine.PlayerPerformance({
                playerId: playerIds[i],
                position: pos,
                minutesPlayed: 90,
                goals: 0,
                assists: 0,
                cleanSheet: (i <= 3) ? 1 : 0,
                goalsConceded: 0,
                ownGoals: 0,
                penaltiesSaved: 0,
                penaltiesMissed: 0,
                yellowCards: 0,
                redCards: 0,
                saves: 0,
                bonusPoints: 0,
                clearances: 3,
                blocks: 1,
                interceptions: 1,
                tackles: 1,
                isPenaltyGoal: false
            });
        }
        
        // 1 starter who doesn't play
        performances[10] = ScoringEngine.PlayerPerformance({
            playerId: PLAYER_FWD3,
            position: ScoringEngine.Position.FWD,
            minutesPlayed: 0, // Doesn't play
            goals: 0,
            assists: 0,
            cleanSheet: 0,
            goalsConceded: 0,
            ownGoals: 0,
            penaltiesSaved: 0,
            penaltiesMissed: 0,
            yellowCards: 0,
            redCards: 0,
            saves: 0,
            bonusPoints: 0,
            clearances: 0,
            blocks: 0,
            interceptions: 0,
            tackles: 0,
            isPenaltyGoal: false
        });
        
        // 1 bench player who plays
        performances[11] = ScoringEngine.PlayerPerformance({
            playerId: PLAYER_BENCH1,
            position: ScoringEngine.Position.FWD,
            minutesPlayed: 90,
            goals: 1, // Scores a goal
            assists: 0,
            cleanSheet: 0,
            goalsConceded: 0,
            ownGoals: 0,
            penaltiesSaved: 0,
            penaltiesMissed: 0,
            yellowCards: 0,
            redCards: 0,
            saves: 0,
            bonusPoints: 1,
            clearances: 0,
            blocks: 0,
            interceptions: 0,
            tackles: 1,
            isPenaltyGoal: false
        });
        
        vm.prank(authorizedUpdater);
        scoringEngine.updatePlayerPerformances(TEST_GAMEWEEK, performances);
        
        uint256[11] memory startingEleven = [
            PLAYER_GK, PLAYER_DEF1, PLAYER_DEF2, PLAYER_DEF3,
            PLAYER_MID1, PLAYER_MID2, PLAYER_MID3, PLAYER_MID4,
            PLAYER_FWD1, PLAYER_FWD2, PLAYER_FWD3
        ];
        uint256[4] memory bench = [PLAYER_BENCH1, PLAYER_BENCH2, PLAYER_BENCH3, PLAYER_BENCH4];
        
        vm.prank(tournamentContract);
        scoringEngine.calculateTeamScore(
            TEST_TOURNAMENT_ID,
            user1,
            startingEleven,
            bench,
            PLAYER_FWD1,
            PLAYER_FWD2,
            ScoringEngine.Formation.F433,
            ScoringEngine.ChipType.Wildcard,
            TEST_GAMEWEEK
        );
        
        // Check that bench player was auto-substituted
        ScoringEngine.ScoreBreakdown[] memory breakdown = scoringEngine.getScoreBreakdown(TEST_TOURNAMENT_ID, user1);
        
        bool benchPlayerFound = false;
        for (uint256 i = 0; i < breakdown.length; i++) {
            if (breakdown[i].playerId == PLAYER_BENCH1 && breakdown[i].isOnBench && breakdown[i].playedMinutes) {
                benchPlayerFound = true;
                // Should have: 2 (minutes) + 4 (goal) + 1 (bonus) = 7 points
                assertEq(breakdown[i].finalScore, 7);
                break;
            }
        }
        assertTrue(benchPlayerFound, "Bench player should be auto-substituted");
    }
    
    /*//////////////////////////////////////////////////////////////
                         INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testCompleteGameweekFlow() public {
        // 1. Update player performances
        _setupBasicPlayerPerformances();
        
        // 2. Update bonus points
        ScoringEngine.BonusPointsData[] memory bonusData = new ScoringEngine.BonusPointsData[](3);
        bonusData[0] = ScoringEngine.BonusPointsData({
            playerId: PLAYER_FWD1,
            bpsScore: 50,
            finalBonusPoints: 3
        });
        bonusData[1] = ScoringEngine.BonusPointsData({
            playerId: PLAYER_MID1,
            bpsScore: 40,
            finalBonusPoints: 2
        });
        bonusData[2] = ScoringEngine.BonusPointsData({
            playerId: PLAYER_DEF1,
            bpsScore: 35,
            finalBonusPoints: 1
        });
        
        vm.prank(authorizedUpdater);
        scoringEngine.updateBonusPoints(TEST_GAMEWEEK, bonusData);
        
        // 3. Calculate multiple team scores
        uint256[11] memory startingEleven = [
            PLAYER_GK, PLAYER_DEF1, PLAYER_DEF2, PLAYER_DEF3,
            PLAYER_MID1, PLAYER_MID2, PLAYER_MID3, PLAYER_MID4,
            PLAYER_FWD1, PLAYER_FWD2, PLAYER_FWD3
        ];
        uint256[4] memory bench = [PLAYER_BENCH1, PLAYER_BENCH2, PLAYER_BENCH3, PLAYER_BENCH4];
        
        vm.startPrank(tournamentContract);
        
        // User 1 - normal captain
        uint256 score1 = scoringEngine.calculateTeamScore(
            TEST_TOURNAMENT_ID,
            user1,
            startingEleven,
            bench,
            PLAYER_FWD1,
            PLAYER_FWD2,
            ScoringEngine.Formation.F433,
            ScoringEngine.ChipType.Wildcard,
            TEST_GAMEWEEK
        );
        
        // User 2 - different captain, triple captain chip
        uint256 score2 = scoringEngine.calculateTeamScore(
            TEST_TOURNAMENT_ID + 1,
            user2,
            startingEleven,
            bench,
            PLAYER_MID1,
            PLAYER_FWD1,
            ScoringEngine.Formation.F352,
            ScoringEngine.ChipType.TripleCaptain,
            TEST_GAMEWEEK
        );
        
        vm.stopPrank();
        
        // 4. Verify results
        assertTrue(score1 > 0);
        assertTrue(score2 > 0);
        assertTrue(score2 != score1); // Different scores due to different captains and chips
        
        assertTrue(scoringEngine.isScoreCalculated(TEST_TOURNAMENT_ID, user1));
        assertTrue(scoringEngine.isScoreCalculated(TEST_TOURNAMENT_ID + 1, user2));
        
        // 5. Advance gameweek
        vm.prank(owner);
        scoringEngine.advanceGameweek();
        assertEq(scoringEngine.currentGameweek(), 2);
    }
    
    /*//////////////////////////////////////////////////////////////
                              EVENTS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testPlayerPerformanceUpdatedEvent() public {
        ScoringEngine.PlayerPerformance[] memory performances = new ScoringEngine.PlayerPerformance[](1);
        performances[0] = ScoringEngine.PlayerPerformance({
            playerId: PLAYER_GK,
            position: ScoringEngine.Position.GK,
            minutesPlayed: 90,
            goals: 0,
            assists: 0,
            cleanSheet: 1,
            goalsConceded: 0,
            ownGoals: 0,
            penaltiesSaved: 0,
            penaltiesMissed: 0,
            yellowCards: 0,
            redCards: 0,
            saves: 0,
            bonusPoints: 0,
            clearances: 0,
            blocks: 0,
            interceptions: 0,
            tackles: 0,
            isPenaltyGoal: false
        });
        
        vm.prank(authorizedUpdater);
        vm.expectEmit(true, true, false, true);
        emit ScoringEngine.PlayerPerformanceUpdated(TEST_GAMEWEEK, PLAYER_GK, 6); // 2 + 4 = 6 points
        scoringEngine.updatePlayerPerformances(TEST_GAMEWEEK, performances);
    }
    
    function testTeamScoreCalculatedEvent() public {
        _setupBasicPlayerPerformances();
        
        uint256[11] memory startingEleven = [
            PLAYER_GK, PLAYER_DEF1, PLAYER_DEF2, PLAYER_DEF3,
            PLAYER_MID1, PLAYER_MID2, PLAYER_MID3, PLAYER_MID4,
            PLAYER_FWD1, PLAYER_FWD2, PLAYER_FWD3
        ];
        uint256[4] memory bench = [PLAYER_BENCH1, PLAYER_BENCH2, PLAYER_BENCH3, PLAYER_BENCH4];
        
        vm.prank(tournamentContract);
        vm.expectEmit(true, true, false, false);
        emit ScoringEngine.TeamScoreCalculated(TEST_TOURNAMENT_ID, user1, 0, TEST_GAMEWEEK);
        scoringEngine.calculateTeamScore(
            TEST_TOURNAMENT_ID,
            user1,
            startingEleven,
            bench,
            PLAYER_FWD1,
            PLAYER_FWD2,
            ScoringEngine.Formation.F433,
            ScoringEngine.ChipType.Wildcard,
            TEST_GAMEWEEK
        );
    }
}