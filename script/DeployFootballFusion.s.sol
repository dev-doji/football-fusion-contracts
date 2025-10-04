// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {PlayerNFT} from "../src/PlayerNFT.sol";
import {PrizeDistribution} from "../src/PrizeDistribution.sol";
import {ScoringEngine} from "../src/ScoringEngine.sol";
import {FootballFusionTournament} from "../src/FootballFusionTournament.sol";

/**
 * @title FootballFusion Deployment Script
 * @dev Deploys all contracts in correct order with proper initialization
 * @notice Run with: forge script script/DeployFootballFusion.s.sol --rpc-url $BASE_SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify
 */
contract DeployFootballFusion is Script {
    
    /*//////////////////////////////////////////////////////////////
                            CONFIGURATION
    //////////////////////////////////////////////////////////////*/
    
    // Base chain USDC addresses
    address public constant USDC_MAINNET = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913; // Base mainnet USDC
    address public constant USDC_TESTNET = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;  // Base testnet USDC
    
    // Deployment configuration
    struct DeploymentConfig {
        address deployer;
        address usdcAddress;
        bool isTestnet;
    }
    
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    
    PlayerNFT public playerNFT;
    PrizeDistribution public prizeDistribution;
    ScoringEngine public scoringEngine;
    FootballFusionTournament public tournament;
    
    DeploymentConfig public config;

    /*//////////////////////////////////////////////////////////////
                            MAIN DEPLOYMENT
    //////////////////////////////////////////////////////////////*/
    
    function run() external {
        // Setup deployment configuration
        _setupConfig();
        
        console.log("Starting FootballFusion deployment...");
        console.log("Deployer:", config.deployer);
        console.log("USDC Address:", config.usdcAddress);
        console.log("Is Testnet:", config.isTestnet);
        console.log("Chain ID:", block.chainid);
        
        vm.startBroadcast();
        
        // Deploy contracts in dependency order
        _deployPlayerNFT();
        _deployPrizeDistribution();
        _deployScoringEngine();
        _deployTournament();
        
        // Set up contract interactions
        _setupContractReferences();
        
        // Initialize with sample data if testnet
        if (config.isTestnet) {
            _initializeTestData();
        }
        
        vm.stopBroadcast();
        
        // Log deployment summary
        _logDeploymentSummary();
        
        console.log("Deployment completed successfully!");
    }

    /*//////////////////////////////////////////////////////////////
                            DEPLOYMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function _deployPlayerNFT() internal {
        console.log("Deploying PlayerNFT...");
        
        playerNFT = new PlayerNFT(
            config.usdcAddress,
            config.deployer  // Initial owner
        );
        
        console.log("PlayerNFT deployed at:", address(playerNFT));
        
        // Verify initial state
        require(playerNFT.owner() == config.deployer, "PlayerNFT: Incorrect owner");
        require(address(playerNFT.USDC()) == config.usdcAddress, "PlayerNFT: Incorrect USDC");
        require(playerNFT.currentSeason() == 1, "PlayerNFT: Incorrect initial season");
        require(playerNFT.packageCounter() == 3, "PlayerNFT: Default packages not initialized");
    }
    
    function _deployPrizeDistribution() internal {
        console.log("Deploying PrizeDistribution...");
        
        // Deploy with a temporary tournament address, then update it later
        prizeDistribution = new PrizeDistribution(
            config.usdcAddress,
            config.deployer, // Use deployer as temporary tournament address
            config.deployer  // Initial owner
        );
        
        console.log("PrizeDistribution deployed at:", address(prizeDistribution));
        
        // Verify initial state
        require(prizeDistribution.owner() == config.deployer, "PrizeDistribution: Incorrect owner");
        require(address(prizeDistribution.USDC()) == config.usdcAddress, "PrizeDistribution: Incorrect USDC");
        require(prizeDistribution.rulesCounter() == 3, "PrizeDistribution: Default rules not initialized");
    }
    
    function _deployScoringEngine() internal {
        console.log("Deploying ScoringEngine...");
        
        scoringEngine = new ScoringEngine(
            config.deployer  // Initial owner
        );
        
        console.log("ScoringEngine deployed at:", address(scoringEngine));
        
        // Verify initial state
        require(scoringEngine.owner() == config.deployer, "ScoringEngine: Incorrect owner");
        require(scoringEngine.currentGameweek() == 1, "ScoringEngine: Incorrect initial gameweek");
        
        // Verify scoring rules are initialized
        require(scoringEngine.getScoringRule("assist") == 3, "ScoringEngine: Scoring rules not initialized");
    }
    
    function _deployTournament() internal {
        console.log("Deploying FootballFusionTournament...");
        
        tournament = new FootballFusionTournament(
            config.usdcAddress,
            config.deployer  // Initial owner
        );
        
        console.log("FootballFusionTournament deployed at:", address(tournament));
        
        // Verify initial state
        require(tournament.owner() == config.deployer, "Tournament: Incorrect owner");
        require(address(tournament.USDC()) == config.usdcAddress, "Tournament: Incorrect USDC");
        require(tournament.tournamentCounter() == 0, "Tournament: Incorrect initial counter");
    }

    /*//////////////////////////////////////////////////////////////
                            SETUP FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function _setupContractReferences() internal {
        console.log("Setting up contract references...");
        
        // Set tournament contract address in PlayerNFT
        playerNFT.setTournamentContract(address(tournament));
        console.log("PlayerNFT tournament contract set");
        
        // Set tournament contract address in PrizeDistribution
        prizeDistribution.setTournamentContract(address(tournament));
        console.log("PrizeDistribution tournament contract set");
        
        // Set contract addresses in ScoringEngine
        scoringEngine.setContractAddresses(
            address(tournament),
            address(playerNFT)
        );
        console.log("ScoringEngine contract addresses set");
        
        // Set authorized updater for ScoringEngine (tournament contract)
        scoringEngine.setAuthorizedUpdater(address(tournament), true);
        console.log("ScoringEngine authorized updater set");
        
        // Verify all references are set correctly
        require(playerNFT.tournamentContract() == address(tournament), "PlayerNFT: Tournament reference not set");
        require(prizeDistribution.tournamentContract() == address(tournament), "PrizeDistribution: Tournament reference not set");
        require(scoringEngine.tournamentContract() == address(tournament), "ScoringEngine: Tournament reference not set");
        require(scoringEngine.playerNFTContract() == address(playerNFT), "ScoringEngine: PlayerNFT reference not set");
    }
    
    function _setupConfig() internal {
        config.deployer = msg.sender;
        
        // Determine if this is a testnet deployment
        config.isTestnet = _isTestnet();
        
        if (config.isTestnet) {
            // Use Base testnet USDC
            config.usdcAddress = USDC_TESTNET;
            console.log("Testnet deployment detected - using Base testnet USDC");
        } else {
            // Use Base mainnet USDC
            config.usdcAddress = USDC_MAINNET;
            console.log("Mainnet deployment detected - using Base mainnet USDC");
        }
    }
    
    function _isTestnet() internal view returns (bool) {
        // Check chain ID to determine if testnet
        uint256 chainId = block.chainid;
        
        // Base mainnet = 8453, Base Sepolia testnet = 84532
        return chainId == 84532 ||  // Base Sepolia testnet
               chainId == 31337 ||  // Hardhat/Anvil local
               chainId == 11155111 || // Ethereum Sepolia (if testing there)
               chainId == 5;         // Ethereum Goerli (if testing there)
    }

    /*//////////////////////////////////////////////////////////////
                            TEST DATA INITIALIZATION
    //////////////////////////////////////////////////////////////*/
    
    function _initializeTestData() internal {
        console.log("Initializing test data for testnet...");
        
        // Add some test players
        _addTestPlayers();
        
        // Create a test tournament
        _createTestTournament();
        
        console.log("Test data initialized");
    }
    
    function _addTestPlayers() internal {
        console.log("Adding test players...");
        
        // Add a few test players across all positions
        tournament.addPlayer(
            "Erling Haaland",
            "Manchester City",
            FootballFusionTournament.Position.FWD,
            1200_000000, // $1200
            "https://example.com/haaland.jpg"
        );
        
        tournament.addPlayer(
            "Kevin De Bruyne",
            "Manchester City", 
            FootballFusionTournament.Position.MID,
            1000_000000, // $1000
            "https://example.com/debruyne.jpg"
        );
        
        tournament.addPlayer(
            "Virgil van Dijk",
            "Liverpool",
            FootballFusionTournament.Position.DEF,
            800_000000, // $800
            "https://example.com/vandijk.jpg"
        );
        
        tournament.addPlayer(
            "Alisson Becker",
            "Liverpool",
            FootballFusionTournament.Position.GK,
            600_000000, // $600
            "https://example.com/alisson.jpg"
        );
        
        // Add more players for a complete team
        tournament.addPlayer(
            "Bukayo Saka",
            "Arsenal",
            FootballFusionTournament.Position.MID,
            900_000000,
            "https://example.com/saka.jpg"
        );
        
        tournament.addPlayer(
            "Gabriel Jesus",
            "Arsenal",
            FootballFusionTournament.Position.FWD,
            850_000000,
            "https://example.com/jesus.jpg"
        );
        
        tournament.addPlayer(
            "Reece James",
            "Chelsea",
            FootballFusionTournament.Position.DEF,
            750_000000,
            "https://example.com/james.jpg"
        );
        
        tournament.addPlayer(
            "Bruno Fernandes",
            "Manchester United",
            FootballFusionTournament.Position.MID,
            950_000000,
            "https://example.com/bruno.jpg"
        );
        
        console.log("Test players added:", tournament.playerCounter());
    }
    
    function _createTestTournament() internal {
        console.log("Creating test tournament...");
        
        tournament.createTournament(
            0, // Entry fee index (starter tier - $2)
            block.timestamp + 1 hours, // Start time
            block.timestamp + 1 days,  // End time
            100, // Max participants
            FootballFusionTournament.TournamentType.EPL,
            FootballFusionTournament.PricingTier.Tier1,
            "Test EPL Gameweek 1",
            "GW1"
        );
        
        console.log("Test tournament created with ID:", tournament.tournamentCounter());
    }

    /*//////////////////////////////////////////////////////////////
                            DEPLOYMENT SUMMARY
    //////////////////////////////////////////////////////////////*/
    
    function _logDeploymentSummary() internal view {
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", config.deployer);
        console.log("USDC Address:", config.usdcAddress);
        console.log("Is Testnet:", config.isTestnet);
        console.log("");
        console.log("Contract Addresses:");
        console.log("PlayerNFT:", address(playerNFT));
        console.log("PrizeDistribution:", address(prizeDistribution));
        console.log("ScoringEngine:", address(scoringEngine));
        console.log("FootballFusionTournament:", address(tournament));
        console.log("");
        console.log("Contract Verification:");
        console.log("PlayerNFT owner:", playerNFT.owner());
        console.log("PrizeDistribution owner:", prizeDistribution.owner());
        console.log("ScoringEngine owner:", scoringEngine.owner());
        console.log("Tournament owner:", tournament.owner());
        console.log("");
        console.log("Contract References:");
        console.log("PlayerNFT tournament:", playerNFT.tournamentContract());
        console.log("PrizeDistribution tournament:", prizeDistribution.tournamentContract());
        console.log("ScoringEngine tournament:", scoringEngine.tournamentContract());
        console.log("ScoringEngine playerNFT:", scoringEngine.playerNFTContract());
        
        if (config.isTestnet) {
            console.log("");
            console.log("Test Data:");
            console.log("Test players added:", tournament.playerCounter());
            console.log("Test tournaments created:", tournament.tournamentCounter());
        }
        
        console.log("========================");
    }
}

