#include <inttypes.h>
#include <vector>
#include <stdlib.h>
#include <stdio.h>
#include <time.h>
#include <thread>

const uint32_t TILE_DIM = 50;
const uint32_t MIW = 2;
const uint32_t MAXWID = 8;
const uint32_t NUM_LEVS = 800;
const uint32_t NUM_THREADS = 4;
const uint32_t NUM_LEVS_PER_THREAD = NUM_LEVS / NUM_THREADS;

struct GenRandGenerator {
    uint32_t operator()( uint32_t & gen ) {
        gen += gen;
        gen ^= 1;
        int32_t tgen=gen;
        if ( tgen < 0) {
            gen ^= 0x88888eef;
        }
        return gen;
    }
};

struct Tile {
    uint32_t X, Y;
    bool T;
};

struct Room {
    uint32_t x, y, w, h, roomNum;
};

struct Level {
    Level() : tiles( 2500 ) {
        for( std::size_t t = 0 ; t < 2500 ; t++ ) {
            tiles[t].X = t % TILE_DIM;
            tiles[t].Y = t / TILE_DIM;
            tiles[t].T = false;
        }
        rooms.reserve( 100 );
    }

    void fillTiles() {
        for( std::vector<Room>::iterator rIter = rooms.begin(),
                 end = rooms.end() ; rIter != end ; ++rIter ) {
            for( uint32_t yi = rIter->y ; yi <= ( rIter->y + rIter->h ) ; ++yi ) {
                for( uint32_t xi = rIter->x ; xi <= ( rIter->x + rIter->w ) ; ++xi ) {
                    tiles[ yi * TILE_DIM + xi ].T = true;
                }
            }
        }
    }
    std::vector<Tile> tiles;
    std::vector<Room> rooms;
};

template <typename RandomGenerator>
class LevelGenerator {
    void makeRoomSilentlyFail( Level & level, uint32_t & gen ) {
        uint32_t x( nextRandomGenerator_( gen ) % TILE_DIM );
        uint32_t y( nextRandomGenerator_( gen ) % TILE_DIM );
        uint32_t w( (nextRandomGenerator_( gen ) % MAXWID) + MIW );
        uint32_t h( (nextRandomGenerator_( gen ) % MAXWID) + MIW );

        if( (x+w) < TILE_DIM && (y+h) < TILE_DIM && x != 0 && y != 0 &&
            !isCollision( level.rooms, x, y, w, h ) ) {
            level.rooms.push_back( Room { x, y, w, h,
                        (uint32_t)(level.rooms.size() + 1) } );
        }
    }

    bool isCollision( std::vector<Room> & rooms, const uint32_t x,
                      const uint32_t y, const uint32_t w, const uint32_t h ) {
        for( std::vector<Room>::iterator rIter = rooms.begin(),
                 end = rooms.end() ; rIter != end ; ++rIter ) {
            if( !( ((rIter->x + rIter->w + 1 ) < x || rIter->x > (x + w + 1 )) ||
                   ((rIter->y + rIter->h + 1) < y || rIter->y > (y + h + 1 )) ) ) {
                return true;
            }
        }
        return false;
    }
    RandomGenerator nextRandomGenerator_;
    std::vector<Level> levels_;
public:
    LevelGenerator( RandomGenerator randomGenerator, const uint32_t numLevels ) :
        nextRandomGenerator_( randomGenerator ), levels_( numLevels, Level() ) {}

    void partitionedGenerateLevels( uint32_t seed, const uint32_t partitionStartIndex,
                                    const uint32_t partitionEndIndex ) {
        for( std::size_t i = partitionStartIndex ; i < partitionEndIndex ; ++i ) {
            for( std::size_t ii = 0 ; ii < 50000 ; ii++ ) {
                makeRoomSilentlyFail( levels_[i], seed );
                if( levels_[i].rooms.size() == 99 ) {
                    break;
                }
            }
            levels_[i].fillTiles();
        }
    }

    template <typename LevelMetric>
    Level & pickLevelByCriteria( LevelMetric levelMetric ) {
        std::vector<Level>::iterator lIter = levels_.begin(),
            lEnd = levels_.end();
        Level & result( *lIter++ );
        for( ; lIter != lEnd ; ++lIter ) {
            if( levelMetric.isBetterLevel( result, *lIter ) ) {
                result = *lIter;
            }
        }
        return result;
    }
};

struct NumRoomsMetric {
    bool isBetterLevel( const Level & x, const Level & y ) {
        return y.rooms.size() > x.rooms.size();
    }
};

void printLevel( const Level & level ) {
    for( uint32_t i = 0 ; i < 2500 ; i++ ) {
        printf( "%d", (level.tiles[i].T ? 1 : 0 ) );
        if( i % ( TILE_DIM ) == 49 && i != 0 ) printf( "\n" );
    }
}

void generateLevels( const uint32_t threadNum, const uint32_t threadSeed,
                     LevelGenerator<GenRandGenerator> & levelGenerator ) {
    uint32_t loopStartIndex( threadNum * NUM_LEVS_PER_THREAD );
    uint32_t loopEndIndex( loopStartIndex + NUM_LEVS_PER_THREAD );
    printf("The seed of thread %d is: %d\n", threadNum + 1, threadSeed );
    levelGenerator.partitionedGenerateLevels( threadSeed, loopStartIndex,
                                              loopEndIndex );
}

int main(int argc, char* argv[]) {
	clock_t start, stop;
	start = clock();
	int v = atoi(argv[1]);
	printf("The random seed is: %d \n", v);
	srand(v);
    uint32_t gen( v );

    GenRandGenerator randGenerator;
    LevelGenerator<GenRandGenerator> levelGenerator( randGenerator, NUM_LEVS );

    std::vector<std::thread> threads( NUM_THREADS );
    for( uint32_t i = 0 ; i < NUM_THREADS ; ++i ) {
        gen = v * ((i+1)*(i+1));
        threads[i] = std::move( std::thread { generateLevels, i, gen, std::ref(levelGenerator) } );
    }

    for( uint32_t i = 0 ; i < NUM_THREADS ; ++i ) {
        threads[i].join();
    }
    NumRoomsMetric numRoomsMetric;
    Level & l( levelGenerator.pickLevelByCriteria( numRoomsMetric ) );
    printLevel( l );

	stop = clock();
	long clocks_per_ms = CLOCKS_PER_SEC/1000;
    printf("%d\n", (stop - start)/clocks_per_ms);
    return 0;
}
