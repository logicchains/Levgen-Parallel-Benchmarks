// Compile with:
// ldc2 -O2 -release -singleobj -wi -disable-boundscheck <file.d>

module deterministic;

import std.stdio, std.random, std.parallelism;

enum LEVEL_SIZE     =  50;   /// Width and height of a level
enum ROOM_MIN       =   3;   /// Rooms will be at least this large.
enum ROOM_MAX       =  10;   /// Rooms will be at most this large.

enum NUM_LEVS       = 800;

alias ℕ = size_t;

// Helpers for bit counting.

/// 64-bit population count algorithm. For LDC the intrinsics have a good fallback if POPCNT doesn't exist.
ℕ countBitsD(ℕ i) pure nothrow {
	version (LDC) {
		import ldc.intrinsics;
		return llvm_ctpop(i);
	} else static if (ℕ.sizeof == 4) {
		import core.bitop;
		return popcnt(i);
	} else {
		i = i - ((i >> 1) & 0x5555555555555555uL);
		i = (i & 0x3333333333333333uL) + ((i >> 2) & 0x3333333333333333uL);
		return (((i + (i >> 4)) & 0xF0F0F0F0F0F0F0FuL) * 0x101010101010101uL) >> 56;
	}
}

// For GDC we have to determine at runtime wether POPCNT is supported since the compiler
// intrinsic has a slow fallback.
version(GNU) {
	__gshared ℕ function(ℕ) countBits = &countBitsD;

	shared static this() {
		import core.cpuid;
		if (hasPopcnt) {
			countBits = function(ℕ i) pure nothrow {
				import gcc.builtins;
				static if (ℕ.sizeof == 4) {
					return __builtin_popcount(i);
				} else {
					return __builtin_popcount(i & uint.max) + __builtin_popcount(i >> 32);
				}
			};
		}
	}
} else {
	alias countBits = countBitsD;
}

// Room and level generation structures

struct Room {
	ℕ x, y, w, h;
}

