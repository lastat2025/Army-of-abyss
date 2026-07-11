// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * ╔══════════════════════════════════════════════════════════════╗
 * ║       ARMY OF THE ABYSS — RISK DEATH TOLL                  ║
 * ║       Full Game Contract — All 19 Warriors                  ║
 * ║       LnC Tech Innovations © 2026                          ║
 * ║       Chain: Base Mainnet (8453)                           ║
 * ║       5% Abyss Tax → 0x9E1d192bd9c4dc67617D47381090DDb84db8d6C5 ║
 * ╚══════════════════════════════════════════════════════════════╝
 *
 * HOW IT WORKS:
 * 1. Warrior 1 calls openArena(charId) + sends ETH (the Death Toll)
 * 2. Warrior 2 calls enterArena(arenaId, charId) + sends SAME ETH amount
 * 3. Contract instantly resolves combat — weighted by character power
 * 4. Victor receives 95% of total pot automatically
 * 5. LnC wallet receives 5% Abyss Tax automatically
 * 6. Gas paid separately by each warrior — taken off top naturally
 * 7. If no opponent joins in 24h — warrior 1 can void and get refund
 *
 * CHARACTER POWER SCORES (out of 10000):
 * Higher power = higher win probability — but upsets can happen!
 * #1  THE DREADLORD   9500  GENESIS
 * #2  ROTMOTHER       8200  LEGENDARY
 * #3  IRONBLIGHT      9100  EPIC
 * #4  WRAITHQUEEN     8800  LEGENDARY
 * #5  BONECRUSHER     8600  RARE
 * #6  VEXMORTA        7900  EPIC
 * #7  FROSTGRAVE      8100  EPIC
 * #8  ASHRENDER       8300  RARE
 * #9  SHADOWMELD      8700  LEGENDARY
 * #10 GORECLAW        8400  EPIC
 * #11 CRYPTLURKER     7800  RARE
 * #12 SOULHARVEST     9200  GENESIS
 * #13 THORNWALL       7700  RARE
 * #14 STORMWRAITH     8000  EPIC
 * #15 MARROWFIEND     7600  RARE
 * #16 VOIDWEAVER      9000  LEGENDARY
 * #17 PLAGUEBRINGER   7500  EPIC
 * #18 HELLFORGED      9300  GENESIS
 * #19 THE ABYSS KING  9900  GENESIS BOSS
 */

