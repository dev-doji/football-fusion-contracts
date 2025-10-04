// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {PlayerNFT} from "../src/PlayerNFT.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract PlayerNFTTest is Test {
    PlayerNFT public playerNFT;
    ERC20Mock public usdc;
    
    address public owner = makeAddr("owner");
    address public tournamentContract = makeAddr("tournament");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public user3 = makeAddr("user3");
    
    uint256 constant INITIAL_USDC_SUPPLY = 1_000_000_000_000; // 1M USDC (6 decimals)
    uint256 constant MARKETPLACE_FEE_BPS = 250; // 2.5%
    uint256 constant BPS_DENOMINATOR = 10_000;
    
    // Test player data
    string constant PLAYER_NAME = "Lionel Messi";
    string constant PLAYER_TEAM = "Inter Miami";
    string constant PLAYER_NATIONALITY = "Argentina";
    string constant PLAYER_IMAGE_URL = "https://example.com/messi.jpg";
    uint256 constant PLAYER_AGE = 36;
    uint256 constant PLAYER_BASE_PRICE = 1000_000000; // $1000 USDC
    
    function setUp() public {
        // Deploy mock USDC
        usdc = new ERC20Mock();
        
        // Deploy PlayerNFT contract
        vm.startPrank(owner);
        playerNFT = new PlayerNFT(address(usdc), owner);
        playerNFT.setTournamentContract(tournamentContract);
        vm.stopPrank();
        
        // Mint USDC to test users
        usdc.mint(user1, INITIAL_USDC_SUPPLY / 4);
        usdc.mint(user2, INITIAL_USDC_SUPPLY / 4);
        usdc.mint(user3, INITIAL_USDC_SUPPLY / 4);
        usdc.mint(address(this), INITIAL_USDC_SUPPLY / 4);
        
        // Give users USDC approval to PlayerNFT contract
        vm.prank(user1);
        usdc.approve(address(playerNFT), INITIAL_USDC_SUPPLY);
        vm.prank(user2);
        usdc.approve(address(playerNFT), INITIAL_USDC_SUPPLY);
        vm.prank(user3);
        usdc.approve(address(playerNFT), INITIAL_USDC_SUPPLY);
        usdc.approve(address(playerNFT), INITIAL_USDC_SUPPLY);
    }
    
    /*//////////////////////////////////////////////////////////////
                            INITIALIZATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testInitialState() public {
        assertEq(address(playerNFT.USDC()), address(usdc));
        assertEq(playerNFT.owner(), owner);
        assertEq(playerNFT.tournamentContract(), tournamentContract);
        assertEq(playerNFT.currentSeason(), 1);
        assertEq(playerNFT.packageCounter(), 3); // 3 default packages
        assertEq(playerNFT.totalSupply(), 0);
        assertFalse(playerNFT.paused());
    }
    
    function testDefaultContractPackages() public {
        // Package 1: 5 contracts for $5
        PlayerNFT.ContractPackage memory package1 = playerNFT.getContractPackage(1);
        assertEq(package1.contracts, 5);
        assertEq(package1.priceInUSDC, 5_000000);
        assertEq(package1.bonusPercentage, 0);
        assertTrue(package1.isActive);
        
        // Package 2: 10 contracts for $9 (10% bonus)
        PlayerNFT.ContractPackage memory package2 = playerNFT.getContractPackage(2);
        assertEq(package2.contracts, 10);
        assertEq(package2.priceInUSDC, 9_000000);
        assertEq(package2.bonusPercentage, 10);
        assertTrue(package2.isActive);
        
        // Package 3: 20 contracts for $17 (15% bonus)
        PlayerNFT.ContractPackage memory package3 = playerNFT.getContractPackage(3);
        assertEq(package3.contracts, 20);
        assertEq(package3.priceInUSDC, 17_000000);
        assertEq(package3.bonusPercentage, 15);
        assertTrue(package3.isActive);
    }
    
    function testConstructorFailsWithZeroAddress() public {
        vm.expectRevert(PlayerNFT.InvalidParameters.selector);
        new PlayerNFT(address(0), owner);
    }
    
    /*//////////////////////////////////////////////////////////////
                            MINTING TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testMintPlayer() public {
        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit PlayerNFT.PlayerMinted(
            1,
            user1,
            PLAYER_NAME,
            PlayerNFT.Position.FWD,
            PlayerNFT.Rarity.Legendary
        );
        
        uint256 tokenId = playerNFT.mintPlayer(
            user1,
            PLAYER_NAME,
            PLAYER_TEAM,
            PlayerNFT.Position.FWD,
            PlayerNFT.Rarity.Legendary,
            PLAYER_BASE_PRICE,
            PLAYER_NATIONALITY,
            PLAYER_AGE,
            PLAYER_IMAGE_URL
        );
        
        assertEq(tokenId, 1);
        assertEq(playerNFT.ownerOf(tokenId), user1);
        assertEq(playerNFT.totalSupply(), 1);
        
        // Check player data
        PlayerNFT.PlayerData memory player = playerNFT.getPlayer(tokenId);
        assertEq(player.name, PLAYER_NAME);
        assertEq(player.team, PLAYER_TEAM);
        assertEq(uint256(player.position), uint256(PlayerNFT.Position.FWD));
        assertEq(uint256(player.rarity), uint256(PlayerNFT.Rarity.Legendary));
        assertEq(player.basePrice, PLAYER_BASE_PRICE);
        assertEq(player.currentPrice, PLAYER_BASE_PRICE);
        assertEq(player.contractsRemaining, 38); // Legendary = 38 contracts
        assertEq(player.maxContracts, 38);
        assertEq(player.nationality, PLAYER_NATIONALITY);
        assertEq(player.age, PLAYER_AGE);
        assertTrue(player.isActive);
        assertEq(uint256(player.status), uint256(PlayerNFT.PlayerStatus.Active));
    }
    
    function testMintPlayerFailsForNonOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        playerNFT.mintPlayer(
            user1,
            PLAYER_NAME,
            PLAYER_TEAM,
            PlayerNFT.Position.FWD,
            PlayerNFT.Rarity.Common,
            PLAYER_BASE_PRICE,
            PLAYER_NATIONALITY,
            PLAYER_AGE,
            PLAYER_IMAGE_URL
        );
    }
    
    function testBatchMintPlayers() public {
        address[] memory recipients = new address[](3);
        string[] memory names = new string[](3);
        string[] memory teams = new string[](3);
        PlayerNFT.Position[] memory positions = new PlayerNFT.Position[](3);
        PlayerNFT.Rarity[] memory rarities = new PlayerNFT.Rarity[](3);
        uint256[] memory basePrices = new uint256[](3);
        string[] memory nationalities = new string[](3);
        uint256[] memory ages = new uint256[](3);
        string[] memory imageUrls = new string[](3);
        
        recipients[0] = user1;
        recipients[1] = user2;
        recipients[2] = user3;
        
        names[0] = "Cristiano Ronaldo";
        names[1] = "Kylian Mbappe";
        names[2] = "Erling Haaland";
        
        teams[0] = "Al Nassr";
        teams[1] = "PSG";
        teams[2] = "Manchester City";
        
        positions[0] = PlayerNFT.Position.FWD;
        positions[1] = PlayerNFT.Position.FWD;
        positions[2] = PlayerNFT.Position.FWD;
        
        rarities[0] = PlayerNFT.Rarity.Legendary;
        rarities[1] = PlayerNFT.Rarity.Epic;
        rarities[2] = PlayerNFT.Rarity.Rare;
        
        basePrices[0] = 1200_000000;
        basePrices[1] = 800_000000;
        basePrices[2] = 600_000000;
        
        nationalities[0] = "Portugal";
        nationalities[1] = "France";
        nationalities[2] = "Norway";
        
        ages[0] = 39;
        ages[1] = 25;
        ages[2] = 23;
        
        imageUrls[0] = "https://example.com/ronaldo.jpg";
        imageUrls[1] = "https://example.com/mbappe.jpg";
        imageUrls[2] = "https://example.com/haaland.jpg";
        
        vm.prank(owner);
        playerNFT.batchMintPlayers(
            recipients,
            names,
            teams,
            positions,
            rarities,
            basePrices,
            nationalities,
            ages,
            imageUrls
        );
        
        assertEq(playerNFT.totalSupply(), 3);
        assertEq(playerNFT.ownerOf(1), user1);
        assertEq(playerNFT.ownerOf(2), user2);
        assertEq(playerNFT.ownerOf(3), user3);
        
        // Check contract allocations by rarity
        assertEq(playerNFT.getPlayer(1).contractsRemaining, 38); // Legendary
        assertEq(playerNFT.getPlayer(2).contractsRemaining, 25); // Epic
        assertEq(playerNFT.getPlayer(3).contractsRemaining, 20); // Rare
    }
    
    function testBatchMintFailsWithMismatchedArrays() public {
        address[] memory recipients = new address[](2);
        string[] memory names = new string[](3); // Mismatched length
        string[] memory teams = new string[](2);
        PlayerNFT.Position[] memory positions = new PlayerNFT.Position[](2);
        PlayerNFT.Rarity[] memory rarities = new PlayerNFT.Rarity[](2);
        uint256[] memory basePrices = new uint256[](2);
        string[] memory nationalities = new string[](2);
        uint256[] memory ages = new uint256[](2);
        string[] memory imageUrls = new string[](2);
        
        vm.prank(owner);
        vm.expectRevert(PlayerNFT.InvalidParameters.selector);
        playerNFT.batchMintPlayers(
            recipients,
            names,
            teams,
            positions,
            rarities,
            basePrices,
            nationalities,
            ages,
            imageUrls
        );
    }
    
    /*//////////////////////////////////////////////////////////////
                        CONTRACT MANAGEMENT TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testUsePlayerContract() public {
        // Mint player first
        uint256 tokenId = _mintPlayerToUser(user1, PlayerNFT.Rarity.Common);
        
        uint256 contractsBefore = playerNFT.getPlayer(tokenId).contractsRemaining;
        
        vm.prank(tournamentContract);
        playerNFT.usePlayerContract(tokenId, user1);
        
        uint256 contractsAfter = playerNFT.getPlayer(tokenId).contractsRemaining;
        assertEq(contractsAfter, contractsBefore - 1);
    }
    
    function testUsePlayerContractFailsForNonOwner() public {
        uint256 tokenId = _mintPlayerToUser(user1, PlayerNFT.Rarity.Common);
        
        vm.prank(tournamentContract);
        vm.expectRevert(PlayerNFT.NotOwnerOrApproved.selector);
        playerNFT.usePlayerContract(tokenId, user2); // user2 doesn't own the player
    }
    
    function testUsePlayerContractFailsForNonTournament() public {
        uint256 tokenId = _mintPlayerToUser(user1, PlayerNFT.Rarity.Common);
        
        vm.prank(user1);
        vm.expectRevert(PlayerNFT.NotOwnerOrApproved.selector);
        playerNFT.usePlayerContract(tokenId, user1);
    }
    
    function testUsePlayerContractFailsWhenNoContractsRemaining() public {
        uint256 tokenId = _mintPlayerToUser(user1, PlayerNFT.Rarity.Common);
        
        // Use all contracts
        vm.startPrank(tournamentContract);
        for (uint256 i = 0; i < 15; i++) {
            playerNFT.usePlayerContract(tokenId, user1);
        }
        
        // Should fail on 16th use
        vm.expectRevert(PlayerNFT.InsufficientContracts.selector);
        playerNFT.usePlayerContract(tokenId, user1);
        vm.stopPrank();
    }
    
    function testRenewContracts() public {
        uint256 tokenId = _mintPlayerToUser(user1, PlayerNFT.Rarity.Common);
        uint256 packageId = 1; // 5 contracts for $5
        
        uint256 contractsBefore = playerNFT.getPlayer(tokenId).contractsRemaining;
        uint256 balanceBefore = usdc.balanceOf(user1);
        
        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit PlayerNFT.ContractsRenewed(tokenId, user1, 5, 5_000000);
        playerNFT.renewContracts(tokenId, packageId);
        
        uint256 contractsAfter = playerNFT.getPlayer(tokenId).contractsRemaining;
        uint256 balanceAfter = usdc.balanceOf(user1);
        
        assertEq(contractsAfter, contractsBefore + 5);
        assertEq(balanceAfter, balanceBefore - 5_000000);
        assertEq(playerNFT.userContractSpending(user1), 5_000000);
        assertEq(playerNFT.lastRenewalTime(tokenId), block.timestamp);
    }
    
    function testRenewContractsWithBonus() public {
        uint256 tokenId = _mintPlayerToUser(user1, PlayerNFT.Rarity.Common);
        uint256 packageId = 2; // 10 contracts + 10% bonus = 11 contracts for $9
        
        uint256 contractsBefore = playerNFT.getPlayer(tokenId).contractsRemaining;
        
        vm.prank(user1);
        playerNFT.renewContracts(tokenId, packageId);
        
        uint256 contractsAfter = playerNFT.getPlayer(tokenId).contractsRemaining;
        assertEq(contractsAfter, contractsBefore + 11); // 10 + 1 bonus
    }
    
    function testRenewContractsFailsForNonOwner() public {
        uint256 tokenId = _mintPlayerToUser(user1, PlayerNFT.Rarity.Common);
        
        vm.prank(user2);
        vm.expectRevert(PlayerNFT.NotOwnerOrApproved.selector);
        playerNFT.renewContracts(tokenId, 1);
    }
    
    function testRenewContractsFailsWithInvalidPackage() public {
        uint256 tokenId = _mintPlayerToUser(user1, PlayerNFT.Rarity.Common);
        
        vm.prank(user1);
        vm.expectRevert(PlayerNFT.InvalidPackage.selector);
        playerNFT.renewContracts(tokenId, 999); // Invalid package
    }
    
    function testRenewContractsFailsWithCooldown() public {
        uint256 tokenId = _mintPlayerToUser(user1, PlayerNFT.Rarity.Common);
        
        // First renewal
        vm.prank(user1);
        playerNFT.renewContracts(tokenId, 1);
        
        // Immediate second renewal should fail
        vm.prank(user1);
        vm.expectRevert(PlayerNFT.ContractCooldown.selector);
        playerNFT.renewContracts(tokenId, 1);
        
        // After cooldown period should work
        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(user1);
        playerNFT.renewContracts(tokenId, 1);
    }
    
    /*//////////////////////////////////////////////////////////////
                        MARKETPLACE TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testListPlayer() public {
        uint256 tokenId = _mintPlayerToUser(user1, PlayerNFT.Rarity.Common);
        uint256 price = 500_000000; // $500
        
        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit PlayerNFT.PlayerListed(tokenId, user1, price, 15);
        playerNFT.listPlayer(tokenId, price);
        
        PlayerNFT.MarketListing memory listing = playerNFT.getMarketListing(tokenId);
        assertEq(listing.seller, user1);
        assertEq(listing.price, price);
        assertEq(listing.contractsIncluded, 15);
        assertTrue(listing.isActive);
        assertEq(listing.listedAt, block.timestamp);
    }
    
    function testListPlayerFailsForNonOwner() public {
        uint256 tokenId = _mintPlayerToUser(user1, PlayerNFT.Rarity.Common);
        
        vm.prank(user2);
        vm.expectRevert(PlayerNFT.NotOwnerOrApproved.selector);
        playerNFT.listPlayer(tokenId, 500_000000);
    }
    
    function testListPlayerFailsWithZeroPrice() public {
        uint256 tokenId = _mintPlayerToUser(user1, PlayerNFT.Rarity.Common);
        
        vm.prank(user1);
        vm.expectRevert(PlayerNFT.InvalidPrice.selector);
        playerNFT.listPlayer(tokenId, 0);
    }
    
    function testBuyPlayer() public {
        uint256 tokenId = _mintPlayerToUser(user1, PlayerNFT.Rarity.Common);
        uint256 price = 500_000000; // $500
        
        // List player
        vm.prank(user1);
        playerNFT.listPlayer(tokenId, price);
        
        uint256 marketplaceFee = (price * MARKETPLACE_FEE_BPS) / BPS_DENOMINATOR;
        uint256 sellerAmount = price - marketplaceFee;
        
        uint256 user1BalanceBefore = usdc.balanceOf(user1);
        uint256 user2BalanceBefore = usdc.balanceOf(user2);
        uint256 ownerBalanceBefore = usdc.balanceOf(owner);
        
        // Buy player
        vm.prank(user2);
        vm.expectEmit(true, true, true, true);
        emit PlayerNFT.PlayerSold(tokenId, user1, user2, price);
        playerNFT.buyPlayer(tokenId);
        
        // Check ownership transfer
        assertEq(playerNFT.ownerOf(tokenId), user2);
        
        // Check USDC transfers
        assertEq(usdc.balanceOf(user1), user1BalanceBefore + sellerAmount);
        assertEq(usdc.balanceOf(user2), user2BalanceBefore - price);
        assertEq(usdc.balanceOf(owner), ownerBalanceBefore + marketplaceFee);
        
        // Check listing is inactive
        assertFalse(playerNFT.getMarketListing(tokenId).isActive);
        
        // Check price update
        assertEq(playerNFT.getPlayer(tokenId).currentPrice, price);
    }
    
    function testBuyPlayerFailsForInactiveListing() public {
        uint256 tokenId = _mintPlayerToUser(user1, PlayerNFT.Rarity.Common);
        
        vm.prank(user2);
        vm.expectRevert(PlayerNFT.ListingNotFound.selector);
        playerNFT.buyPlayer(tokenId);
    }
    
    function testBuyPlayerFailsForSeller() public {
        uint256 tokenId = _mintPlayerToUser(user1, PlayerNFT.Rarity.Common);
        
        vm.prank(user1);
        playerNFT.listPlayer(tokenId, 500_000000);
        
        vm.prank(user1);
        vm.expectRevert(PlayerNFT.NotSeller.selector);
        playerNFT.buyPlayer(tokenId);
    }
    
    function testCancelListing() public {
        uint256 tokenId = _mintPlayerToUser(user1, PlayerNFT.Rarity.Common);
        
        vm.prank(user1);
        playerNFT.listPlayer(tokenId, 500_000000);
        
        assertTrue(playerNFT.getMarketListing(tokenId).isActive);
        
        vm.prank(user1);
        playerNFT.cancelListing(tokenId);
        
        assertFalse(playerNFT.getMarketListing(tokenId).isActive);
    }
    
    function testCancelListingFailsForNonSeller() public {
        uint256 tokenId = _mintPlayerToUser(user1, PlayerNFT.Rarity.Common);
        
        vm.prank(user1);
        playerNFT.listPlayer(tokenId, 500_000000);
        
        vm.prank(user2);
        vm.expectRevert(PlayerNFT.NotSeller.selector);
        playerNFT.cancelListing(tokenId);
    }
    
    /*//////////////////////////////////////////////////////////////
                            ADMIN FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testUpdatePlayerStats() public {
        uint256 tokenId = _mintPlayerToUser(user1, PlayerNFT.Rarity.Common);
        uint256 gameweekPoints = 15;
        
        PlayerNFT.PlayerStats memory stats = PlayerNFT.PlayerStats({
            gamesPlayed: 10,
            goals: 8,
            assists: 5,
            cleanSheets: 0,
            yellowCards: 2,
            redCards: 0,
            saves: 0,
            passAccuracy: 85,
            shotsOnTarget: 12,
            tacklesWon: 3
        });
        
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit PlayerNFT.PlayerStatsUpdated(tokenId, gameweekPoints, gameweekPoints);
        playerNFT.updatePlayerStats(tokenId, gameweekPoints, stats);
        
        PlayerNFT.PlayerData memory player = playerNFT.getPlayer(tokenId);
        assertEq(player.gameweekPoints, gameweekPoints);
        assertEq(player.totalSeasonPoints, gameweekPoints);
        assertEq(player.averagePoints, gameweekPoints / stats.gamesPlayed);
        
        PlayerNFT.PlayerStats memory retrievedStats = playerNFT.getPlayerStats(tokenId);
        assertEq(retrievedStats.gamesPlayed, 10);
        assertEq(retrievedStats.goals, 8);
        assertEq(retrievedStats.assists, 5);
    }
    
    function testAddContractPackage() public {
        uint256 contracts = 50;
        uint256 priceInUSDC = 45_000000;
        uint256 bonusPercentage = 20;
        
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit PlayerNFT.ContractPackageAdded(4, contracts, priceInUSDC);
        playerNFT.addContractPackage(contracts, priceInUSDC, bonusPercentage);
        
        assertEq(playerNFT.packageCounter(), 4);
        
        PlayerNFT.ContractPackage memory package = playerNFT.getContractPackage(4);
        assertEq(package.contracts, contracts);
        assertEq(package.priceInUSDC, priceInUSDC);
        assertEq(package.bonusPercentage, bonusPercentage);
        assertTrue(package.isActive);
    }
    
    function testStartNewSeason() public {
        // Mint some players and use contracts
        uint256 tokenId1 = _mintPlayerToUser(user1, PlayerNFT.Rarity.Common);
        uint256 tokenId2 = _mintPlayerToUser(user2, PlayerNFT.Rarity.Rare);
        
        // Use some contracts
        vm.startPrank(tournamentContract);
        playerNFT.usePlayerContract(tokenId1, user1);
        playerNFT.usePlayerContract(tokenId2, user2);
        vm.stopPrank();
        
        // Update some stats
        PlayerNFT.PlayerStats memory stats = PlayerNFT.PlayerStats({
            gamesPlayed: 5,
            goals: 3,
            assists: 2,
            cleanSheets: 0,
            yellowCards: 1,
            redCards: 0,
            saves: 0,
            passAccuracy: 80,
            shotsOnTarget: 6,
            tacklesWon: 2
        });
        
        vm.prank(owner);
        playerNFT.updatePlayerStats(tokenId1, 10, stats);
        
        uint256 seasonBefore = playerNFT.currentSeason();
        
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit PlayerNFT.SeasonStarted(2, block.timestamp);
        playerNFT.startNewSeason();
        
        assertEq(playerNFT.currentSeason(), seasonBefore + 1);
        assertEq(playerNFT.seasonStartTime(), block.timestamp);
        
        // Check that stats were reset
        PlayerNFT.PlayerData memory player1 = playerNFT.getPlayer(tokenId1);
        PlayerNFT.PlayerData memory player2 = playerNFT.getPlayer(tokenId2);
        
        assertEq(player1.totalSeasonPoints, 0);
        assertEq(player1.gameweekPoints, 0);
        assertEq(player1.averagePoints, 0);
        assertEq(player1.contractsRemaining, 15); // Reset to max for Common
        
        assertEq(player2.contractsRemaining, 20); // Reset to max for Rare
    }
    
    function testSetTournamentContract() public {
        address newTournament = makeAddr("newTournament");
        
        vm.prank(owner);
        playerNFT.setTournamentContract(newTournament);
        
        assertEq(playerNFT.tournamentContract(), newTournament);
    }
    
    function testEmergencyWithdraw() public {
        uint256 amount = 100_000000;
        usdc.transfer(address(playerNFT), amount);
        
        uint256 ownerBalanceBefore = usdc.balanceOf(owner);
        
        vm.prank(owner);
        playerNFT.emergencyWithdraw();
        
        uint256 ownerBalanceAfter = usdc.balanceOf(owner);
        assertEq(ownerBalanceAfter, ownerBalanceBefore + amount);
        assertEq(usdc.balanceOf(address(playerNFT)), 0);
    }
    
    /*//////////////////////////////////////////////////////////////
                            PAUSE FUNCTIONALITY TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testPauseUnpause() public {
        assertFalse(playerNFT.paused());
        
        vm.prank(owner);
        playerNFT.pause();
        
        assertTrue(playerNFT.paused());
        
        vm.prank(owner);
        playerNFT.unpause();
        
        assertFalse(playerNFT.paused());
    }
    
    function testCannotRenewContractsWhenPaused() public {
        uint256 tokenId = _mintPlayerToUser(user1, PlayerNFT.Rarity.Common);
        
        vm.prank(owner);
        playerNFT.pause();
        
        vm.prank(user1);
        vm.expectRevert();
        playerNFT.renewContracts(tokenId, 1);
    }
    
    function testCannotListPlayerWhenPaused() public {
        uint256 tokenId = _mintPlayerToUser(user1, PlayerNFT.Rarity.Common);
        
        vm.prank(owner);
        playerNFT.pause();
        
        vm.prank(user1);
        vm.expectRevert();
        playerNFT.listPlayer(tokenId, 500_000000);
    }
    
    /*//////////////////////////////////////////////////////////////
                           ACCESS CONTROL TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testOnlyOwnerCanMint() public {
        vm.prank(user1);
        vm.expectRevert();
        playerNFT.mintPlayer(
            user1,
            PLAYER_NAME,
            PLAYER_TEAM,
            PlayerNFT.Position.FWD,
            PlayerNFT.Rarity.Common,
            PLAYER_BASE_PRICE,
            PLAYER_NATIONALITY,
            PLAYER_AGE,
            PLAYER_IMAGE_URL
        );
    }
    
    function testOnlyOwnerCanUpdateStats() public {
        uint256 tokenId = _mintPlayerToUser(user1, PlayerNFT.Rarity.Common);
        
        PlayerNFT.PlayerStats memory stats = PlayerNFT.PlayerStats({
            gamesPlayed: 1,
            goals: 1,
            assists: 0,
            cleanSheets: 0,
            yellowCards: 0,
            redCards: 0,
            saves: 0,
            passAccuracy: 90,
            shotsOnTarget: 2,
            tacklesWon: 1
        });
        
        vm.prank(user1);
        vm.expectRevert();
        playerNFT.updatePlayerStats(tokenId, 10, stats);
    }
    
    function testOnlyOwnerCanAddContractPackage() public {
        vm.prank(user1);
        vm.expectRevert();
        playerNFT.addContractPackage(10, 10_000000, 5);
    }
    
    function testOnlyOwnerCanStartNewSeason() public {
        vm.prank(user1);
        vm.expectRevert();
        playerNFT.startNewSeason();
    }
    
    function testOnlyOwnerCanPause() public {
        vm.prank(user1);
        vm.expectRevert();
        playerNFT.pause();
    }
    
    /*//////////////////////////////////////////////////////////////
                           VIEW FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testGetUserOwnedPlayers() public {
        uint256 tokenId1 = _mintPlayerToUser(user1, PlayerNFT.Rarity.Common);
        uint256 tokenId2 = _mintPlayerToUser(user1, PlayerNFT.Rarity.Rare);
        uint256 tokenId3 = _mintPlayerToUser(user2, PlayerNFT.Rarity.Epic);
        
        uint256[] memory user1Players = playerNFT.getUserOwnedPlayers(user1);
        uint256[] memory user2Players = playerNFT.getUserOwnedPlayers(user2);
        uint256[] memory user3Players = playerNFT.getUserOwnedPlayers(user3);
        
        assertEq(user1Players.length, 2);
        assertEq(user1Players[0], tokenId1);
        assertEq(user1Players[1], tokenId2);
        
        assertEq(user2Players.length, 1);
        assertEq(user2Players[0], tokenId3);
        
        assertEq(user3Players.length, 0);
    }
    
    function testCanUsePlayer() public {
        uint256 tokenId = _mintPlayerToUser(user1, PlayerNFT.Rarity.Common);
        
        // Should be usable initially
        assertTrue(playerNFT.canUsePlayer(tokenId, user1));
        
        // Should not be usable by different user
        assertFalse(playerNFT.canUsePlayer(tokenId, user2));
        
        // Use all contracts
        vm.startPrank(tournamentContract);
        for (uint256 i = 0; i < 15; i++) {
            playerNFT.usePlayerContract(tokenId, user1);
        }
        vm.stopPrank();
        
        // Should not be usable when no contracts remaining
        assertFalse(playerNFT.canUsePlayer(tokenId, user1));
        
        // Should not be usable for non-existent token
        assertFalse(playerNFT.canUsePlayer(999, user1));
    }
    
    /*//////////////////////////////////////////////////////////////
                           COMPLEX SCENARIO TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testCompletePlayerLifecycle() public {
        // Set timestamp to 0 to avoid initial cooldown issues
        vm.warp(0);
        
        // 1. Mint player
        uint256 tokenId = _mintPlayerToUser(user1, PlayerNFT.Rarity.Epic);
        
        // 2. Use some contracts in tournaments
        vm.startPrank(tournamentContract);
        playerNFT.usePlayerContract(tokenId, user1);
        playerNFT.usePlayerContract(tokenId, user1);
        vm.stopPrank();
        
        assertEq(playerNFT.getPlayer(tokenId).contractsRemaining, 23); // 25 - 2
        
        // 3. Update player stats
        PlayerNFT.PlayerStats memory stats = PlayerNFT.PlayerStats({
            gamesPlayed: 2,
            goals: 2,
            assists: 1,
            cleanSheets: 0,
            yellowCards: 0,
            redCards: 0,
            saves: 0,
            passAccuracy: 88,
            shotsOnTarget: 4,
            tacklesWon: 2
        });
        
        vm.prank(owner);
        playerNFT.updatePlayerStats(tokenId, 15, stats);
        
        assertEq(playerNFT.getPlayer(tokenId).totalSeasonPoints, 15);
        
        // 4. Renew contracts
        vm.prank(user1);
        playerNFT.renewContracts(tokenId, 1); // 5 contracts
        
        assertEq(playerNFT.getPlayer(tokenId).contractsRemaining, 28); // 23 + 5
        
        // 5. List player for sale
        uint256 listPrice = 2000_000000;
        vm.prank(user1);
        playerNFT.listPlayer(tokenId, listPrice);
        
        assertTrue(playerNFT.getMarketListing(tokenId).isActive);
        
        // 6. Buy player
        vm.prank(user2);
        playerNFT.buyPlayer(tokenId);
        
        assertEq(playerNFT.ownerOf(tokenId), user2);
        assertFalse(playerNFT.getMarketListing(tokenId).isActive);
        
        // 7. New owner can use player
        assertTrue(playerNFT.canUsePlayer(tokenId, user2));
        assertFalse(playerNFT.canUsePlayer(tokenId, user1));
    }
    
    function testMultiplePlayersAndMarketplace() public {
        // Mint different rarity players
        uint256 commonId = _mintPlayerToUser(user1, PlayerNFT.Rarity.Common);
        uint256 rareId = _mintPlayerToUser(user1, PlayerNFT.Rarity.Rare);
        uint256 epicId = _mintPlayerToUser(user2, PlayerNFT.Rarity.Epic);
        uint256 legendaryId = _mintPlayerToUser(user3, PlayerNFT.Rarity.Legendary);
        
        // List all players
        vm.prank(user1);
        playerNFT.listPlayer(commonId, 200_000000);
        
        vm.prank(user1);
        playerNFT.listPlayer(rareId, 400_000000);
        
        vm.prank(user2);
        playerNFT.listPlayer(epicId, 800_000000);
        
        vm.prank(user3);
        playerNFT.listPlayer(legendaryId, 1500_000000);
        
        // User2 buys common and rare players
        vm.startPrank(user2);
        playerNFT.buyPlayer(commonId);
        playerNFT.buyPlayer(rareId);
        vm.stopPrank();
        
        // Check ownership
        assertEq(playerNFT.ownerOf(commonId), user2);
        assertEq(playerNFT.ownerOf(rareId), user2);
        assertEq(playerNFT.ownerOf(epicId), user2); // Still owns
        assertEq(playerNFT.ownerOf(legendaryId), user3); // Still owns
        
        // Check user2 now has 3 players
        uint256[] memory user2Players = playerNFT.getUserOwnedPlayers(user2);
        assertEq(user2Players.length, 3);
    }
    
    function testSeasonResetFunctionality() public {
        // Mint players and simulate a season
        uint256 tokenId1 = _mintPlayerToUser(user1, PlayerNFT.Rarity.Common);
        uint256 tokenId2 = _mintPlayerToUser(user2, PlayerNFT.Rarity.Legendary);
        
        // Use contracts and update stats throughout season
        vm.startPrank(tournamentContract);
        for (uint256 i = 0; i < 10; i++) {
            playerNFT.usePlayerContract(tokenId1, user1);
        }
        for (uint256 i = 0; i < 20; i++) {
            playerNFT.usePlayerContract(tokenId2, user2);
        }
        vm.stopPrank();
        
        // Update stats multiple times
        PlayerNFT.PlayerStats memory stats = PlayerNFT.PlayerStats({
            gamesPlayed: 10,
            goals: 8,
            assists: 5,
            cleanSheets: 0,
            yellowCards: 2,
            redCards: 0,
            saves: 0,
            passAccuracy: 85,
            shotsOnTarget: 15,
            tacklesWon: 8
        });
        
        vm.startPrank(owner);
        playerNFT.updatePlayerStats(tokenId1, 12, stats);
        playerNFT.updatePlayerStats(tokenId1, 8, stats);
        playerNFT.updatePlayerStats(tokenId2, 15, stats);
        playerNFT.updatePlayerStats(tokenId2, 18, stats);
        vm.stopPrank();
        
        // Check pre-season state
        assertEq(playerNFT.getPlayer(tokenId1).contractsRemaining, 5); // 15 - 10
        assertEq(playerNFT.getPlayer(tokenId1).totalSeasonPoints, 20); // 12 + 8
        assertEq(playerNFT.getPlayer(tokenId2).contractsRemaining, 18); // 38 - 20
        assertEq(playerNFT.getPlayer(tokenId2).totalSeasonPoints, 33); // 15 + 18
        
        // Start new season
        vm.prank(owner);
        playerNFT.startNewSeason();
        
        // Check post-season reset
        assertEq(playerNFT.getPlayer(tokenId1).contractsRemaining, 15); // Reset to max
        assertEq(playerNFT.getPlayer(tokenId1).totalSeasonPoints, 0); // Reset
        assertEq(playerNFT.getPlayer(tokenId1).gameweekPoints, 0); // Reset
        assertEq(playerNFT.getPlayer(tokenId1).averagePoints, 0); // Reset
        
        assertEq(playerNFT.getPlayer(tokenId2).contractsRemaining, 38); // Reset to max
        assertEq(playerNFT.getPlayer(tokenId2).totalSeasonPoints, 0); // Reset
        
        assertEq(playerNFT.currentSeason(), 2);
    }
    
    /*//////////////////////////////////////////////////////////////
                           EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testPlayerNotExists() public {
        vm.prank(user1);
        vm.expectRevert(PlayerNFT.PlayerNotExists.selector);
        playerNFT.listPlayer(999, 100_000000);
        
        vm.prank(tournamentContract);
        vm.expectRevert(PlayerNFT.PlayerNotExists.selector);
        playerNFT.usePlayerContract(999, user1);
    }
    
    function testRarityContractAllocation() public {
        uint256 commonId = _mintPlayerToUser(user1, PlayerNFT.Rarity.Common);
        uint256 rareId = _mintPlayerToUser(user1, PlayerNFT.Rarity.Rare);
        uint256 epicId = _mintPlayerToUser(user1, PlayerNFT.Rarity.Epic);
        uint256 legendaryId = _mintPlayerToUser(user1, PlayerNFT.Rarity.Legendary);
        
        assertEq(playerNFT.getPlayer(commonId).maxContracts, 15);
        assertEq(playerNFT.getPlayer(rareId).maxContracts, 20);
        assertEq(playerNFT.getPlayer(epicId).maxContracts, 25);
        assertEq(playerNFT.getPlayer(legendaryId).maxContracts, 38);
        
        // All should start with max contracts
        assertEq(playerNFT.getPlayer(commonId).contractsRemaining, 15);
        assertEq(playerNFT.getPlayer(rareId).contractsRemaining, 20);
        assertEq(playerNFT.getPlayer(epicId).contractsRemaining, 25);
        assertEq(playerNFT.getPlayer(legendaryId).contractsRemaining, 38);
    }
    
    /*//////////////////////////////////////////////////////////////
                           HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function _mintPlayerToUser(address user, PlayerNFT.Rarity rarity) internal returns (uint256) {
        vm.prank(owner);
        return playerNFT.mintPlayer(
            user,
            PLAYER_NAME,
            PLAYER_TEAM,
            PlayerNFT.Position.FWD,
            rarity,
            PLAYER_BASE_PRICE,
            PLAYER_NATIONALITY,
            PLAYER_AGE,
            PLAYER_IMAGE_URL
        );
    }
}