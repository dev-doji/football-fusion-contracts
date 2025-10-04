// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.4.0
pragma solidity ^0.8.30;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {ERC721Pausable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title FootballFusion Player NFT Contract
 * @dev ERC721 NFTs representing football player ownership with contract system
 * @author FootballFusion Team
 * @notice Players have contracts (usage limits) and can be traded on marketplace
 */
contract PlayerNFT is ERC721, ERC721Enumerable, ERC721URIStorage, ERC721Pausable, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/
    
    enum Position { GK, DEF, MID, FWD }
    enum Rarity { Common, Rare, Epic, Legendary }
    enum PlayerStatus { Active, Injured, Suspended, Retired }

    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/
    
    struct PlayerData {
        string name;
        string team;
        Position position;
        Rarity rarity;
        PlayerStatus status;
        uint256 basePrice;              // Base price in USDC
        uint256 currentPrice;           // Current market price
        uint256 contractsRemaining;     // Matches the player can be used
        uint256 maxContracts;           // Maximum contracts per season
        uint256 totalSeasonPoints;      // Points scored this season
        uint256 gameweekPoints;         // Points in current gameweek
        uint256 averagePoints;          // Rolling average points
        uint256 lastUpdated;            // Last stats update timestamp
        bool isActive;                  // Can be used in tournaments
        string nationality;             // Player nationality
        uint256 age;                    // Player age
        uint256 transferValue;          // Real-world transfer value
    }

    struct ContractPackage {
        uint256 contracts;              // Number of contracts
        uint256 priceInUSDC;           // Price in USDC (6 decimals)
        uint256 bonusPercentage;        // Bonus contracts percentage
        bool isActive;
    }

    struct MarketListing {
        address seller;
        uint256 price;                  // Price in USDC
        uint256 listedAt;
        bool isActive;
        uint256 contractsIncluded;      // Contracts included in sale
    }

    struct PlayerStats {
        uint256 gamesPlayed;
        uint256 goals;
        uint256 assists;
        uint256 cleanSheets;
        uint256 yellowCards;
        uint256 redCards;
        uint256 saves;                  // For goalkeepers
        uint256 passAccuracy;           // Percentage (0-100)
        uint256 shotsOnTarget;
        uint256 tacklesWon;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    
    /// @notice USDC contract on Base
    IERC20 public immutable USDC;
    
    /// @notice Tournament contract address
    address public tournamentContract;
    
    /// @notice Marketplace fee (2.5% = 250/10000)
    uint256 public constant MARKETPLACE_FEE_BPS = 250;
    uint256 private constant BPS_DENOMINATOR = 10_000;
    
    /// @notice Token ID counter
    uint256 private _nextTokenId = 1;
    
    /// @notice Contract packages
    mapping(uint256 => ContractPackage) public contractPackages;
    uint256 public packageCounter;
    
    /// @notice Player data
    mapping(uint256 => PlayerData) public players;
    mapping(uint256 => PlayerStats) public playerStats;
    
    /// @notice Marketplace
    mapping(uint256 => MarketListing) public marketListings;
    mapping(address => uint256[]) public userListings;
    
    /// @notice Contract renewal tracking
    mapping(uint256 => uint256) public lastRenewalTime;
    mapping(address => uint256) public userContractSpending;
    
    /// @notice Player ownership tracking
    mapping(address => uint256[]) public userOwnedPlayers;
    mapping(uint256 => uint256) public playerToOwnerIndex;
    
    /// @notice Season management
    uint256 public currentSeason;
    uint256 public seasonStartTime;
    
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event PlayerMinted(
        uint256 indexed tokenId,
        address indexed to,
        string name,
        Position position,
        Rarity rarity
    );
    
    event PlayerListed(
        uint256 indexed tokenId,
        address indexed seller,
        uint256 price,
        uint256 contractsIncluded
    );
    
    event PlayerSold(
        uint256 indexed tokenId,
        address indexed seller,
        address indexed buyer,
        uint256 price
    );
    
    event ContractsRenewed(
        uint256 indexed tokenId,
        address indexed owner,
        uint256 contractsAdded,
        uint256 pricePaid
    );
    
    event PlayerStatsUpdated(
        uint256 indexed tokenId,
        uint256 gameweekPoints,
        uint256 totalSeasonPoints
    );
    
    event ContractPackageAdded(
        uint256 indexed packageId,
        uint256 contracts,
        uint256 price
    );
    
    event SeasonStarted(
        uint256 indexed season,
        uint256 startTime
    );

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    
    error PlayerNotExists();
    error NotOwnerOrApproved();
    error PlayerNotActive();
    error InsufficientContracts();
    error InvalidPrice();
    error ListingNotFound();
    error NotSeller();
    error InvalidPackage();
    error ContractCooldown();
    error InvalidParameters();
    error MarketplacePaused();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    constructor(
        address _usdcAddress,
        address _initialOwner
    ) ERC721("FootballFusion Player", "FFP") Ownable(_initialOwner) {
        if (_usdcAddress == address(0)) revert InvalidParameters();
        
        USDC = IERC20(_usdcAddress);
        currentSeason = 1;
        seasonStartTime = block.timestamp;
        
        // Initialize default contract packages
        _initializeContractPackages();
    }

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    
    modifier validPlayer(uint256 tokenId) {
        if (_ownerOf(tokenId) == address(0)) revert PlayerNotExists();
        _;
    }
    
    modifier onlyTournament() {
        if (msg.sender != tournamentContract) revert NotOwnerOrApproved();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            MINTING FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Mint new player NFT
     * @param to Recipient address
     * @param name Player name
     * @param team Player team
     * @param position Player position
     * @param rarity Player rarity
     * @param basePrice Base price in USDC
     * @param nationality Player nationality
     * @param age Player age
     * @param imageUrl Player image URL
     */
    function mintPlayer(
        address to,
        string memory name,
        string memory team,
        Position position,
        Rarity rarity,
        uint256 basePrice,
        string memory nationality,
        uint256 age,
        string memory imageUrl
    ) external onlyOwner returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        
        // Determine max contracts based on rarity
        uint256 maxContracts = _getMaxContractsByRarity(rarity);
        
        players[tokenId] = PlayerData({
            name: name,
            team: team,
            position: position,
            rarity: rarity,
            status: PlayerStatus.Active,
            basePrice: basePrice,
            currentPrice: basePrice,
            contractsRemaining: maxContracts,
            maxContracts: maxContracts,
            totalSeasonPoints: 0,
            gameweekPoints: 0,
            averagePoints: 0,
            lastUpdated: block.timestamp,
            isActive: true,
            nationality: nationality,
            age: age,
            transferValue: basePrice * 10 // Rough estimate
        });
        
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, imageUrl);
        
        emit PlayerMinted(tokenId, to, name, position, rarity);
        
        return tokenId;
    }
    
    /**
     * @notice Batch mint multiple players
     * @param recipients Array of recipient addresses
     * @param names Array of player names
     * @param teams Array of player teams
     * @param positions Array of player positions
     * @param rarities Array of player rarities
     * @param basePrices Array of base prices
     * @param nationalities Array of nationalities
     * @param ages Array of ages
     * @param imageUrls Array of image URLs
     */
    function batchMintPlayers(
        address[] calldata recipients,
        string[] calldata names,
        string[] calldata teams,
        Position[] calldata positions,
        Rarity[] calldata rarities,
        uint256[] calldata basePrices,
        string[] calldata nationalities,
        uint256[] calldata ages,
        string[] calldata imageUrls
    ) external onlyOwner {
        if (recipients.length != names.length || 
            recipients.length != teams.length ||
            recipients.length != positions.length ||
            recipients.length != rarities.length ||
            recipients.length != basePrices.length ||
            recipients.length != nationalities.length ||
            recipients.length != ages.length ||
            recipients.length != imageUrls.length) {
            revert InvalidParameters();
        }
        
        for (uint256 i = 0; i < recipients.length; i++) {
            uint256 tokenId = _nextTokenId++;
            
            // Determine max contracts based on rarity
            uint256 maxContracts = _getMaxContractsByRarity(rarities[i]);
            
            players[tokenId] = PlayerData({
                name: names[i],
                team: teams[i],
                position: positions[i],
                rarity: rarities[i],
                status: PlayerStatus.Active,
                basePrice: basePrices[i],
                currentPrice: basePrices[i],
                contractsRemaining: maxContracts,
                maxContracts: maxContracts,
                totalSeasonPoints: 0,
                gameweekPoints: 0,
                averagePoints: 0,
                lastUpdated: block.timestamp,
                isActive: true,
                nationality: nationalities[i],
                age: ages[i],
                transferValue: basePrices[i] * 10
            });
            
            _safeMint(recipients[i], tokenId);
            _setTokenURI(tokenId, imageUrls[i]);
            
            emit PlayerMinted(tokenId, recipients[i], names[i], positions[i], rarities[i]);
        }
    }

    /*//////////////////////////////////////////////////////////////
                            CONTRACT MANAGEMENT
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Use player contract for tournament
     * @param tokenId Player token ID
     * @param user Player owner
     */
    function usePlayerContract(uint256 tokenId, address user) external onlyTournament validPlayer(tokenId) {
        if (ownerOf(tokenId) != user) revert NotOwnerOrApproved();
        if (!players[tokenId].isActive) revert PlayerNotActive();
        if (players[tokenId].contractsRemaining == 0) revert InsufficientContracts();
        
        players[tokenId].contractsRemaining--;
    }
    
    /**
     * @notice Renew player contracts
     * @param tokenId Player token ID
     * @param packageId Contract package ID
     */
    function renewContracts(
        uint256 tokenId,
        uint256 packageId
    ) external nonReentrant whenNotPaused validPlayer(tokenId) {
        if (ownerOf(tokenId) != msg.sender) revert NotOwnerOrApproved();
        if (packageId > packageCounter || !contractPackages[packageId].isActive) {
            revert InvalidPackage();
        }
        
        // Cooldown check (24 hours)
     
if (lastRenewalTime[tokenId] != 0 && block.timestamp < lastRenewalTime[tokenId] + 1 days) {
    revert ContractCooldown();
}
        ContractPackage memory package = contractPackages[packageId];
        uint256 totalContracts = package.contracts;
        
        // Apply bonus
        if (package.bonusPercentage > 0) {
            totalContracts += (totalContracts * package.bonusPercentage) / 100;
        }
        
        // Transfer USDC
        USDC.safeTransferFrom(msg.sender, address(this), package.priceInUSDC);
        
        // Update player contracts
        players[tokenId].contractsRemaining += totalContracts;
        lastRenewalTime[tokenId] = block.timestamp;
        userContractSpending[msg.sender] += package.priceInUSDC;
        
        emit ContractsRenewed(tokenId, msg.sender, totalContracts, package.priceInUSDC);
    }

    /*//////////////////////////////////////////////////////////////
                            MARKETPLACE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice List player for sale
     * @param tokenId Player token ID
     * @param price Sale price in USDC
     */
    function listPlayer(
        uint256 tokenId,
        uint256 price
    ) external nonReentrant whenNotPaused validPlayer(tokenId) {
        if (ownerOf(tokenId) != msg.sender) revert NotOwnerOrApproved();
        if (price == 0) revert InvalidPrice();
        
        marketListings[tokenId] = MarketListing({
            seller: msg.sender,
            price: price,
            listedAt: block.timestamp,
            isActive: true,
            contractsIncluded: players[tokenId].contractsRemaining
        });
        
        userListings[msg.sender].push(tokenId);
        
        emit PlayerListed(tokenId, msg.sender, price, players[tokenId].contractsRemaining);
    }
    
    /**
     * @notice Buy listed player
     * @param tokenId Player token ID
     */
    function buyPlayer(uint256 tokenId) external nonReentrant whenNotPaused validPlayer(tokenId) {
        MarketListing storage listing = marketListings[tokenId];
        
        if (!listing.isActive) revert ListingNotFound();
        if (listing.seller == msg.sender) revert NotSeller();
        
        address seller = listing.seller;
        uint256 price = listing.price;
        
        // Calculate marketplace fee
        uint256 marketplaceFee = (price * MARKETPLACE_FEE_BPS) / BPS_DENOMINATOR;
        uint256 sellerAmount = price - marketplaceFee;
        
        // Transfer USDC
        USDC.safeTransferFrom(msg.sender, seller, sellerAmount);
        USDC.safeTransferFrom(msg.sender, owner(), marketplaceFee);
        
        // Transfer NFT
        _transfer(seller, msg.sender, tokenId);
        
        // Update listing
        listing.isActive = false;
        
        // Update player price
        players[tokenId].currentPrice = price;
        
        emit PlayerSold(tokenId, seller, msg.sender, price);
    }
    
    /**
     * @notice Cancel player listing
     * @param tokenId Player token ID
     */
    function cancelListing(uint256 tokenId) external validPlayer(tokenId) {
        MarketListing storage listing = marketListings[tokenId];
        
        if (listing.seller != msg.sender) revert NotSeller();
        if (!listing.isActive) revert ListingNotFound();
        
        listing.isActive = false;
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Update player stats
     * @param tokenId Player token ID
     * @param gameweekPoints Points for current gameweek
     * @param statsData Updated stats data
     */
    function updatePlayerStats(
        uint256 tokenId,
        uint256 gameweekPoints,
        PlayerStats calldata statsData
    ) external onlyOwner validPlayer(tokenId) {
        players[tokenId].gameweekPoints = gameweekPoints;
        players[tokenId].totalSeasonPoints += gameweekPoints;
        players[tokenId].lastUpdated = block.timestamp;
        
        // Update rolling average (last 5 gameweeks)
        if (statsData.gamesPlayed > 0) {
            players[tokenId].averagePoints = players[tokenId].totalSeasonPoints / statsData.gamesPlayed;
        }
        
        playerStats[tokenId] = statsData;
        
        emit PlayerStatsUpdated(tokenId, gameweekPoints, players[tokenId].totalSeasonPoints);
    }
    
    /**
     * @notice Add contract package
     * @param contracts Number of contracts
     * @param priceInUSDC Price in USDC
     * @param bonusPercentage Bonus percentage
     */
    function addContractPackage(
        uint256 contracts,
        uint256 priceInUSDC,
        uint256 bonusPercentage
    ) external onlyOwner {
        packageCounter++;
        
        contractPackages[packageCounter] = ContractPackage({
            contracts: contracts,
            priceInUSDC: priceInUSDC,
            bonusPercentage: bonusPercentage,
            isActive: true
        });
        
        emit ContractPackageAdded(packageCounter, contracts, priceInUSDC);
    }
    
    /**
     * @notice Start new season
     */
    function startNewSeason() external onlyOwner {
        currentSeason++;
        seasonStartTime = block.timestamp;
        
        // Reset all player stats for new season
        uint256 totalPlayers = totalSupply();
        for (uint256 i = 1; i < totalPlayers + 1; i++) {
            if (_ownerOf(i) != address(0)) {
                players[i].totalSeasonPoints = 0;
                players[i].gameweekPoints = 0;
                players[i].averagePoints = 0;
                players[i].contractsRemaining = players[i].maxContracts;
            }
        }
        
        emit SeasonStarted(currentSeason, seasonStartTime);
    }
    
    /**
     * @notice Set tournament contract address
     * @param _tournamentContract Tournament contract address
     */
    function setTournamentContract(address _tournamentContract) external onlyOwner {
        tournamentContract = _tournamentContract;
    }
    
    /**
     * @notice Emergency withdrawal
     */
    function emergencyWithdraw() external onlyOwner {
        uint256 balance = USDC.balanceOf(address(this));
        if (balance > 0) {
            USDC.safeTransfer(owner(), balance);
        }
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function _getMaxContractsByRarity(Rarity rarity) internal pure returns (uint256) {
        if (rarity == Rarity.Common) return 15;
        if (rarity == Rarity.Rare) return 20;
        if (rarity == Rarity.Epic) return 25;
        if (rarity == Rarity.Legendary) return 38; // Full season
        return 15;
    }
    
    function _initializeContractPackages() internal {
        // Package 1: 5 contracts for $5
        packageCounter++;
        contractPackages[packageCounter] = ContractPackage({
            contracts: 5,
            priceInUSDC: 5_000000,
            bonusPercentage: 0,
            isActive: true
        });
        
        // Package 2: 10 contracts for $9 (10% bonus)
        packageCounter++;
        contractPackages[packageCounter] = ContractPackage({
            contracts: 10,
            priceInUSDC: 9_000000,
            bonusPercentage: 10,
            isActive: true
        });
        
        // Package 3: 20 contracts for $17 (15% bonus)
        packageCounter++;
        contractPackages[packageCounter] = ContractPackage({
            contracts: 20,
            priceInUSDC: 17_000000,
            bonusPercentage: 15,
            isActive: true
        });
    }
    
    function _addPlayerToOwner(address owner, uint256 tokenId) internal {
        userOwnedPlayers[owner].push(tokenId);
        playerToOwnerIndex[tokenId] = userOwnedPlayers[owner].length - 1;
    }
    
    function _removePlayerFromOwner(address owner, uint256 tokenId) internal {
        uint256[] storage ownedPlayers = userOwnedPlayers[owner];
        uint256 playerIndex = playerToOwnerIndex[tokenId];
        uint256 lastPlayerIndex = ownedPlayers.length - 1;
        
        if (playerIndex != lastPlayerIndex) {
            uint256 lastTokenId = ownedPlayers[lastPlayerIndex];
            ownedPlayers[playerIndex] = lastTokenId;
            playerToOwnerIndex[lastTokenId] = playerIndex;
        }
        
        ownedPlayers.pop();
        delete playerToOwnerIndex[tokenId];
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function getPlayer(uint256 tokenId) external view returns (PlayerData memory) {
        return players[tokenId];
    }
    
    function getPlayerStats(uint256 tokenId) external view returns (PlayerStats memory) {
        return playerStats[tokenId];
    }
    
    function getUserOwnedPlayers(address user) external view returns (uint256[] memory) {
        return userOwnedPlayers[user];
    }
    
    function getMarketListing(uint256 tokenId) external view returns (MarketListing memory) {
        return marketListings[tokenId];
    }
    
    function getContractPackage(uint256 packageId) external view returns (ContractPackage memory) {
        return contractPackages[packageId];
    }
    
    function canUsePlayer(uint256 tokenId, address user) external view returns (bool) {
        if (_ownerOf(tokenId) == address(0)) return false;
        if (ownerOf(tokenId) != user) return false;
        if (!players[tokenId].isActive) return false;
        if (players[tokenId].contractsRemaining == 0) return false;
        return true;
    }

    /*//////////////////////////////////////////////////////////////
                       REQUIRED OVERRIDES
    //////////////////////////////////////////////////////////////*/
    
    // The following functions are overrides required by Solidity.
    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Enumerable, ERC721Pausable)
        returns (address)
    {
        address from = _ownerOf(tokenId);
        
        // Handle ownership tracking for transfers
        if (from != address(0) && to != address(0) && from != to) {
            _removePlayerFromOwner(from, tokenId);
        }
        
        // Call parent _update
        address previousOwner = super._update(to, tokenId, auth);
        
        // Handle ownership tracking for new owner
        if (to != address(0) && (from == address(0) || from != to)) {
            _addPlayerToOwner(to, tokenId);
        }
        
        return previousOwner;
    }
    
    function _increaseBalance(address account, uint128 value)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._increaseBalance(account, value);
    }
    
    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }
    
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable, ERC721URIStorage)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
    
    function pause() public onlyOwner {
        _pause();
    }
    
    function unpause() public onlyOwner {
        _unpause();
    }
}