#include <cstdint>
#include <vector>
#include <cstdlib>
#include <iostream>
#include <time.h>
#include <thread>
#include <cassert>
#include <cstring>


const uint32_t TILE_DIM = 50;
const uint32_t WIDMIN = 2;
const uint32_t RESTWIDMAX = 8;
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
    Room(uint32_t x, uint32_t y, uint32_t w, uint32_t h, uint32_t roomNum)
        : x(x), y(y), w(w), h(h), roomNum(roomNum) { }

    uint32_t x, y, w, h, roomNum;
};

struct Level {
    Level() : tiles( 2500 ) {
        for( uint32_t t = 0 ; t < 2500 ; t++ ) {
            tiles[t].X = t % TILE_DIM;
            tiles[t].Y = t / TILE_DIM;
            tiles[t].T = false;
        }
        rooms.reserve( 100 );
    }

    void fillTiles() {
        for( const Room & r : rooms ) {
            for( uint32_t yi = r.y ; yi <= ( r.y + r.h ) ; ++yi ) {
                for( uint32_t xi = r.x ; xi <= ( r.x + r.w ) ; ++xi ) {
                    tiles[ yi * TILE_DIM + xi ].T = true;
                }
            }
        }
    }

    std::vector<Tile> tiles;
    std::vector<Room> rooms;
};

class OcclusionBuffer{
    std::vector<uint8_t> buffer;
    int width;
    int height;
public:
    OcclusionBuffer(int w, int h)
    :buffer(w*h), width(w), height(h){
        
    };
    
    bool IsOccluded(int minx, int miny, int maxx, int maxy){
        int      line   = maxx-minx+1;
        int      lines  = maxy-miny+1;
        int      stride = width-line;
        uint8_t* p      = buffer.data()+minx+width*miny;
        
        // test region if any point is marked
        while(lines--){
            int templine = line;
            while(templine--){
                if (*p)
                    return true;
                p++;
            }
            p+=stride;
        }
        return false;
    }
    
    void Occlude(int minx, int miny, int maxx, int maxy){
        int      line   = maxx-minx+1;
        int      lines  = maxy-miny+1;
        int      stride = width-line;
        uint8_t* p      = buffer.data()+minx+width*miny;
        
        //mark region
        while(lines--){
            int templine = line;
            while(templine--){
                *p = 1;
                p++;
            }
            p+=stride;
        }
    }
    
    void Clear(){
        memset(buffer.data(), 0, width*height);
    }
};

template <typename RandomGenerator>
class LevelGenerator {
    bool makeRoomSilentlyFail( Level & level, uint32_t & gen, OcclusionBuffer& occ ) {
        uint32_t x( nextRandomGenerator_( gen ) % TILE_DIM );
        uint32_t y( nextRandomGenerator_( gen ) % TILE_DIM );
        uint32_t w( (nextRandomGenerator_( gen ) % RESTWIDMAX) + WIDMIN );
        uint32_t h( (nextRandomGenerator_( gen ) % RESTWIDMAX) + WIDMIN );

        if( (x+w) < TILE_DIM-1 && (y+h) < TILE_DIM-1 && x != 0 && y != 0 &&
            !isCollision( x, y, w, h, occ ) ) {
                occ.Occlude(x, y, x+w, y+h);
                level.rooms.emplace_back(x, y, w, h, (uint32_t)(level.rooms.size() + 1));
                return true;
        }
        return false;
    }

    static bool isCollision(const uint32_t x,
                      const uint32_t y, const uint32_t w, const uint32_t h, OcclusionBuffer &occ ) {
        return occ.IsOccluded(x-1, y-1, x+w+1, y+h+1);
    }
    RandomGenerator nextRandomGenerator_;
    std::vector<Level> levels_;
    
public:
    LevelGenerator( RandomGenerator randomGenerator, const uint32_t numLevels ) :
        nextRandomGenerator_( randomGenerator ), levels_( numLevels, Level() ) {}

    void partitionedGenerateLevels( uint32_t seed, const uint32_t partitionStartIndex,
                                    const uint32_t partitionEndIndex ) {
        OcclusionBuffer occ(TILE_DIM, TILE_DIM);
        for( uint32_t i = partitionStartIndex ; i < partitionEndIndex ; ++i ) {
            occ.Clear();
            uint32_t roomsAdded = 0;
            for( uint32_t ii = 0 ; ii < 50000 ; ii++ ) {
                roomsAdded += static_cast<size_t>(makeRoomSilentlyFail( levels_[i], seed, occ ));
                if (roomsAdded == 99) break;
            }
            levels_[i].fillTiles();
        }
    }

    template <typename LevelMetric>
    Level & pickLevelByCriteria( LevelMetric levelMetric ) {
        auto lIter = levels_.begin(), lEnd = levels_.end();
        Level * result( &*lIter++ );
        for( ; lIter != lEnd ; ++lIter ) {
            if( levelMetric.isBetterLevel( *result, *lIter ) ) {
                result = &*lIter;
            }
        }
        return *result;
    }
};

struct NumRoomsMetric {
    bool isBetterLevel( const Level & x, const Level & y ) {
        return y.rooms.size() > x.rooms.size();
    }
};

void printLevel( const Level & level ) {
    for( uint32_t i = 0 ; i < 2500 ; i++ ) {
        std::cout <<  (level.tiles[i].T ? 1 : 0 );
        if( i % ( TILE_DIM ) == 49 && i != 0 ) std::cout << std::endl;
    }
}

int main(int argc, char* argv[]) {
    clock_t start, stop;
    start = clock();
    //int v = atoi(argv[1]);
    int v = 10; // nicer for IDE/Profiler
    std::cout << "The random seed is: " << v << std::endl;
    srand(v);

    GenRandGenerator randGenerator;
    LevelGenerator<GenRandGenerator> levelGenerator( randGenerator, NUM_LEVS );

    std::vector<std::thread> threads; threads.reserve( NUM_THREADS );
    for( uint32_t i = 0 ; i < NUM_THREADS ; ++i ) {
        uint32_t threadSeed = v * ((i+1)*(i+1));
        std::cout << "The seed of thread " << i << " is: " << threadSeed << std::endl;
        uint32_t partitionStartIndex( i * NUM_LEVS_PER_THREAD );
        uint32_t partitionEndIndex( partitionStartIndex + NUM_LEVS_PER_THREAD );
        threads.emplace_back(std::bind( &LevelGenerator<GenRandGenerator>::partitionedGenerateLevels,
                           &levelGenerator, threadSeed, partitionStartIndex, partitionEndIndex ));
    }

    for( uint32_t i = 0 ; i < NUM_THREADS ; ++i ) {
        threads[i].join();
    }
    NumRoomsMetric numRoomsMetric;
    Level & l( levelGenerator.pickLevelByCriteria( numRoomsMetric ) );
    printLevel( l );

    stop = clock();
    long clocks_per_ms = CLOCKS_PER_SEC/1000;
    std::cout << (stop - start)/clocks_per_ms << std::endl;
    return 0;
}