/*//////////////////////////////////////////////////////////////
                        VERIFICATION HELPER
//////////////////////////////////////////////////////////////*/

/**
 * @title Deployment Verification Helper
 * @dev Use this to verify deployment after the fact
 */
contract VerifyDeployment is Script {
    
    function verifyContracts(
        address _playerNFT,
        address _prizeDistribution, 
        address _scoringEngine,
        address _tournament,
        address _expectedOwner,
        address _expectedUSDC
    ) external view {
        console.log("Verifying deployment...");
        
        PlayerNFT playerNFT = PlayerNFT(_playerNFT);
        PrizeDistribution prizeDistribution = PrizeDistribution(_prizeDistribution);
        ScoringEngine scoringEngine = ScoringEngine(_scoringEngine);
        FootballFusionTournament tournament = FootballFusionTournament(_tournament);
        
        // Verify ownership
        require(playerNFT.owner() == _expectedOwner, "PlayerNFT: Wrong owner");
        require(prizeDistribution.owner() == _expectedOwner, "PrizeDistribution: Wrong owner");
        require(scoringEngine.owner() == _expectedOwner, "ScoringEngine: Wrong owner");
        require(tournament.owner() == _expectedOwner, "Tournament: Wrong owner");
        
        // Verify USDC addresses
        require(address(playerNFT.USDC()) == _expectedUSDC, "PlayerNFT: Wrong USDC");
        require(address(prizeDistribution.USDC()) == _expectedUSDC, "PrizeDistribution: Wrong USDC");
        require(address(tournament.USDC()) == _expectedUSDC, "Tournament: Wrong USDC");
        
        // Verify contract references
        require(playerNFT.tournamentContract() == _tournament, "PlayerNFT: Wrong tournament ref");
        require(prizeDistribution.tournamentContract() == _tournament, "PrizeDistribution: Wrong tournament ref");
        require(scoringEngine.tournamentContract() == _tournament, "ScoringEngine: Wrong tournament ref");
        require(scoringEngine.playerNFTContract() == _playerNFT, "ScoringEngine: Wrong playerNFT ref");
        
        console.log("All contracts verified successfully!");
    }
}