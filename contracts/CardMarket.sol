// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";

interface IPoker {
    function cards(uint256 tokenId) external view returns (uint8 rank, uint8 suit, uint8 level, uint32 hashRate);
}

contract CardMarket is Ownable, ReentrancyGuard, ERC721Holder {
    using SafeERC20 for IERC20;

    address public immutable poker;

    address public receiveToken;
    address public fundReceiver;

    uint256 public feeRate = 0;

    struct Card {
        address user;

        uint256 tokenId;
        uint256 price;

        uint8 rank;
        uint8 suit;
        uint8 level;
    }

    Card[] private _cards;

    mapping(uint256 => uint256) private _allCard;

    event Sold(address indexed account, uint256 tokenId, uint256 price);
    event Bought(address indexed account, address indexed seller, uint256 tokenId, uint256 price, uint256 level, uint256 rank, uint256 suit);
    event Withdrawn(address indexed account, uint256 tokenId, uint256 level, uint256 rank, uint256 suit);

    constructor(address poker_) {
        poker = poker_;

        fundReceiver = _msgSender();
    }

    function setReceiveToken(address value) external onlyOwner {
        receiveToken = value;
    }

    function setFundReceiver(address value) external onlyOwner {
        fundReceiver = value;
    }

    function setFeeRate(uint256 value) external onlyOwner {
        require(value < 100, "Invalid fee rate");
        feeRate = value;
    }

    function totalCards() public view returns (uint256) {
        return _cards.length;
    }

    function cards(uint256 startIndex, uint256 endIndex) public view returns (Card[] memory) {
        if (endIndex == 0) {
            endIndex = totalCards();
        }
        require(startIndex < endIndex, "Invalid index");

        Card[] memory result = new Card[](endIndex - startIndex);
        for (uint256 i = startIndex; i < endIndex; i++) {
            result[i - startIndex] = _cards[i];
        }
        return result;
    }

    function sell(uint256 tokenId, uint256 price) external nonReentrant {
        address account = _msgSender();

        (uint8 rank, uint8 suit, uint8 level, ) = IPoker(poker).cards(tokenId);
        _cards.push(Card(account, tokenId, price, rank, suit, level));

        _allCard[tokenId] = _cards.length - 1;

        IERC721(poker).safeTransferFrom(account, address(this), tokenId);

        emit Sold(account, tokenId, price);
    }

    function buy(uint256 tokenId) external nonReentrant {
        address account = _msgSender();

        uint256 tokenIndex = _allCard[tokenId];
        Card storage card = _cards[tokenIndex];

        uint256 payment = card.price;
        IERC20(receiveToken).transferFrom(account, address(this), payment);

        address seller = card.user;
        if (feeRate > 0 && fundReceiver != address(0)) {
            uint256 fee = payment * feeRate / 100;
            payment -= fee;

            IERC20(receiveToken).safeTransfer(fundReceiver, fee);
        }
        IERC20(receiveToken).safeTransfer(seller, payment);

        IERC721(poker).safeTransferFrom(address(this), account, tokenId);

        emit Bought(account, seller, tokenId, card.price, card.level, card.rank, card.suit);

        if (_cards.length - 1 > 0) {
            Card memory lastCard = _cards[_cards.length - 1];
            card.level = lastCard.level;
            card.price = lastCard.price;
            card.rank = lastCard.rank;
            card.suit = lastCard.suit;
            card.user = lastCard.user;
            card.tokenId = lastCard.tokenId;

            _allCard[lastCard.tokenId] = tokenIndex;
        }

        _cards.pop();

        delete _allCard[tokenId];
    }

    function withdraw(uint256 tokenId) external nonReentrant {
        address account = _msgSender();

        uint256 tokenIndex = _allCard[tokenId];
        Card storage card = _cards[tokenIndex];

        address seller = card.user;
        require(account == seller, "tokenId not owned");

        IERC721(poker).safeTransferFrom(address(this), account, tokenId);

        emit Withdrawn(account, tokenId, card.level, card.rank, card.suit);

        if (_cards.length - 1 > 0) {
            Card memory lastCard = _cards[_cards.length - 1];
            card.level = lastCard.level;
            card.price = lastCard.price;
            card.rank = lastCard.rank;
            card.suit = lastCard.suit;
            card.user = lastCard.user;
            card.tokenId = lastCard.tokenId;

            _allCard[lastCard.tokenId] = tokenIndex;
        }

        _cards.pop();

        delete _allCard[tokenId];
    }
}
