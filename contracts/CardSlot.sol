// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface ICardMine {
    function roundStakedTokens(uint256 numberOfDays) external view returns (uint256);
    function roundWithdrawnTokens(uint256 numberOfDays) external view returns (uint256);
}

interface IUniswapV2Pair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

contract CardSlot is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public constant USDT_BNB_PAIR = 0x16b9a82891338f9bA80E2D6970FddA79D1eb0daE;
    address public constant BNB_PK_PAIR = 0xCC98892f067559fd0316C65E984d3E93B682252E;

    address public immutable token;
    address public immutable poker;

    address public fundReceiver;

    ICardMine public cardMine;

    uint256 public opening;
    uint256 public basePrice = 50 ether;
    uint256 public totalSales;

    struct Team {
        address owner;

        string name;

        uint256 deposits;
        uint256 slots;
        uint256 minHashRate;
    }

    Team[] private _teams;

    mapping(address => mapping(uint256 => uint256)) public teamRoundDeposits;
    mapping(address => mapping(uint256 => uint256)) public teamRoundSlots;

    mapping(string => uint256) public teamIndexes;
    mapping(address => uint256) public ownedTeams;

    mapping(uint256 => uint256) public roundDeposits;
    mapping(uint256 => uint256) public roundSales;

    event Registered(address indexed account, string name);
    event Deposited(address indexed account, uint256 amount);
    event Withdrawn(address indexed account, uint256 amount);
    event Purchased(address indexed account, uint256 amount);

    event MinHashRateChanged(address indexed account, uint256 amount);

    constructor(address token_, address poker_) {
        token = token_;
        poker = poker_;

        fundReceiver = _msgSender();

        opening = block.timestamp;
    }

    function setFundReceiver(address value) external onlyOwner {
        fundReceiver = value;
    }

    function setCardMine(address value) external onlyOwner {
        cardMine = ICardMine(value);
    }

    function setBasePrice(uint256 value) public onlyOwner {
        require(value >= 1e18, "Invalid value");
        basePrice = value;
    }

    function price() public view returns (uint256) {
        IUniswapV2Pair uniswapV2Pair = IUniswapV2Pair(USDT_BNB_PAIR);
        (uint256 reserve0, uint256 reserve1, ) = uniswapV2Pair.getReserves();
        uint256 finalPrice = basePrice * reserve1 / reserve0;

        uniswapV2Pair = IUniswapV2Pair(BNB_PK_PAIR);
        (reserve0, reserve1, ) = uniswapV2Pair.getReserves();
        return finalPrice * reserve0 / reserve1;
    }

    function today() public view returns (uint256) {
        return (block.timestamp - opening) / 1 days + 1;
    }

    function period() public view returns (uint256) {
        uint256 numberOfPeriod = today() % 5;
        return numberOfPeriod > 0 ? numberOfPeriod : 5;
    }

    function round() public view returns (uint256) {
        return (block.timestamp - opening) / (5 * 1 days);
    }

    function setTeamName(string memory name) external {
        address account = _msgSender();

        uint256 index = ownedTeams[account];
        require(index > 0, "User can't operation team");

        require(bytes(name).length > 0, "Name cannot be empty");
        require(teamIndexes[name] == 0, "This team already exists");

        Team storage teamData = _teams[index - 1];

        teamIndexes[name] = teamIndexes[teamData.name];

        teamData.name = name;
    }

    function teams(uint256 index) public view returns (address owner, string memory name, uint256 deposits, uint256 slots, uint256 minHashRate) {
        require(index < _teams.length, "Invalid index");

        Team memory team = _teams[index];
        return (team.owner, team.name, team.deposits, team.slots, team.minHashRate);
    }

    function totalTeams() public view returns (uint256) {
        return _teams.length;
    }

    function teamsByIndex(uint256 startIndex, uint256 endIndex) public view returns (Team[] memory) {
        if (endIndex == 0) {
            endIndex = totalTeams();
        }
        require(startIndex < endIndex, "Invalid index");

        Team[] memory result = new Team[](endIndex - startIndex);
        uint256 resultLength = result.length;
        uint256 index = startIndex;
        for (uint256 i = 0; i < resultLength; i++) {
            result[i].owner = _teams[index].owner;
            result[i].name = _teams[index].name;
            result[i].deposits = _teams[index].deposits;
            result[i].slots = _teams[index].slots;
            result[i].minHashRate = _teams[index].minHashRate;
            index++;
        }
        return result;
    }

    function currentSupply() public view returns (uint256) {
        uint256 numberOfRound = round();
        if (numberOfRound == 0) {
            return 15000;
        } else if (numberOfRound % 2 == 1) {
            return 0;
        }

        uint256 lastRoundSales = roundSales[numberOfRound - 2];

        uint256 roundStakedTokens = cardMine.roundStakedTokens(numberOfRound);
        uint256 roundWithdrawnTokens = cardMine.roundWithdrawnTokens(numberOfRound);

        uint256 percentage = (
            (IERC721(poker).balanceOf(address(cardMine)) + roundWithdrawnTokens - roundStakedTokens) * 100
        ) / ((totalSales - roundSales[numberOfRound] - (lastRoundSales / 2)) * 5);

        if (percentage >= 40 && lastRoundSales == 0) {
            lastRoundSales = 2000;
        }

        if (percentage >= 80) {
            return (lastRoundSales * 120) / 100;
        } else if (percentage >= 60) {
            return (lastRoundSales * 80) / 100;
        } else if (percentage >= 40) {
            return (lastRoundSales * 40) / 100;
        }

        return 0;
    }

    function getCurrentSupplyParam() public view returns (uint256, uint256) {
        uint256 numberOfRound = round();
        uint256 lower = cardMine.roundWithdrawnTokens(numberOfRound);
        uint256 lastRoundSales = roundSales[numberOfRound - 2];
        uint256 cardNum = IERC721(poker).balanceOf(address(cardMine)) + lower - cardMine.roundStakedTokens(numberOfRound);
        uint256 cardStoreNum = (totalSales - roundSales[numberOfRound] - (lastRoundSales / 2)) * 5;
        return (cardNum, cardStoreNum);
    }

    function setMinHashRate(uint256 amount) external {
        address account = _msgSender();

        uint256 teamIndex = ownedTeams[account];
        require(teamIndex > 0, "Not own team");

        _teams[teamIndex - 1].minHashRate = amount;

        emit MinHashRateChanged(account, amount);
    }

    function preOrder(uint256 amount, string calldata name) external nonReentrant {
        uint256 numberOfRound = round();
        require(numberOfRound % 2 == 0 && period() <= 3, "Pre-order has not yet started");

        address account = _msgSender();

        Team storage team;

        uint256 teamIndex = ownedTeams[account];
        if (teamIndex == 0) {
            require(bytes(name).length > 0, "Name cannot be empty");
            require(teamIndexes[name] == 0, "This team already exists");

            team = _teams.push();
            team.owner = account;
            team.name = name;

            teamIndexes[name] = _teams.length;
            ownedTeams[account] = _teams.length;

            emit Registered(account, name);
        } else {
            team = _teams[teamIndex - 1];
        }

        team.deposits += amount;

        teamRoundDeposits[team.owner][numberOfRound] += amount;

        roundDeposits[numberOfRound] += amount;

        IERC20(token).safeTransferFrom(account, address(this), amount);

        emit Deposited(account, amount);
    }

    function withdraw() external nonReentrant {
        uint256 remainder = round() % 2;
        require(remainder > 0 || (remainder == 0 && period() > 3), "Withdrawal is not allowed at the current time");

        address account = _msgSender();

        uint256 teamIndex = ownedTeams[account];
        require(teamIndex > 0, "Do not own team");

        Team storage team = _teams[teamIndex - 1];

        uint256 payment = team.deposits;
        if (payment > 0) {
            team.deposits = 0;

            IERC20(token).safeTransfer(account, payment);
        }

        emit Withdrawn(account, payment);
    }

    function purchase(uint256 amount) external nonReentrant {
        uint256 numberOfRound = round();
        uint256 numberOfPeriod = period();

        require(numberOfRound % 2 == 0 && numberOfPeriod > 3, "Not yet on sale");
        require((roundSales[numberOfRound] + amount) <= currentSupply(), "Insufficient supply");

        address account = _msgSender();

        uint256 payment = price() * amount;
        IERC20(token).safeTransferFrom(account, address(this), payment);
        IERC20(token).safeTransfer(fundReceiver, payment);

        uint256 teamIndex = ownedTeams[account];
        require(teamIndex > 0, "Not own team");

        Team storage team = _teams[teamIndex - 1];
        team.slots += amount;

        if (numberOfPeriod == 4) {
            uint256 canBePurchased = (teamRoundDeposits[team.owner][numberOfRound] * currentSupply()) / roundDeposits[numberOfRound];
            require(teamRoundSlots[team.owner][numberOfRound] + amount <= canBePurchased, "Purchase limit exceeded");
        }

        team.minHashRate = 100;

        teamRoundSlots[team.owner][numberOfRound] += amount;

        roundSales[numberOfRound] += amount;

        totalSales += amount;

        emit Purchased(account, amount);
    }
}