template LevelGen(ℕ levelSize, ℕ roomMin, ℕ roomMax) {
	/// The number of different room widths/heights.
	enum roomSizes = roomMax + 1 - roomMin;
	/// Number of positions for the smallest room on one axis.
	enum minRoomSlots = levelSize - 1 - roomMin;
	/// Number of positions for the largest room on one axis.
	enum maxRoomSlots = levelSize - 1 - roomMax;
	/// Number of possibilities to place different rooms along one axis.
	enum optionsPerAxis = (minRoomSlots + maxRoomSlots) * roomSizes / 2;
	/// Number of bits in a machine word.
	enum wordBits = ℕ.sizeof * 8;
	/// Set if internal representations of the levels always fit into a machine word. (Minor optimization.)
	enum singleWord = minRoomSlots < wordBits;

	/**
	 * Returns at compile-time a lookup table that maps room sizes to how many placement
	 * options exist for them on an empty level.
	 */
	enum initialAvailableOptionCntsPerRoom() {
		ℕ[roomSizes][roomSizes] result;
		foreach (w; roomMin .. roomMax + 1) {
			foreach (h; roomMin .. roomMax + 1) {
				immutable cnt = cast(uint) ((levelSize - 1 - w) * (levelSize - 1 - h));
				result[w - roomMin][h - roomMin] = cnt;
			}
		}
		return result;
	}

	struct Level {
		/// The maximum number of rooms that can be in a single level.
		enum roomLimit = ((levelSize - 1) / (roomMin + 1)) ^^ 2;

		Room[roomLimit] rooms;
		ℕ roomCnt = 0;
		ubyte[levelSize][levelSize] tiles;

		void dump() const @trusted {
			foreach (row; 0 .. levelSize) {
				foreach (col; 0 .. LEVEL_SIZE) {
					write( this.tiles[row][col] ? "  " : "██" );
				}
				writeln();
			}
		}
	}

	enum blockedArraySize() {
		ℕ words = 0;
		foreach (w; maxRoomSlots .. minRoomSlots + 1) {
			words += (w + wordBits - 1) / wordBits;
		}
		return words * optionsPerAxis;
	}

	enum calcBlockedOffsets() {
		ℕ[roomSizes][roomSizes] result;
		ℕ offset = 0;
		foreach (h; roomMin .. roomMax + 1) {
			immutable hSlots = levelSize - 1 - h;
			foreach (w; roomMin .. roomMax + 1) {
				result[w - roomMin][h - roomMin] = offset;
				immutable wWords = (levelSize - 1 - w + wordBits - 1) / wordBits;
				offset += hSlots * wWords;
			}
		}
		return result;
	}

	enum initialBlockedPositions() {
		ℕ[blockedArraySize()] result;
		ℕ offset = 0;
		foreach (h; roomMin .. roomMax + 1) {
			immutable hSlots = levelSize - 1 - h;
			foreach (w; roomMin .. roomMax + 1) {
				immutable wWords = (levelSize - 1 - w + wordBits - 1) / wordBits;
				immutable strideBits = (levelSize - 1 - w) % wordBits;
				if (strideBits != 0) {
					immutable strideMask = ℕ.max << strideBits;
					auto pos = &result[offset + wWords - 1];
					foreach (y; 0 .. levelSize - 1 - h) {
						*pos = strideMask;
						if (y != levelSize - 2 - h) {
							pos += wWords;
						}
					}
				}
				offset += hSlots * wWords;
			}
		}
		return result;
	}

	struct RoomGenerator {
		/// Total number of possibilities to place any kind of room on an empty level.
		enum totalOptionCnt = optionsPerAxis * optionsPerAxis;

		/**
		 * The options are ordered as follows:
		 * On the highest order are room sizes, smallest room first, then increasing width, then increasing height.
		 * For every room there is a bitmap with all available positions for this room size.
		 */
		ℕ[blockedArraySize()] blocked = initialBlockedPositions();
		/// Offsets into the 'blocked' array corresponding to given room sizes.
		immutable static ℕ[roomSizes][roomSizes] blockedOffsets = calcBlockedOffsets();
		/// All currently available room positions. This is the sum of 'availableOptionCntsPerRoom'.
		ℕ availableOptionCnt = totalOptionCnt;
		/// Available room positions broken down by room sizes.
		ℕ[roomSizes][roomSizes] availableOptionCntsPerRoom = initialAvailableOptionCntsPerRoom();

		/**
		 * Retrieves a rectangular area from 'blocked' that is reserved for the possible positions of rooms of
		 * size w*h.
		 */
		ℕ* bitmapForRoomDims(ℕ w, ℕ h) {
			return &this.blocked[this.blockedOffsets[w - roomMin][h - roomMin]];
		}

		/// Places the n-th option of rooms sized w*h in the level.
		void placeRoom(ℕ w, ℕ h, ℕ option, ref Level level) {
			const(ℕ*) bitmap = this.bitmapForRoomDims(w, h);
			const(ℕ)* bitptr = bitmap;
			immutable stride = (levelSize - 1 - w + wordBits - 1) / wordBits;

			while (wordBits - countBits(*bitptr) <= option) {
				option -= wordBits - countBits(*bitptr++);
			}

			ℕ bit = 0;
			while (option) {
				if (!(*bitptr & (1uL << bit++))) {
					option--;
				}
			}
			while (*bitptr & (1uL << bit)) {
				bit++;
			}
			immutable x = (bitptr - bitmap) % stride * wordBits + bit;
			immutable y = (bitptr - bitmap) / stride;
			this.placeRoom(x, y, w, h, level);
		}

		/// Used internally by the other overload, to place a room at a known good position.
		void placeRoom(ℕ x, ℕ y, ℕ w, ℕ h, ref Level level) {
			this.makeSlotsUnavailable(x, y, x + w, y + h);
			level.rooms[level.roomCnt++] = Room(x, y, w, h);
			foreach (ly; y + 1 .. y + h + 1) {
				foreach (lx; x + 1 .. x + w + 1) {
					level.tiles[ly][lx] = 1;
				}
			}
		}

		/**
		 * Given an occluded area, this function marks room positions as unavailable where the room would
		 * overlap the area. This also updates the probabilities for each room size and the total available
		 * room positions count 'availableOptionCnt'.
		 */
		void makeSlotsUnavailable(ℕ x1, ℕ y1, ℕ x2, ℕ y2) {
			foreach (h; roomMin .. roomMax + 1) {
				foreach (w; roomMin .. roomMax + 1) {
					// Don't try to mark any squares as blocked if there are none left.
					if (this.availableOptionCntsPerRoom[w - roomMin][h - roomMin] == 0)
						continue;

					auto bitmap = this.bitmapForRoomDims(w, h);
					// Calculate actual affected area for this room size.
					ℕ rx1 = (x1 > w) ? x1 - w : 0;
					ℕ ry1 = (y1 > h) ? y1 - h : 0;
					ℕ rx2 = (x2 + 1 < levelSize - 1 - w) ? x2 + 1 : levelSize - 1 - w;
					ℕ ry2 = (y2 + 1 < levelSize - 1 - h) ? y2 + 1 : levelSize - 1 - h;

					// Disable all options in this area.
					ℕ removedOptions = 0;
					immutable stride = (levelSize - 1 - w + wordBits - 1) / wordBits;
					immutable initialMask = ℕ.max << (rx1 % wordBits);
					immutable finalMask = ~(ℕ.max << (rx2 % wordBits));
					if (singleWord || rx1 / wordBits == rx2 / wordBits) {
						// All bits are in the same word.
						immutable mask = initialMask & finalMask;
						foreach (y; ry1 .. ry2) {
							auto wordptr = &bitmap[stride * y + rx1 / wordBits];
							removedOptions += countBits(~*wordptr & mask);
							*wordptr |= mask;
						}
					} else {
						foreach (y; ry1 .. ry2) {
							// initial
							auto wordptr = &bitmap[stride * y + rx1 / wordBits];
							removedOptions += countBits(~*wordptr & initialMask);
							*wordptr++ |= initialMask;
							ℕ x = (rx1 / wordBits + 1) * wordBits;
							// central
							while (x + wordBits <= rx2) {
								removedOptions += countBits(~*wordptr);
								*wordptr++ = ℕ.max;
								x += wordBits;
							}
							// final
							if (x < rx2) {
								removedOptions += countBits(~*wordptr & finalMask);
								*wordptr |= finalMask;
							}
						}
					}
					this.availableOptionCntsPerRoom[w - roomMin][h - roomMin] -= removedOptions;
					this.availableOptionCnt -= removedOptions;
				}
			}
		}
	}
}

