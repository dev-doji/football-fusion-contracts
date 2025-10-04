// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title FootballFusion Tournament Contract
 * @dev Fantasy football tournaments with USDC prizes on Base chain
 * @author FootballFusion Team
 * @notice Supports EPL, Champions League, and International tournaments
 */
contract FootballFusionTournament is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;
    
    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/
    
    enum TournamentType { EPL, ChampionsLeague, International, Custom }
    enum Formation { F343, F352, F433, F442, F451, F532, F541 }
    enum Position { GK, DEF, MID, FWD }
    enum PricingTier { Tier1, Tier2, Tier3 }
    
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/
    
    struct Tournament {
        uint256 entryFee;              // Entry fee in USDC (6 decimals)
        uint256 startTime;
        uint256 endTime;
        uint256 maxParticipants;
        uint256 currentParticipants;
        uint256 totalPrizePool;
        TournamentType tournamentType;
        PricingTier pricingTier;
        bool isActive;
        bool isSettled;
        string name;
        string gameweek;
    }
    
    struct UserTeam {
        uint256[11] startingEleven;
        uint256[4] bench;
        uint256 captainId;
        uint256 viceCaptainId;
        Formation formation;
        uint256 totalScore;
        bool hasParticipated;
        bool chipsUsed;
        PricingTier userTier;
    }
    
    struct Player {
        string name;
        string team;
        Position position;
        uint256 price;                 // Price in USDC
        bool isActive;
        uint256 gameweekPoints;
        uint256 totalSeasonPoints;
        string imageUrl;
    }
    
    struct TournamentResult {
        address user;
        uint256 finalScore;
        uint256 rank;
        uint256 prizeWon;
    }
    
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    
    /// @notice USDC contract on Base
    IERC20 public immutable USDC;
    
    /// @notice Platform fee (2% = 200/10000)
    uint256 public constant PLATFORM_FEE_BPS = 200;
    uint256 private constant BPS_DENOMINATOR = 10_000;
    
    /// @notice Counter variables
    uint256 public tournamentCounter;
    uint256 public playerCounter;
    
    /// @notice Regional pricing in USDC (6 decimals)
    /// @dev [starter, standard, premium, high, mega]
    mapping(PricingTier => uint256[5]) public tierPricing;
    
    /// @notice Main data mappings
    mapping(uint256 => Tournament) public tournaments;
    mapping(uint256 => mapping(address => UserTeam)) public userTeams;
    mapping(uint256 => Player) public players;
    mapping(uint256 => TournamentResult[]) public tournamentResults;
    mapping(uint256 => address[]) public tournamentParticipants;
    
    /// @notice User statistics
    mapping(address => uint256) public userTotalWinnings;
    mapping(address => uint256) public userTournamentCount;
    mapping(address => PricingTier) public userPricingTier;
    
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event TournamentCreated(
        uint256 indexed tournamentId,
        uint256 entryFee,
        TournamentType tournamentType,
        PricingTier pricingTier,
        string name
    );
    
    event PlayerJoinedTournament(
        uint256 indexed tournamentId,
        address indexed player,
        uint256 captainId,
        Formation formation,
        PricingTier userTier
    );
    
    event TournamentSettled(
        uint256 indexed tournamentId,
        address[] winners,
        uint256[] prizes,
        uint256 totalPrizePool
    );
    
    event PlayerAdded(
        uint256 indexed playerId,
        string name,
        string team,
        Position position
    );
    
    event PlayerPointsUpdated(
        uint256 indexed playerId,
        uint256 gameweekPoints,
        uint256 totalSeasonPoints
    );
    
    event PricingTierUpdated(
        address indexed user,
        PricingTier oldTier,
        PricingTier newTier
    );
    
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    
    error InvalidTournament();
    error RegistrationClosed();
    error TournamentFull();
    error AlreadyJoined();
    error InvalidTeamSelection();
    error TournamentNotEnded();
    error AlreadySettled();
    error InvalidArrayLength();
    error PlayerNotExists();
    error Unauthorized();
    error InvalidPricingTier();
    error InsufficientFee();
    
    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    constructor(address _usdcAddress, address _initialOwner) Ownable(_initialOwner) {
        if (_usdcAddress == address(0)) revert InvalidTournament();
        
        USDC = IERC20(_usdcAddress);
        
        // Initialize regional pricing (USDC has 6 decimals)
        tierPricing[PricingTier.Tier1] = [2_000000, 10_000000, 25_000000, 50_000000, 100_000000];
        tierPricing[PricingTier.Tier2] = [3_000000, 15_000000, 35_000000, 75_000000, 150_000000];
        tierPricing[PricingTier.Tier3] = [5_000000, 20_000000, 50_000000, 100_000000, 250_000000];
    }
    
    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    
    modifier validTournament(uint256 _tournamentId) {
        if (_tournamentId > tournamentCounter || _tournamentId == 0) {
            revert InvalidTournament();
        }
        _;
    }
    
    modifier validPlayer(uint256 _playerId) {
        if (_playerId > playerCounter || _playerId == 0) {
            revert PlayerNotExists();
        }
        _;
    }
    
    /*//////////////////////////////////////////////////////////////
                            USER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Set user's regional pricing tier
     * @param _user User address
     * @param _tier Pricing tier
     */
    function setUserPricingTier(address _user, PricingTier _tier) external {
        if (msg.sender != _user && msg.sender != owner()) {
            revert Unauthorized();
        }
        
        PricingTier oldTier = userPricingTier[_user];
        userPricingTier[_user] = _tier;
        
        emit PricingTierUpdated(_user, oldTier, _tier);
    }
    
    /**
     * @notice Join tournament with team selection
     * @param _tournamentId Tournament ID
     * @param _startingEleven Array of 11 player IDs
     * @param _bench Array of 4 bench player IDs  
     * @param _captainId Captain player ID
     * @param _viceCaptainId Vice-captain player ID
     * @param _formation Team formation
     */
    function joinTournament(
        uint256 _tournamentId,
        uint256[11] calldata _startingEleven,
        uint256[4] calldata _bench,
        uint256 _captainId,
        uint256 _viceCaptainId,
        Formation _formation
    ) external nonReentrant whenNotPaused validTournament(_tournamentId) {
        Tournament storage tournament = tournaments[_tournamentId];
        
        if (!tournament.isActive) revert InvalidTournament();
        if (block.timestamp >= tournament.startTime) revert RegistrationClosed();
        if (tournament.currentParticipants >= tournament.maxParticipants) revert TournamentFull();
        if (userTeams[_tournamentId][msg.sender].hasParticipated) revert AlreadyJoined();
        
        // Validate team selection
        if (!_validateTeam(_startingEleven, _bench, _captainId, _viceCaptainId, _formation)) {
            revert InvalidTeamSelection();
        }
        
        // Calculate entry fee based on user's tier
        PricingTier userTier = userPricingTier[msg.sender];
        uint256 entryFee = _calculateEntryFee(tournament.entryFee, tournament.pricingTier, userTier);
        
        // Transfer USDC from user
        USDC.safeTransferFrom(msg.sender, address(this), entryFee);
        
        // Store user team
        userTeams[_tournamentId][msg.sender] = UserTeam({
            startingEleven: _startingEleven,
            bench: _bench,
            captainId: _captainId,
            viceCaptainId: _viceCaptainId,
            formation: _formation,
            totalScore: 0,
            hasParticipated: true,
            chipsUsed: false,
            userTier: userTier
        });
        
        // Update tournament state
        tournament.currentParticipants++;
        tournament.totalPrizePool += entryFee;
        tournamentParticipants[_tournamentId].push(msg.sender);
        userTournamentCount[msg.sender]++;
        
        emit PlayerJoinedTournament(_tournamentId, msg.sender, _captainId, _formation, userTier);
    }
    
    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Create new tournament
     */
    function createTournament(
        uint256 _entryFeeIndex,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _maxParticipants,
        TournamentType _tournamentType,
        PricingTier _pricingTier,
        string memory _name,
        string memory _gameweek
    ) external onlyOwner {
        if (_startTime <= block.timestamp) revert InvalidTournament();
        if (_endTime <= _startTime) revert InvalidTournament();
        if (_maxParticipants == 0) revert InvalidTournament();
        if (_entryFeeIndex >= 5) revert InvalidPricingTier();
        
        uint256 entryFee = tierPricing[_pricingTier][_entryFeeIndex];
        tournamentCounter++;
        
        tournaments[tournamentCounter] = Tournament({
            entryFee: entryFee,
            startTime: _startTime,
            endTime: _endTime,
            maxParticipants: _maxParticipants,
            currentParticipants: 0,
            totalPrizePool: 0,
            tournamentType: _tournamentType,
            pricingTier: _pricingTier,
            isActive: true,
            isSettled: false,
            name: _name,
            gameweek: _gameweek
        });
        
        emit TournamentCreated(tournamentCounter, entryFee, _tournamentType, _pricingTier, _name);
    }
    
    /**
     * @notice Add new player
     */
    function addPlayer(
        string memory _name,
        string memory _team,
        Position _position,
        uint256 _price,
        string memory _imageUrl
    ) external onlyOwner {
        playerCounter++;
        
        players[playerCounter] = Player({
            name: _name,
            team: _team,
            position: _position,
            price: _price,
            isActive: true,
            gameweekPoints: 0,
            totalSeasonPoints: 0,
            imageUrl: _imageUrl
        });
        
        emit PlayerAdded(playerCounter, _name, _team, _position);
    }
    
    /**
     * @notice Update player points
     */
    function updatePlayerPoints(
        uint256 _playerId,
        uint256 _gameweekPoints
    ) external onlyOwner validPlayer(_playerId) {
        players[_playerId].gameweekPoints = _gameweekPoints;
        players[_playerId].totalSeasonPoints += _gameweekPoints;
        
        emit PlayerPointsUpdated(_playerId, _gameweekPoints, players[_playerId].totalSeasonPoints);
    }
    
    /**
     * @notice Calculate user score for tournament
     */
    function calculateUserScore(
        uint256 _tournamentId,
        address _user
    ) external onlyOwner validTournament(_tournamentId) returns (uint256) {
        UserTeam storage team = userTeams[_tournamentId][_user];
        if (!team.hasParticipated) revert InvalidTeamSelection();
        
        uint256 totalScore = 0;
        
        // Calculate points for starting eleven
        for (uint256 i = 0; i < 11; i++) {
            uint256 playerId = team.startingEleven[i];
            uint256 playerPoints = players[playerId].gameweekPoints;
            
            // Double points for captain
            if (playerId == team.captainId) {
                playerPoints *= 2;
            }
            
            totalScore += playerPoints;
        }
        
        team.totalScore = totalScore;
        return totalScore;
    }
    
    /**
     * @notice Settle tournament and distribute prizes
     */
    function settleTournament(
        uint256 _tournamentId,
        address[] calldata _winners,
        uint256[] calldata _finalScores
    ) external onlyOwner nonReentrant validTournament(_tournamentId) {
        Tournament storage tournament = tournaments[_tournamentId];
        
        if (!tournament.isActive) revert InvalidTournament();
        if (block.timestamp <= tournament.endTime) revert TournamentNotEnded();
        if (tournament.isSettled) revert AlreadySettled();
        if (_winners.length != _finalScores.length) revert InvalidArrayLength();
        if (_winners.length == 0 || _winners.length > 10) revert InvalidArrayLength();
        
        tournament.isSettled = true;
        tournament.isActive = false;
        
        uint256 platformFee = (tournament.totalPrizePool * PLATFORM_FEE_BPS) / BPS_DENOMINATOR;
        uint256 remainingPool = tournament.totalPrizePool - platformFee;
        
        uint256[] memory prizes = _calculatePrizeDistribution(remainingPool, _winners.length);
        
        // Store results and transfer prizes
        for (uint256 i = 0; i < _winners.length; i++) {
            tournamentResults[_tournamentId].push(TournamentResult({
                user: _winners[i],
                finalScore: _finalScores[i],
                rank: i + 1,
                prizeWon: prizes[i]
            }));
            
            userTotalWinnings[_winners[i]] += prizes[i];
            
            if (prizes[i] > 0) {
                USDC.safeTransfer(_winners[i], prizes[i]);
            }
        }
        
        // Transfer platform fee
        if (platformFee > 0) {
            USDC.safeTransfer(owner(), platformFee);
        }
        
        emit TournamentSettled(_tournamentId, _winners, prizes, tournament.totalPrizePool);
    }
    
    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function _calculateEntryFee(
        uint256 _baseFee,
        PricingTier _tournamentTier,
        PricingTier _userTier
    ) internal pure returns (uint256) {
        if (_tournamentTier == _userTier) {
            return _baseFee;
        }
        
        if (_userTier == PricingTier.Tier1) {
            return (_baseFee * 4000) / BPS_DENOMINATOR; // 60% discount
        } else if (_userTier == PricingTier.Tier2) {
            return (_baseFee * 7000) / BPS_DENOMINATOR; // 30% discount
        }
        
        return _baseFee;
    }
    
    function _calculatePrizeDistribution(
        uint256 _remainingPool,
        uint256 _numWinners
    ) internal pure returns (uint256[] memory) {
        uint256[] memory prizes = new uint256[](_numWinners);
        
        if (_numWinners == 1) {
            prizes[0] = _remainingPool;
        } else if (_numWinners == 2) {
            prizes[0] = (_remainingPool * 7000) / BPS_DENOMINATOR; // 70%
            prizes[1] = (_remainingPool * 3000) / BPS_DENOMINATOR; // 30%
        } else if (_numWinners == 3) {
            prizes[0] = (_remainingPool * 6000) / BPS_DENOMINATOR; // 60%
            prizes[1] = (_remainingPool * 2500) / BPS_DENOMINATOR; // 25%
            prizes[2] = (_remainingPool * 1500) / BPS_DENOMINATOR; // 15%
        } else {
            // For 4+ winners, distribute more evenly
            prizes[0] = (_remainingPool * 4000) / BPS_DENOMINATOR; // 40%
            prizes[1] = (_remainingPool * 2000) / BPS_DENOMINATOR; // 20%
            prizes[2] = (_remainingPool * 1500) / BPS_DENOMINATOR; // 15%
            
            uint256 remaining = (_remainingPool * 2500) / BPS_DENOMINATOR; // 25%
            for (uint256 i = 3; i < _numWinners; i++) {
                prizes[i] = remaining / (_numWinners - 3);
            }
        }
        
        return prizes;
    }
    
    function _validateTeam(
        uint256[11] calldata _startingEleven,
        uint256[4] calldata _bench,
        uint256 _captainId,
        uint256 _viceCaptainId,
        Formation _formation
    ) internal view returns (bool) {
        // Check players exist and are active
        for (uint256 i = 0; i < 11; i++) {
            if (_startingEleven[i] > playerCounter || _startingEleven[i] == 0) return false;
            if (!players[_startingEleven[i]].isActive) return false;
        }
        
        for (uint256 i = 0; i < 4; i++) {
            if (_bench[i] > playerCounter || _bench[i] == 0) return false;
            if (!players[_bench[i]].isActive) return false;
        }
        
        // Check for duplicates
        for (uint256 i = 0; i < 11; i++) {
            for (uint256 j = i + 1; j < 11; j++) {
                if (_startingEleven[i] == _startingEleven[j]) return false;
            }
        }
        
        // Validate captain/vice-captain
        bool captainFound = false;
        bool viceCaptainFound = false;
        for (uint256 i = 0; i < 11; i++) {
            if (_startingEleven[i] == _captainId) captainFound = true;
            if (_startingEleven[i] == _viceCaptainId) viceCaptainFound = true;
        }
        
        if (!captainFound || !viceCaptainFound || _captainId == _viceCaptainId) return false;
        
        return _validateFormation(_startingEleven, _formation);
    }
    
    function _validateFormation(
        uint256[11] calldata _startingEleven,
        Formation _formation
    ) internal view returns (bool) {
        uint256[4] memory positionCounts; // [GK, DEF, MID, FWD]
        
        for (uint256 i = 0; i < 11; i++) {
            positionCounts[uint256(players[_startingEleven[i]].position)]++;
        }
        
        // Must have exactly 1 goalkeeper
        if (positionCounts[0] != 1) return false;
        
        // Check formation requirements
        if (_formation == Formation.F343) {
            return (positionCounts[1] == 3 && positionCounts[2] == 4 && positionCounts[3] == 3);
        } else if (_formation == Formation.F352) {
            return (positionCounts[1] == 3 && positionCounts[2] == 5 && positionCounts[3] == 2);
        } else if (_formation == Formation.F433) {
            return (positionCounts[1] == 4 && positionCounts[2] == 3 && positionCounts[3] == 3);
        } else if (_formation == Formation.F442) {
            return (positionCounts[1] == 4 && positionCounts[2] == 4 && positionCounts[3] == 2);
        } else if (_formation == Formation.F451) {
            return (positionCounts[1] == 4 && positionCounts[2] == 5 && positionCounts[3] == 1);
        } else if (_formation == Formation.F532) {
            return (positionCounts[1] == 5 && positionCounts[2] == 3 && positionCounts[3] == 2);
        } else if (_formation == Formation.F541) {
            return (positionCounts[1] == 5 && positionCounts[2] == 4 && positionCounts[3] == 1);
        }
        
        return false;
    }
    
    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function getTournament(uint256 _tournamentId) external view returns (Tournament memory) {
        return tournaments[_tournamentId];
    }
    
    function getUserTeam(uint256 _tournamentId, address _user) external view returns (UserTeam memory) {
        return userTeams[_tournamentId][_user];
    }
    
    function getPlayer(uint256 _playerId) external view returns (Player memory) {
        return players[_playerId];
    }
    
    function getTournamentResults(uint256 _tournamentId) external view returns (TournamentResult[] memory) {
        return tournamentResults[_tournamentId];
    }
    
    function getTierPricing(PricingTier _tier) external view returns (uint256[5] memory) {
        return tierPricing[_tier];
    }
    
    function getEffectiveEntryFee(
        uint256 _tournamentId,
        address _user
    ) external view returns (uint256) {
        Tournament memory tournament = tournaments[_tournamentId];
        PricingTier userTier = userPricingTier[_user];
        return _calculateEntryFee(tournament.entryFee, tournament.pricingTier, userTier);
    }
    
    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
    
    function emergencyWithdraw() external onlyOwner {
        uint256 balance = USDC.balanceOf(address(this));
        if (balance > 0) {
            USDC.safeTransfer(owner(), balance);
        }
    }
}
