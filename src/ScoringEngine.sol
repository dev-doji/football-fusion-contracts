// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title FootballFusion Scoring Engine
 * @dev Handles all scoring calculations based on FPL 2025/26 rules
 * @author FootballFusion Team
 * @notice Implements comprehensive football scoring with bonus points and chips
 */
contract ScoringEngine is Ownable, ReentrancyGuard, Pausable {
    
    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/
    
    enum Position { GK, DEF, MID, FWD }
    enum ChipType { Wildcard, FreeHit, TripleCaptain, BenchBoost }
    enum Formation { F343, F352, F433, F442, F451, F532, F541 }
    
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/
    
    struct PlayerPerformance {
        uint256 playerId;
        Position position;
        uint256 minutesPlayed;
        uint256 goals;
        uint256 assists;
        uint256 cleanSheet;          // 1 if clean sheet, 0 otherwise
        uint256 goalsConceded;
        uint256 ownGoals;
        uint256 penaltiesSaved;
        uint256 penaltiesMissed;
        uint256 yellowCards;
        uint256 redCards;
        uint256 saves;               // For goalkeepers
        uint256 bonusPoints;         // 0, 1, 2, or 3
        uint256 clearances;          // New 2025/26 feature
        uint256 blocks;              // New 2025/26 feature
        uint256 interceptions;       // New 2025/26 feature
        uint256 tackles;             // New 2025/26 feature
        bool isPenaltyGoal;          // New 2025/26 standardization
    }
    
    struct TeamScore {
        uint256 tournamentId;
        address user;
        uint256[11] startingEleven;
        uint256[4] bench;
        uint256 captainId;
        uint256 viceCaptainId;
        Formation formation;
        ChipType activeChip;
        bool chipUsed;
        uint256 totalScore;
        uint256 gameweek;
        uint256 calculatedAt;
    }
    
    struct ScoreBreakdown {
        uint256 playerId;
        uint256 basePoints;
        uint256 bonusPoints;
        uint256 captainMultiplier;   // 1x, 2x, or 3x for triple captain
        uint256 finalScore;
        bool isOnBench;
        bool playedMinutes;
    }
    
    struct BonusPointsData {
        uint256 playerId;
        uint256 bpsScore;            // Bonus Points System score
        uint256 finalBonusPoints;    // 0, 1, 2, or 3
    }
    
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Tournament contract address
    address public tournamentContract;
    
    /// @notice Player NFT contract address
    address public playerNFTContract;
    
    /// @notice Oracle addresses for data feeds
    mapping(string => address) public dataOracles;
    
    /// @notice Gameweek performance data
    mapping(uint256 => mapping(uint256 => PlayerPerformance)) public gameweekPerformances;
    
    /// @notice Calculated team scores
    mapping(uint256 => mapping(address => TeamScore)) public teamScores;
    
    /// @notice Score breakdowns for transparency
    mapping(uint256 => mapping(address => ScoreBreakdown[])) public scoreBreakdowns;
    
    /// @notice Bonus points for each gameweek
    mapping(uint256 => BonusPointsData[]) public gameweekBonusPoints;
    
    /// @notice Scoring rules (can be updated for different competitions)
    mapping(string => uint256) public scoringRules;
    
    /// @notice Current gameweek
    uint256 public currentGameweek;
    
    /// @notice Authorized score updaters
    mapping(address => bool) public authorizedUpdaters;
    
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event PlayerPerformanceUpdated(
        uint256 indexed gameweek,
        uint256 indexed playerId,
        uint256 totalPoints
    );
    
    event TeamScoreCalculated(
        uint256 indexed tournamentId,
        address indexed user,
        uint256 totalScore,
        uint256 gameweek
    );
    
    event BonusPointsAwarded(
        uint256 indexed gameweek,
        uint256[] playerIds,
        uint256[] bonusPoints
    );
    
    event ScoringRuleUpdated(
        string indexed rule,
        uint256 oldValue,
        uint256 newValue
    );
    
    event GameweekAdvanced(
        uint256 indexed oldGameweek,
        uint256 indexed newGameweek
    );

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    
    error NotAuthorized();
    error InvalidGameweek();
    error InvalidPlayerData();
    error InvalidFormation();
    error ScoreAlreadyCalculated();
    error InvalidBonusPoints();
    error DataNotReady();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    constructor(address _initialOwner) Ownable(_initialOwner) {
        currentGameweek = 1;
        _initializeScoringRules();
    }

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    
    modifier onlyAuthorized() {
        if (!authorizedUpdaters[msg.sender] && msg.sender != owner()) {
            revert NotAuthorized();
        }
        _;
    }
    
    modifier onlyTournament() {
        if (msg.sender != tournamentContract) {
            revert NotAuthorized();
        }
        _;
    }
    
    modifier validGameweek(uint256 gameweek) {
        if (gameweek == 0 || gameweek > 50) {
            revert InvalidGameweek();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            PERFORMANCE UPDATE
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Update player performance for a gameweek
     * @param gameweek Gameweek number
     * @param performances Array of player performances
     */
    function updatePlayerPerformances(
        uint256 gameweek,
        PlayerPerformance[] calldata performances
    ) external onlyAuthorized whenNotPaused validGameweek(gameweek) {
        for (uint256 i = 0; i < performances.length; i++) {
            PlayerPerformance memory perf = performances[i];
            
            if (perf.playerId == 0) revert InvalidPlayerData();
            
            gameweekPerformances[gameweek][perf.playerId] = perf;
            
            uint256 totalPoints = _calculatePlayerScore(perf);
            
            emit PlayerPerformanceUpdated(gameweek, perf.playerId, totalPoints);
        }
    }
    
    /**
     * @notice Update bonus points for gameweek
     * @param gameweek Gameweek number
     * @param bonusData Array of bonus points data
     */
    function updateBonusPoints(
        uint256 gameweek,
        BonusPointsData[] calldata bonusData
    ) external onlyAuthorized whenNotPaused validGameweek(gameweek) {
        // Clear existing bonus points for this gameweek
        delete gameweekBonusPoints[gameweek];
        
        uint256[] memory playerIds = new uint256[](bonusData.length);
        uint256[] memory bonusPoints = new uint256[](bonusData.length);
        
        for (uint256 i = 0; i < bonusData.length; i++) {
            if (bonusData[i].finalBonusPoints > 3) revert InvalidBonusPoints();
            
            gameweekBonusPoints[gameweek].push(bonusData[i]);
            gameweekPerformances[gameweek][bonusData[i].playerId].bonusPoints = bonusData[i].finalBonusPoints;
            
            playerIds[i] = bonusData[i].playerId;
            bonusPoints[i] = bonusData[i].finalBonusPoints;
        }
        
        emit BonusPointsAwarded(gameweek, playerIds, bonusPoints);
    }

    /*//////////////////////////////////////////////////////////////
                            SCORING CALCULATION
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Calculate team score for tournament
     * @param tournamentId Tournament ID
     * @param user User address
     * @param startingEleven Starting eleven player IDs
     * @param bench Bench player IDs
     * @param captainId Captain player ID
     * @param viceCaptainId Vice-captain player ID
     * @param formation Team formation
     * @param activeChip Active chip type
     * @param gameweek Gameweek number
     */
    function calculateTeamScore(
        uint256 tournamentId,
        address user,
        uint256[11] calldata startingEleven,
        uint256[4] calldata bench,
        uint256 captainId,
        uint256 viceCaptainId,
        Formation formation,
        ChipType activeChip,
        uint256 gameweek
    ) external onlyTournament nonReentrant returns (uint256) {
        // Check if score already calculated
        if (teamScores[tournamentId][user].calculatedAt != 0) {
            revert ScoreAlreadyCalculated();
        }
        
        uint256 totalScore = 0;
        uint256 playingCount = 0;
        
        // Clear previous score breakdown
        delete scoreBreakdowns[tournamentId][user];
        
        // Calculate starting eleven scores
        for (uint256 i = 0; i < 11; i++) {
            uint256 playerId = startingEleven[i];
            PlayerPerformance memory perf = gameweekPerformances[gameweek][playerId];
            
            if (perf.minutesPlayed > 0) {
                playingCount++;
                uint256 playerScore = _calculatePlayerScore(perf);
                
                // Apply captain multiplier
                uint256 multiplier = 1;
                if (playerId == captainId) {
                    multiplier = (activeChip == ChipType.TripleCaptain) ? 3 : 2;
                } else if (playerId == viceCaptainId && gameweekPerformances[gameweek][captainId].minutesPlayed == 0) {
                    // Vice-captain becomes captain if captain doesn't play
                    multiplier = (activeChip == ChipType.TripleCaptain) ? 3 : 2;
                }
                
                uint256 finalPlayerScore = playerScore * multiplier;
                totalScore += finalPlayerScore;
                
                // Store breakdown
                scoreBreakdowns[tournamentId][user].push(ScoreBreakdown({
                    playerId: playerId,
                    basePoints: _calculateBaseScore(perf),
                    bonusPoints: perf.bonusPoints,
                    captainMultiplier: multiplier,
                    finalScore: finalPlayerScore,
                    isOnBench: false,
                    playedMinutes: true
                }));
            }
        }
        
        // Handle bench players (auto-substitution if < 11 playing)
        if (playingCount < 11 || activeChip == ChipType.BenchBoost) {
            for (uint256 i = 0; i < 4; i++) {
                uint256 benchPlayerId = bench[i];
                PlayerPerformance memory benchPerf = gameweekPerformances[gameweek][benchPlayerId];
                
                if (benchPerf.minutesPlayed > 0) {
                    uint256 benchScore = _calculatePlayerScore(benchPerf);
                    
                    if (activeChip == ChipType.BenchBoost) {
                        // Bench Boost: all bench players count
                        totalScore += benchScore;
                    } else if (playingCount < 11) {
                        // Auto-substitution for non-playing starters
                        totalScore += benchScore;
                        playingCount++;
                    }
                    
                    scoreBreakdowns[tournamentId][user].push(ScoreBreakdown({
                        playerId: benchPlayerId,
                        basePoints: _calculateBaseScore(benchPerf),
                        bonusPoints: benchPerf.bonusPoints,
                        captainMultiplier: 1,
                        finalScore: benchScore,
                        isOnBench: true,
                        playedMinutes: true
                    }));
                }
            }
        }
        
        // Store team score
        teamScores[tournamentId][user] = TeamScore({
            tournamentId: tournamentId,
            user: user,
            startingEleven: startingEleven,
            bench: bench,
            captainId: captainId,
            viceCaptainId: viceCaptainId,
            formation: formation,
            activeChip: activeChip,
            chipUsed: activeChip != ChipType.Wildcard, // Wildcard doesn't count as "used"
            totalScore: totalScore,
            gameweek: gameweek,
            calculatedAt: block.timestamp
        });
        
        emit TeamScoreCalculated(tournamentId, user, totalScore, gameweek);
        
        return totalScore;
    }
    
    /**
     * @notice Calculate individual player score
     * @param perf Player performance data
     * @return Total points scored
     */
    function _calculatePlayerScore(PlayerPerformance memory perf) internal view returns (uint256) {
        uint256 baseScore = _calculateBaseScore(perf);
        return baseScore + perf.bonusPoints;
    }
    
    /**
     * @notice Calculate base score (excluding bonus points)
     * @param perf Player performance data
     * @return Base points scored
     */
    function _calculateBaseScore(PlayerPerformance memory perf) internal view returns (uint256) {
        uint256 points = 0;
        
        // Minutes played points
        if (perf.minutesPlayed >= 60) {
            points += scoringRules["minutesPlayed60Plus"];
        } else if (perf.minutesPlayed > 0) {
            points += scoringRules["minutesPlayedSome"];
        }
        
        // Goals (position dependent)
        if (perf.goals > 0) {
            uint256 goalPoints = scoringRules[_getPositionKey(perf.position, "goal")];
            points += perf.goals * goalPoints;
        }
        
        // Assists
        points += perf.assists * scoringRules["assist"];
        
        // Clean sheets (GK/DEF only get full points, MID get reduced)
        if (perf.cleanSheet == 1) {
            if (perf.position == Position.GK || perf.position == Position.DEF) {
                points += scoringRules["cleanSheet"];
            } else if (perf.position == Position.MID) {
                points += scoringRules["cleanSheetMid"];
            }
        }
        
        // Goals conceded penalty (GK/DEF only)
        if (perf.position == Position.GK || perf.position == Position.DEF) {
            if (perf.goalsConceded >= 2) {
                uint256 penalty = (perf.goalsConceded / 2) * scoringRules["goalsConcededPenalty"];
                points = points > penalty ? points - penalty : 0;
            }
        }
        
        // Penalties
        points += perf.penaltiesSaved * scoringRules["penaltySaved"];
        points = points > (perf.penaltiesMissed * scoringRules["penaltyMissed"]) ? 
                points - (perf.penaltiesMissed * scoringRules["penaltyMissed"]) : 0;
        
        // Cards
        points = points > (perf.yellowCards * scoringRules["yellowCard"]) ? 
                points - (perf.yellowCards * scoringRules["yellowCard"]) : 0;
        points = points > (perf.redCards * scoringRules["redCard"]) ? 
                points - (perf.redCards * scoringRules["redCard"]) : 0;
        
        // Own goals
        points = points > (perf.ownGoals * scoringRules["ownGoal"]) ? 
                points - (perf.ownGoals * scoringRules["ownGoal"]) : 0;
        
        // New 2025/26 defensive contributions
        uint256 defensiveActions = perf.clearances + perf.blocks + perf.interceptions + perf.tackles;
        if (_qualifiesForDefensiveBonus(perf.position, defensiveActions)) {
            points += scoringRules["defensiveContribution"];
        }
        
        return points;
    }
    
    /**
     * @notice Check if player qualifies for defensive contribution bonus
     * @param position Player position
     * @param totalActions Total defensive actions
     * @return Whether player qualifies
     */
    function _qualifiesForDefensiveBonus(Position position, uint256 totalActions) internal view returns (bool) {
        if (position == Position.DEF) {
            return totalActions >= scoringRules["defensiveThresholdDef"];
        } else if (position == Position.MID || position == Position.FWD) {
            return totalActions >= scoringRules["defensiveThresholdMidFwd"];
        }
        return false;
    }
    
    /**
     * @notice Get position-specific scoring key
     * @param position Player position
     * @param action Action type
     * @return Scoring rule key
     */
    function _getPositionKey(Position position, string memory action) internal pure returns (string memory) {
        if (position == Position.GK) {
            return string(abi.encodePacked(action, "GK"));
        } else if (position == Position.DEF) {
            return string(abi.encodePacked(action, "DEF"));
        } else if (position == Position.MID) {
            return string(abi.encodePacked(action, "MID"));
        } else {
            return string(abi.encodePacked(action, "FWD"));
        }
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Set authorized updater
     * @param updater Updater address
     * @param authorized Authorization status
     */
    function setAuthorizedUpdater(address updater, bool authorized) external onlyOwner {
        authorizedUpdaters[updater] = authorized;
    }
    
    /**
     * @notice Update scoring rule
     * @param rule Rule name
     * @param value New value
     */
    function updateScoringRule(string calldata rule, uint256 value) external onlyOwner {
        uint256 oldValue = scoringRules[rule];
        scoringRules[rule] = value;
        emit ScoringRuleUpdated(rule, oldValue, value);
    }
    
    /**
     * @notice Advance to next gameweek
     */
    function advanceGameweek() external onlyOwner {
        uint256 oldGameweek = currentGameweek;
        currentGameweek++;
        emit GameweekAdvanced(oldGameweek, currentGameweek);
    }
    
    /**
     * @notice Set contract addresses
     * @param _tournamentContract Tournament contract address
     * @param _playerNFTContract Player NFT contract address
     */
    function setContractAddresses(
        address _tournamentContract,
        address _playerNFTContract
    ) external onlyOwner {
        tournamentContract = _tournamentContract;
        playerNFTContract = _playerNFTContract;
    }
    
    /**
     * @notice Set data oracle
     * @param source Oracle source name
     * @param oracle Oracle address
     */
    function setDataOracle(string calldata source, address oracle) external onlyOwner {
        dataOracles[source] = oracle;
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Initialize scoring rules based on FPL 2025/26
     */
    function _initializeScoringRules() internal {
        // Minutes played
        scoringRules["minutesPlayed60Plus"] = 2;
        scoringRules["minutesPlayedSome"] = 1;
        
        // Goals (position dependent)
        scoringRules["goalGK"] = 10;
        scoringRules["goalDEF"] = 6;
        scoringRules["goalMID"] = 5;
        scoringRules["goalFWD"] = 4;
        
        // Assists
        scoringRules["assist"] = 3;
        
        // Clean sheets
        scoringRules["cleanSheet"] = 4;
        scoringRules["cleanSheetMid"] = 1;
        
        // Penalties
        scoringRules["penaltySaved"] = 5;
        scoringRules["penaltyMissed"] = 2;
        
        // Negative points
        scoringRules["yellowCard"] = 1;
        scoringRules["redCard"] = 3;
        scoringRules["ownGoal"] = 2;
        scoringRules["goalsConcededPenalty"] = 1;
        
        // New 2025/26 defensive contributions
        scoringRules["defensiveContribution"] = 2;
        scoringRules["defensiveThresholdDef"] = 10;
        scoringRules["defensiveThresholdMidFwd"] = 12;
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Get player performance for gameweek
     * @param gameweek Gameweek number
     * @param playerId Player ID
     * @return Player performance data
     */
    function getPlayerPerformance(
        uint256 gameweek,
        uint256 playerId
    ) external view returns (PlayerPerformance memory) {
        return gameweekPerformances[gameweek][playerId];
    }
    
    /**
     * @notice Get team score
     * @param tournamentId Tournament ID
     * @param user User address
     * @return Team score data
     */
    function getTeamScore(
        uint256 tournamentId,
        address user
    ) external view returns (TeamScore memory) {
        return teamScores[tournamentId][user];
    }
    
    /**
     * @notice Get score breakdown
     * @param tournamentId Tournament ID
     * @param user User address
     * @return Array of score breakdowns
     */
    function getScoreBreakdown(
        uint256 tournamentId,
        address user
    ) external view returns (ScoreBreakdown[] memory) {
        return scoreBreakdowns[tournamentId][user];
    }
    
    /**
     * @notice Get bonus points for gameweek
     * @param gameweek Gameweek number
     * @return Array of bonus points data
     */
    function getGameweekBonusPoints(
        uint256 gameweek
    ) external view returns (BonusPointsData[] memory) {
        return gameweekBonusPoints[gameweek];
    }
    
    /**
     * @notice Get scoring rule value
     * @param rule Rule name
     * @return Rule value
     */
    function getScoringRule(string calldata rule) external view returns (uint256) {
        return scoringRules[rule];
    }
    
    /**
     * @notice Check if score is calculated
     * @param tournamentId Tournament ID
     * @param user User address
     * @return Whether score is calculated
     */
    function isScoreCalculated(
        uint256 tournamentId,
        address user
    ) external view returns (bool) {
        return teamScores[tournamentId][user].calculatedAt != 0;
    }
    
    /**
     * @notice Calculate projected score (before official calculation)
     * @param startingEleven Starting eleven player IDs
     * @param bench Bench player IDs
     * @param captainId Captain player ID
     * @param viceCaptainId Vice-captain player ID
     * @param activeChip Active chip type
     * @param gameweek Gameweek number
     * @return Projected total score
     */
    function getProjectedScore(
        uint256[11] calldata startingEleven,
        uint256[4] calldata bench,
        uint256 captainId,
        uint256 viceCaptainId,
        ChipType activeChip,
        uint256 gameweek
    ) external view returns (uint256) {
        uint256 totalScore = 0;
        uint256 playingCount = 0;
        
        // Calculate starting eleven scores
        for (uint256 i = 0; i < 11; i++) {
            uint256 playerId = startingEleven[i];
            PlayerPerformance memory perf = gameweekPerformances[gameweek][playerId];
            
            if (perf.minutesPlayed > 0) {
                playingCount++;
                uint256 playerScore = _calculatePlayerScore(perf);
                
                // Apply captain multiplier
                uint256 multiplier = 1;
                if (playerId == captainId) {
                    multiplier = (activeChip == ChipType.TripleCaptain) ? 3 : 2;
                } else if (playerId == viceCaptainId && gameweekPerformances[gameweek][captainId].minutesPlayed == 0) {
                    multiplier = (activeChip == ChipType.TripleCaptain) ? 3 : 2;
                }
                
                totalScore += playerScore * multiplier;
            }
        }
        
        // Handle bench players
        if (playingCount < 11 || activeChip == ChipType.BenchBoost) {
            for (uint256 i = 0; i < 4; i++) {
                uint256 benchPlayerId = bench[i];
                PlayerPerformance memory benchPerf = gameweekPerformances[gameweek][benchPlayerId];
                
                if (benchPerf.minutesPlayed > 0) {
                    uint256 benchScore = _calculatePlayerScore(benchPerf);
                    
                    if (activeChip == ChipType.BenchBoost || playingCount < 11) {
                        totalScore += benchScore;
                        if (playingCount < 11) playingCount++;
                    }
                }
            }
        }
        
        return totalScore;
    }
    
    /**
     * @notice Pause contract
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @notice Unpause contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }
}