// Main function

alias MyLevelGen = LevelGen!(LEVEL_SIZE, ROOM_MIN, ROOM_MAX);

// Global variables are thread local in D.
Random perThreadRng;

static this() {
	// Per thread module ctor.
	perThreadRng = Random(unpredictableSeed);
}

void main() @system {
	MyLevelGen.Level[NUM_LEVS] levels;

	// Process levels in parallel with a batch size of 1 level.
	foreach (i, ref level; parallel(levels[], 1)) {
		MyLevelGen.RoomGenerator rg;
		while (rg.availableOptionCnt) {
			/* Respecting the current potential success of placing a room of a certain size,
			   we pick a width and height. */
			ℕ option = uniform(0, rg.availableOptionCnt);
			ℕ w, h;
		SizeSearch: 
			for (h = 0; h < MyLevelGen.roomSizes; h++) {
				for (w = 0; w < MyLevelGen.roomSizes; w++) {
					if (option < rg.availableOptionCntsPerRoom[w][h]) {
						break SizeSearch;
					}
					option -= rg.availableOptionCntsPerRoom[w][h];
				}
			}
			w += ROOM_MIN;
			h += ROOM_MIN;

			rg.placeRoom(w, h, option, level);
		}
	}

	// Print one of the levels.
	levels[0].dump();
}