contract RiskDeathToll {

    // ═══════════════════════════════════════════════════
    //  OWNERSHIP & FEES
    // ═══════════════════════════════════════════════════

    address public owner;

    // LnC wallet — receives 5% Abyss Tax on every resolved battle
    address public lncFeeWallet = 0x9E1d192bd9c4dc67617D47381090DDb84db8d6C5;

    // 500 basis points = 5.00%  (basis points: 100 = 1%)
    uint256 public abyssTaxBps = 500;

    // Global revenue tracking
    uint256 public totalAbyssTaxCollected;
    uint256 public totalDeathTollPaid;

    // ═══════════════════════════════════════════════════
    //  ARENA SETTINGS
    // ═══════════════════════════════════════════════════

    uint256 public constant MIN_TOLL    = 0.001 ether;  // minimum stake
    uint256 public constant MAX_TOLL    = 50 ether;     // maximum stake
    uint256 public constant TOLL_TIMEOUT = 24 hours;    // void window
    uint256 public arenaCount;                           // total arenas ever opened

    // ═══════════════════════════════════════════════════
    //  CHARACTER SYSTEM — 19 WARRIORS
    // ═══════════════════════════════════════════════════

    struct Character {
        string  name;
        string  class;
        string  rarity;
        uint256 power;      // 0-10000, used in combat RNG weight
        uint256 speed;      // 0-100, cosmetic + tiebreaker
        uint256 defense;    // 0-100, cosmetic
        uint256 magic;      // 0-100, cosmetic
        bool    exists;
    }

    mapping(uint256 => Character) public characters;    // charId => Character
    uint256 public constant TOTAL_CHARS = 19;

    // ═══════════════════════════════════════════════════
    //  ARENA (BATTLE ROOM)
    // ═══════════════════════════════════════════════════

    enum ArenaStatus { OPEN, LOCKED, RESOLVED, VOIDED }

    struct Arena {
        uint256     id;
        address     warrior1;       // arena opener
        address     warrior2;       // challenger
        uint256     char1;          // warrior1 character ID (1-19)
        uint256     char2;          // warrior2 character ID (1-19)
        uint256     deathToll;      // ETH per warrior (in wei)
        uint256     totalPot;       // deathToll * 2
        address     victor;         // winner address
        uint256     victorChar;     // winner character ID
        uint256     victorPayout;   // ETH sent to victor (95%)
        uint256     abyssTax;       // ETH sent to LnC (5%)
        ArenaStatus status;
        uint256     openedAt;       // timestamp
        uint256     resolvedAt;     // timestamp
        bytes32     combatSeed;     // on-chain proof of randomness
    }

    mapping(uint256 => Arena)       public arenas;
    mapping(address => uint256[])   public warriorHistory;      // all arena IDs per wallet
    mapping(address => uint256)     public totalVictories;
    mapping(address => uint256)     public totalDeathTollWon;
    mapping(address => uint256)     public totalArenas;
    mapping(address => uint256)     public totalDeathTollRisked;

    uint256[] public openArenaIds;  // currently open arenas waiting for challengers

    // ═══════════════════════════════════════════════════
    //  LEADERBOARD (top 10 winners by ETH won)
    // ═══════════════════════════════════════════════════

    address[10] public leaderboard;
    mapping(address => bool) public onLeaderboard;

    // ═══════════════════════════════════════════════════
    //  EVENTS
    // ═══════════════════════════════════════════════════

    event ArenaOpened(
        uint256 indexed arenaId,
        address indexed warrior1,
        uint256 indexed char1,
        uint256 deathToll,
        string  charName
    );
    event ArenaLocked(
        uint256 indexed arenaId,
        address indexed warrior2,
        uint256 indexed char2,
        string  charName
    );
    event BattleResolved(
        uint256 indexed arenaId,
        address indexed victor,
        address indexed loser,
        uint256 victorChar,
        string  victorName,
        uint256 payout,
        uint256 abyssTax,
        bytes32 combatSeed
    );
    event ArenaVoided(
        uint256 indexed arenaId,
        address indexed warrior1,
        uint256 refund
    );
    event LeaderboardUpdated(address indexed warrior, uint256 totalWon);
    event AbyssTaxCollected(uint256 indexed arenaId, uint256 amount);

    // ═══════════════════════════════════════════════════
    //  SECURITY — REENTRANCY GUARD
    // ═══════════════════════════════════════════════════

    uint256 private _guard = 1;
    modifier noReenter() {
        require(_guard == 1, "AOTA: reentrant call blocked");
        _guard = 2;
        _;
        _guard = 1;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "AOTA: not owner");
        _;
    }

    modifier validChar(uint256 _charId) {
        require(_charId >= 1 && _charId <= TOTAL_CHARS, "AOTA: invalid warrior ID 1-19");
        require(characters[_charId].exists, "AOTA: warrior not found");
        _;
    }

    // ═══════════════════════════════════════════════════
    //  CONSTRUCTOR — LOADS ALL 19 WARRIORS
    // ═══════════════════════════════════════════════════

    constructor() {
        owner = msg.sender;
        _loadAllWarriors();
    }

    function _loadAllWarriors() internal {
        // ID, Name, Class, Rarity, Power, Speed, Defense, Magic
        _addChar(1,  "THE DREADLORD",   "WARLORD",         "GENESIS",      9500, 40, 80, 60);
        _addChar(2,  "ROTMOTHER",        "NECROMANCER",     "LEGENDARY",    8200, 45, 40, 98);
        _addChar(3,  "IRONBLIGHT",       "BERSERKER",       "EPIC",         9100, 75, 55, 10);
        _addChar(4,  "WRAITHQUEEN",      "PHANTOM",         "LEGENDARY",    8800, 95, 25, 90);
        _addChar(5,  "BONECRUSHER",      "JUGGERNAUT",      "RARE",         8600, 20, 99, 15);
        _addChar(6,  "VEXMORTA",         "PLAGUE WITCH",    "EPIC",         7900, 55, 35, 95);
        _addChar(7,  "FROSTGRAVE",       "ICE REVENANT",    "EPIC",         8100, 50, 70, 80);
        _addChar(8,  "ASHRENDER",        "PYROCLAST",       "RARE",         8300, 65, 45, 75);
        _addChar(9,  "SHADOWMELD",       "ASSASSIN",        "LEGENDARY",    8700, 99, 20, 70);
        _addChar(10, "GORECLAW",         "BEAST REVENANT",  "EPIC",         8400, 80, 50, 20);
        _addChar(11, "CRYPTLURKER",      "STALKER",         "RARE",         7800, 88, 38, 65);
        _addChar(12, "SOULHARVEST",      "LICH",            "GENESIS",      9200, 35, 55, 99);
        _addChar(13, "THORNWALL",        "SIEGE UNDEAD",    "RARE",         7700, 15, 95, 40);
        _addChar(14, "STORMWRAITH",      "TEMPEST",         "EPIC",         8000, 92, 30, 85);
        _addChar(15, "MARROWFIEND",      "CANNIBAL",        "RARE",         7600, 60, 65, 30);
        _addChar(16, "VOIDWEAVER",       "DIMENSION LICH",  "LEGENDARY",    9000, 60, 50, 96);
        _addChar(17, "PLAGUEBRINGER",    "EPIDEMIC",        "EPIC",         7500, 48, 58, 88);
        _addChar(18, "HELLFORGED",       "INFERNAL KNIGHT", "GENESIS",      9300, 55, 85, 55);
        _addChar(19, "THE ABYSS KING",   "OVERLORD",        "GENESIS BOSS", 9900, 70, 99, 99);
    }

    function _addChar(
        uint256 _id, string memory _name, string memory _class,
        string memory _rarity, uint256 _power,
        uint256 _speed, uint256 _defense, uint256 _magic
    ) internal {
        characters[_id] = Character(_name, _class, _rarity, _power, _speed, _defense, _magic, true);
    }

    // ═══════════════════════════════════════════════════
    //  OPEN ARENA — Warrior 1 stakes Death Toll
    // ═══════════════════════════════════════════════════

    /**
     * @notice Open an arena. Stake your Death Toll (ETH) and pick your warrior.
     * @param _charId Your warrior ID (1-19). See character list above.
     * @return arenaId Share this ID with your opponent so they can enter.
     */
    function openArena(uint256 _charId)
        external
        payable
        noReenter
        validChar(_charId)
        returns (uint256)
    {
        require(msg.value >= MIN_TOLL, "Death Toll too low — min 0.001 ETH");
        require(msg.value <= MAX_TOLL, "Death Toll too high — max 50 ETH");

        arenaCount++;
        uint256 id = arenaCount;

        arenas[id] = Arena({
            id:           id,
            warrior1:     msg.sender,
            warrior2:     address(0),
            char1:        _charId,
            char2:        0,
            deathToll:    msg.value,
            totalPot:     msg.value,
            victor:       address(0),
            victorChar:   0,
            victorPayout: 0,
            abyssTax:     0,
            status:       ArenaStatus.OPEN,
            openedAt:     block.timestamp,
            resolvedAt:   0,
            combatSeed:   bytes32(0)
        });

        warriorHistory[msg.sender].push(id);
        openArenaIds.push(id);
        totalArenas[msg.sender]++;
        totalDeathTollRisked[msg.sender] += msg.value;

        emit ArenaOpened(id, msg.sender, _charId, msg.value, characters[_charId].name);
        return id;
    }

    // ═══════════════════════════════════════════════════
    //  ENTER ARENA — Warrior 2 matches Death Toll & FIGHT
    // ═══════════════════════════════════════════════════

    /**
     * @notice Enter an open arena. Match the exact Death Toll. Battle resolves instantly.
     * @param _arenaId The arena ID your opponent shared with you.
     * @param _charId  Your warrior ID (1-19).
     */
    function enterArena(uint256 _arenaId, uint256 _charId)
        external
        payable
        noReenter
        validChar(_charId)
    {
        Arena storage a = arenas[_arenaId];

        require(a.status == ArenaStatus.OPEN,          "Arena not open");
        require(msg.sender != a.warrior1,              "Cannot battle yourself");
        require(msg.value == a.deathToll,              "Must match exact Death Toll amount");
        require(block.timestamp < a.openedAt + TOLL_TIMEOUT, "Arena expired — warrior1 can void it");

        a.warrior2 = msg.sender;
        a.char2    = _charId;
        a.totalPot = a.deathToll * 2;
        a.status   = ArenaStatus.LOCKED;

        warriorHistory[msg.sender].push(_arenaId);
        totalArenas[msg.sender]++;
        totalDeathTollRisked[msg.sender] += msg.value;
        _removeFromOpen(_arenaId);

        emit ArenaLocked(_arenaId, msg.sender, _charId, characters[_charId].name);

        // ⚔️ FIGHT RESOLVES INSTANTLY ON-CHAIN
        _resolveCombat(_arenaId);
    }

    // ═══════════════════════════════════════════════════
    //  COMBAT ENGINE
    // ═══════════════════════════════════════════════════

    function _resolveCombat(uint256 _arenaId) internal {
        Arena storage a = arenas[_arenaId];

        Character memory c1 = characters[a.char1];
        Character memory c2 = characters[a.char2];

        // Total power pool — determines win probability
        // e.g. char1 power 9500 vs char2 power 7500 = 17000 total
        // char1 wins if roll < 9500 = 55.8% chance
        // char2 wins if roll >= 9500 = 44.2% chance
        uint256 totalPower = c1.power + c2.power;

        // Multi-source entropy combat seed
        // Stored on-chain for full transparency and verifiability
        bytes32 seed = keccak256(abi.encodePacked(
            block.timestamp,
            block.prevrandao,           // EIP-4399 RANDAO
            blockhash(block.number - 1),
            a.warrior1,
            a.warrior2,
            a.char1,
            a.char2,
            a.totalPot,
            _arenaId,
            arenaCount,
            gasleft()
        ));

        uint256 roll = uint256(seed) % totalPower;

        // Determine victor
        address victor;
        uint256 victorChar;
        address loser;

        if (roll < c1.power) {
            victor     = a.warrior1;
            victorChar = a.char1;
            loser      = a.warrior2;
        } else {
            victor     = a.warrior2;
            victorChar = a.char2;
            loser      = a.warrior1;
        }

        // ── DEATH TOLL SPLIT ────────────────────────────
        // Total pot split: 95% to victor, 5% to LnC
        uint256 pot     = a.totalPot;
        uint256 tax     = (pot * abyssTaxBps) / 10000;
        uint256 payout  = pot - tax;

        // Update arena record
        a.victor        = victor;
        a.victorChar    = victorChar;
        a.victorPayout  = payout;
        a.abyssTax      = tax;
        a.status        = ArenaStatus.RESOLVED;
        a.resolvedAt    = block.timestamp;
        a.combatSeed    = seed;

        // Update warrior stats
        totalVictories[victor]++;
        totalDeathTollWon[victor] += payout;
        totalAbyssTaxCollected    += tax;
        totalDeathTollPaid        += pot;

        // ── AUTOMATIC PAYOUTS ───────────────────────────
        // Victor gets 95% — instant transfer, no claiming needed
        (bool victorPaid,) = payable(victor).call{value: payout}("");
        require(victorPaid, "Victor payout failed");

        // LnC gets 5% Abyss Tax — instant transfer
        (bool taxPaid,) = payable(lncFeeWallet).call{value: tax}("");
        require(taxPaid, "Abyss Tax transfer failed");

        // Update leaderboard
        _updateLeaderboard(victor);

        emit BattleResolved(
            _arenaId, victor, loser,
            victorChar, characters[victorChar].name,
            payout, tax, seed
        );
        emit AbyssTaxCollected(_arenaId, tax);
    }

    // ═══════════════════════════════════════════════════
    //  VOID ARENA — Get refund if no challenger in 24h
    // ═══════════════════════════════════════════════════

    /**
     * @notice If no opponent joined after 24h, warrior1 can void and get full refund.
     */
    function voidArena(uint256 _arenaId) external noReenter {
        Arena storage a = arenas[_arenaId];
        require(a.warrior1 == msg.sender,                       "Not your arena");
        require(a.status == ArenaStatus.OPEN,                   "Cannot void — not open");
        require(block.timestamp >= a.openedAt + TOLL_TIMEOUT,   "Wait 24h before voiding");

        a.status = ArenaStatus.VOIDED;
        _removeFromOpen(_arenaId);

        uint256 refund = a.deathToll;
        totalDeathTollRisked[msg.sender] -= refund; // reverse the risk since it was voided

        (bool sent,) = payable(msg.sender).call{value: refund}("");
        require(sent, "Refund failed");

        emit ArenaVoided(_arenaId, msg.sender, refund);
    }

    // ═══════════════════════════════════════════════════
    //  LEADERBOARD
    // ═══════════════════════════════════════════════════

    function _updateLeaderboard(address _warrior) internal {
        if (onLeaderboard[_warrior]) {
            // Already on board — re-sort
            _sortLeaderboard();
            return;
        }
        // Check if they beat anyone on the board
        for (uint256 i = 0; i < 10; i++) {
            if (leaderboard[i] == address(0) ||
                totalDeathTollWon[_warrior] > totalDeathTollWon[leaderboard[i]]) {
                // Shift down and insert
                for (uint256 j = 9; j > i; j--) {
                    leaderboard[j] = leaderboard[j-1];
                    if (leaderboard[j] != address(0)) onLeaderboard[leaderboard[j]] = true;
                }
                if (leaderboard[9] != address(0)) onLeaderboard[leaderboard[9]] = false;
                leaderboard[i] = _warrior;
                onLeaderboard[_warrior] = true;
                emit LeaderboardUpdated(_warrior, totalDeathTollWon[_warrior]);
                return;
            }
        }
    }

    function _sortLeaderboard() internal {
        for (uint256 i = 0; i < 9; i++) {
            for (uint256 j = 0; j < 9 - i; j++) {
                if (leaderboard[j] != address(0) && leaderboard[j+1] != address(0)) {
                    if (totalDeathTollWon[leaderboard[j]] < totalDeathTollWon[leaderboard[j+1]]) {
                        address temp = leaderboard[j];
                        leaderboard[j] = leaderboard[j+1];
                        leaderboard[j+1] = temp;
                    }
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════
    //  VIEW FUNCTIONS — Read all game data
    // ═══════════════════════════════════════════════════

    /// @notice Get full arena data
    function getArena(uint256 _id) external view returns (Arena memory) {
        return arenas[_id];
    }

    /// @notice Get all currently open arena IDs
    function getOpenArenas() external view returns (uint256[] memory) {
        return openArenaIds;
    }

    /// @notice Get all arena IDs a warrior has participated in
    function getWarriorHistory(address _w) external view returns (uint256[] memory) {
        return warriorHistory[_w];
    }

    /// @notice Get warrior stats
    function getWarriorStats(address _w) external view returns (
        uint256 arenas_,
        uint256 victories_,
        uint256 ethWon_,
        uint256 ethRisked_
    ) {
        return (
            totalArenas[_w],
            totalVictories[_w],
            totalDeathTollWon[_w],
            totalDeathTollRisked[_w]
        );
    }

    /// @notice Get global contract stats
    function getGlobalStats() external view returns (
        uint256 totalArenas_,
        uint256 totalPaid_,
        uint256 totalTax_,
        uint256 contractBalance_
    ) {
        return (
            arenaCount,
            totalDeathTollPaid,
            totalAbyssTaxCollected,
            address(this).balance
        );
    }

    /// @notice Get character info
    function getCharacter(uint256 _id) external view returns (Character memory) {
        require(_id >= 1 && _id <= TOTAL_CHARS, "Invalid ID");
        return characters[_id];
    }

    /// @notice Get all 19 character power scores at once
    function getAllPowers() external view returns (uint256[19] memory powers) {
        for (uint256 i = 0; i < 19; i++) {
            powers[i] = characters[i+1].power;
        }
    }

    /// @notice Get top 10 leaderboard
    function getLeaderboard() external view returns (
        address[10] memory warriors,
        uint256[10] memory ethWon_,
        uint256[10] memory wins_
    ) {
        for (uint256 i = 0; i < 10; i++) {
            warriors[i] = leaderboard[i];
            if (leaderboard[i] != address(0)) {
                ethWon_[i] = totalDeathTollWon[leaderboard[i]];
                wins_[i]   = totalVictories[leaderboard[i]];
            }
        }
    }

    /// @notice Calculate expected payout for a given Death Toll
    function calcPayout(uint256 _deathToll) external view returns (
        uint256 pot,
        uint256 victorPayout,
        uint256 abyssTax_
    ) {
        pot          = _deathToll * 2;
        abyssTax_    = (pot * abyssTaxBps) / 10000;
        victorPayout = pot - abyssTax_;
    }

    /// @notice Get win probability for char1 vs char2 (returns basis points)
    function getWinChance(uint256 _char1, uint256 _char2) external view returns (
        uint256 char1WinBps,
        uint256 char2WinBps
    ) {
        require(_char1 >= 1 && _char1 <= 19 && _char2 >= 1 && _char2 <= 19);
        uint256 p1 = characters[_char1].power;
        uint256 p2 = characters[_char2].power;
        uint256 total = p1 + p2;
        char1WinBps = (p1 * 10000) / total;
        char2WinBps = (p2 * 10000) / total;
    }

    // ═══════════════════════════════════════════════════
    //  ADMIN — Owner only
    // ═══════════════════════════════════════════════════

    /// @notice Update LnC fee wallet
    function setLncFeeWallet(address _w) external onlyOwner {
        require(_w != address(0), "Zero address");
        lncFeeWallet = _w;
    }

    /// @notice Adjust Abyss Tax (max 10%)
    function setAbyssTax(uint256 _bps) external onlyOwner {
        require(_bps <= 1000, "Max 10%");
        abyssTaxBps = _bps;
    }

    /// @notice Update a character's power score
    function setCharPower(uint256 _id, uint256 _power) external onlyOwner {
        require(_id >= 1 && _id <= TOTAL_CHARS, "Invalid ID");
        require(_power <= 10000, "Max power 10000");
        characters[_id].power = _power;
    }

    /// @notice Transfer ownership
    function transferOwnership(address _new) external onlyOwner {
        require(_new != address(0), "Zero address");
        owner = _new;
    }

    // ═══════════════════════════════════════════════════
    //  INTERNAL HELPERS
    // ═══════════════════════════════════════════════════

    function _removeFromOpen(uint256 _id) internal {
        uint256 len = openArenaIds.length;
        for (uint256 i = 0; i < len; i++) {
            if (openArenaIds[i] == _id) {
                openArenaIds[i] = openArenaIds[len - 1];
                openArenaIds.pop();
                break;
            }
        }
    }

    /// @dev Block direct ETH sends — use openArena or enterArena
    receive() external payable {
        revert("AOTA: Send ETH via openArena() or enterArena()");
    }

    fallback() external payable {
        revert("AOTA: Function not found");
    }
}
