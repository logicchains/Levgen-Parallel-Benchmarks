using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Text;

namespace Levgen
{
    public enum TileType { Rock, Room }

    public struct Tile
    {
        public TileType Type;
    }

    public class Room
    {
        public int X;
        public int Y;
        public int W;
        public int H;
                
        public bool Intersects(Room otherRoom)
        {
            var roomDoesntIntersect = 
                (X + W + 1) < otherRoom.X || X > (otherRoom.X + otherRoom.W + 1) || 
                (Y + H + 1) < otherRoom.Y || Y > (otherRoom.Y + otherRoom.H + 1);
            return !roomDoesntIntersect;
        }
    }

    public class Level
    {
        private readonly List<Room> _rooms;
        private readonly int _tileDim;
        private readonly Tile[] _tiles;

        public Level(int numRooms, int tileDim)
        {
            _tiles = new Tile[tileDim*tileDim];
            _rooms = new List<Room>(numRooms);
            _tileDim = tileDim;
        }

        public int NumberOfRooms
        {
            get { return _rooms.Count; }
        }

        static void GenerateTilesForRoom(Room room, Tile[] ts, int tileDim)
        {
            int x = room.X;
            int y = room.Y;
            int w = room.W;
            int h = room.H;
            
            for (int xi = x; xi <= x + w; xi++)
            {
                for (int yi = y; yi <= y + h; yi++)
                {
                    int num = yi * tileDim + xi;
                    ts[num].Type = TileType.Room;
                }
            }
        }

        bool IntersectsExistingRooms(Room room)
        {
            // manual foreach is a lot faster than Any here
            foreach (var r in _rooms)
            {
                if (r.Intersects(room))
                    return true;
            }
            return false;
        }

        public bool TryAddRoom(Room room)
        {
            if (!IntersectsExistingRooms(room))
            {
                _rooms.Add(room);
                GenerateTilesForRoom(room, _tiles, _tileDim);
                return true;
            }
            return false;
        }

        public override string ToString()
        {
            var tiles = _tiles;
            var sb = new StringBuilder();
            for (int i = 0; i < _tileDim*_tileDim; i++)
            {
                sb.Append(Convert.ToInt32(tiles[i].Type));
                if (i % (_tileDim) == 49 && i != 0) sb.AppendLine();
            }
            return sb.ToString();
        }
    }

    internal class GenRand
    {
        private uint _gen;

        public GenRand(uint seed)
        {
            _gen = seed;
        }
        
        public int Next()
        {
            var gen = _gen;
            gen += gen;
            gen ^= 1;
            if ((int)gen < 0)
            {
                gen ^= 0x88888eef;
            }
            _gen = gen;
            return (int)gen;
        }
    }

    public class LevelSettings
    {
        public LevelSettings(int maxRooms, int tileDim, int restWidMax, int widMin, int roomInsertionAttempts)
        {
            MaxRooms = maxRooms;
            WidMin = widMin;
            RoomInsertionAttempts = roomInsertionAttempts;
            RestWidMax = restWidMax;
            TileDim = tileDim;
        }

        public int TileDim { get; private set; }
        public int RestWidMax { get; private set; }
        public int WidMin { get; private set; }
        public int RoomInsertionAttempts { get; private set; }
        public int MaxRooms { get; private set; }
    }

    public class LevelMaker
    {
        private readonly GenRand _rand;

        public LevelMaker(uint seed)
        {
            _rand = new GenRand(seed);
        }

        public IEnumerable<Level> MakeLevels(LevelSettings settings)
        {
            while(true)
            {
                var lev = new Level(settings.MaxRooms, settings.TileDim);

                int roomCount = 0;
                for (int attempt = 0; attempt < settings.RoomInsertionAttempts; attempt++)
                {
                    var x = _rand.Next() % settings.TileDim;
                    var y = _rand.Next() % settings.TileDim;
                    var w = _rand.Next() % settings.RestWidMax + settings.WidMin;
                    var h = _rand.Next() % settings.RestWidMax + settings.WidMin;

                    if (x + w >= settings.TileDim || y + h >= settings.TileDim || x == 0 || y == 0) continue;
                    var room = new Room{X=x, Y=y, W=w, H=h};
                    if (lev.TryAddRoom(room))
                    {
                        if (++roomCount == settings.MaxRooms)
                            break;
                    }
                }

                yield return lev;
            }
        }
    }

    public static class Program
    {    
        public static void Main(string[] args)
        {
            var sw = new Stopwatch();
            sw.Start();

            const int NumLevels = 800;

            var numThreads = Environment.ProcessorCount;
            var levelsPerThread = NumLevels / numThreads;
            
            var seed = uint.Parse(args[0]);
            Console.WriteLine("The random seed is: {0}", seed);
        
            var levelSettings = new LevelSettings(maxRooms: 99, tileDim: 50, restWidMax: 8, widMin: 2, roomInsertionAttempts: 50000);
    
            var levels = Enumerable.Range(0, numThreads).AsParallel().SelectMany(threadId =>
            {
                var threadSeed = (uint)(seed*(threadId + 1)*(threadId + 1));
                Console.WriteLine("The seed for thread {0} is: {1}", threadId+1, threadSeed);
                return new LevelMaker(threadSeed).MakeLevels(levelSettings).Take(levelsPerThread);
            });
            
            var bestLevel = levels.OrderByDescending(x => x.NumberOfRooms).First();
            
            Console.WriteLine(bestLevel);
            Console.WriteLine((int)Math.Round(sw.Elapsed.TotalMilliseconds));
        }
    }
}