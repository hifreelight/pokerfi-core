// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";

interface IPoker {
    function create(address to, uint8 rank, uint8 suit, uint8 level, uint32 hashRate) external returns (uint256 tokenId);
}

interface ICardSlot {
    function opening() external view returns (uint256);

    function round() external view returns (uint256);
    function roundSales(uint256 numberOfRound) external view returns (uint256);
}

contract CardStore is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public immutable poker;

    address public receiveToken = 0x55d398326f99059fF775485246999027B3197955;
    address public fundReceiver = 0x883248b3354305de4A40501bAedA2F59D964BA38;

    ICardSlot public cardSlot;

    uint256 public suitCount = 2;
    uint256 public levelCount = 0;

    uint256 public totalRewards = 100000;
    uint256 public totalSales = 0;

    mapping(address => uint256) public rewards;
    mapping(address => address) public referrers;

    mapping(uint256 => uint256) public dailySales;
    mapping(uint256 => uint256) public roundSales;

    uint256 private _randomNonce = 0;

    mapping(uint256 => uint256[5]) private _percentOfRanks;

    event Purchased(address indexed account, address indexed referrer, uint256 tokenId);
    event Drawn(address indexed account, uint256 tokenId);

    constructor(address poker_) {
        poker = poker_;

        _percentOfRanks[1] = [70, 10, 10, 9, 1];
        _percentOfRanks[2] = [70, 5, 5, 15, 5];
        _percentOfRanks[3] = [77, 8, 1, 8, 6];
        _percentOfRanks[4] = [75, 15, 3, 3, 4];
        _percentOfRanks[5] = [1, 30, 30, 19, 20];
        _percentOfRanks[6] = [53, 14, 14, 1, 18];
        _percentOfRanks[7] = [47, 17, 18, 17, 1];
        _percentOfRanks[8] = [28, 1, 13, 23, 35];
        _percentOfRanks[9] = [1, 37, 3, 55, 4];
        _percentOfRanks[10] = [35, 12, 35, 18, 0];
    }

    function setReceiveToken(address value) external onlyOwner {
        receiveToken = value;
    }

    function setFundReceiver(address value) external onlyOwner {
        fundReceiver = value;
    }

    function setCardSlot(address value) external onlyOwner {
        cardSlot = ICardSlot(value);
    }

    function setSuitCount(uint256 value) external onlyOwner {
        require(value <= 4, "Invalid suit count");
        suitCount = value;
    }

    function setLevelCount(uint256 value) external onlyOwner {
        require(value <= 9, "Invalid level count");
        levelCount = value;
    }

    function today() public view returns (uint256) {
        return ((block.timestamp - (cardSlot.opening())) / 1 days) + 1;
    }

    function period() public view returns (uint256) {
        uint256 tempPeriod = today() % 10;
        return tempPeriod > 0 ? tempPeriod : 10;
    }

    function todaySupply() public view returns (uint256) {
        if (cardSlot.round() == 0) {
            return 0;
        }

        uint256 round = cardSlot.round() % 2 == 0 ? 2 : 1;
        uint256 lastRound = cardSlot.round() - round;
        uint256 totalSupply = 5 * cardSlot.roundSales(lastRound);
        if (totalSupply < 1) {
            uint256 temp;
            uint256 usedCard;
            for (uint256 i = cardSlot.round() - 1; i >= 0; i--) {
                if (cardSlot.roundSales(i) > 0) {
                    temp = 5 * cardSlot.roundSales(i);
                    break;
                }
                usedCard += roundSales[i];
            }
            totalSupply = (temp > usedCard) ? temp - usedCard : 0;
        }

        if (totalSupply < 30) {
            return totalSupply;
        }

        uint256 numberOfPeriod = period();
        if (numberOfPeriod % 5 == 0) {
            return totalSupply / 30;
        }

        return (totalSupply * (6 - (numberOfPeriod % 5))) / 30;
    }

    function price() public view returns (uint256) {
        return 30 ether + period() * 10 ether;
    }

    function purchase(address referrer) external nonReentrant {
        require(cardSlot.round() > 0, "Not yet on sale");

        uint256 numberOfDays = today();
        require(dailySales[numberOfDays] < todaySupply(), "Insufficient supply");

        address account = _msgSender();

        referrer = _checkReferrer(account, referrer);
        if (referrer != address(0) && IERC721(poker).balanceOf(referrer) >= 1 && totalRewards > 0) {
            rewards[referrer]++;
            totalRewards--;
        }

        (uint8 rank, uint8 suit, uint8 level, uint32 hashRate) = _createCardValues();
        uint256 tokenId = IPoker(poker).create(account, rank, suit, level, hashRate);

        dailySales[numberOfDays]++;

        roundSales[cardSlot.round()]++;

        totalSales++;

        uint256 payment = price();
        IERC20(receiveToken).safeTransferFrom(account, address(this), payment);
        IERC20(receiveToken).safeTransfer(fundReceiver, payment);

        emit Purchased(account, referrer, tokenId);
    }

    function draw() external nonReentrant {
        address account = _msgSender();
        require(rewards[account] > 0, "Insufficient rewards");

        rewards[account]--;

        uint256 tokenId = 0;

        uint256 random = _random(100);
        if (random <= 20) {
            uint8 rank = (random <= 16) ? 5 : 3;
            uint8 suit = uint8(random % suitCount);

            tokenId = IPoker(poker).create(account, rank, suit, 0, 10 * rank);
        }

        emit Drawn(account, tokenId);
    }

    function _createCardValues() internal returns (uint8 rank, uint8 suit, uint8 level, uint32 hashRate) {
        uint256 random = _random(100);

        suit = uint8(random % suitCount);
        level = uint8(random % levelCount);

        uint256 totalSupply = IERC721Enumerable(poker).totalSupply();
        if (totalSupply > 0 && (totalSupply % 1000) == 0) {
            return (0, 1, level, 200);
        } else if (totalSupply > 0 && (totalSupply % 500) == 0) {
            return (0, 0, level, 100);
        }

        uint8[5] memory ranks = [1, 2, 3, 4, 5];

        uint256 numberOfPeriod = period();
        uint256 percentage = 0;

        for (uint256 i = 0; i < ranks.length; i++) {
            uint256 tempRank = (uint256(ranks[i]) + numberOfPeriod) % 14;
            ranks[i] = (tempRank > 0) ? uint8(tempRank) : 1;

            percentage += _percentOfRanks[numberOfPeriod][i];
            if (random <= percentage) {
                rank = ranks[i];
                break;
            }
        }

        hashRate = (rank == 1) ? 150 : 10 * rank;
    }

    function _checkReferrer(address account, address referrer) internal returns (address) {
        if (referrers[account] == address(0) && referrer != address(0) && referrers[referrer] != account && referrer != account) {
            referrers[account] = referrer;
        }
        return referrers[account];
    }

    function _random(uint256 modulus) internal returns (uint256) {
        _randomNonce++;
        return uint256(keccak256(abi.encodePacked(_randomNonce, block.difficulty, _msgSender()))) % modulus;
    }
}
