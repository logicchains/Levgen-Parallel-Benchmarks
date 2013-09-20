{-# OPTIONS -Wall -O2 #-}
import Data.List.Split (chunksOf)
import Data.Ord (comparing)
import System.Environment
import qualified Data.Vector as V
import qualified Data.List as L
import Random.Xorshift (Xorshift, makeXorshift)
import Control.Monad.Random (Rand, evalRand, getRandom, next)
import Control.Concurrent (forkIO)
import Control.Concurrent.MVar
import Control.DeepSeq (NFData(..), deepseq)

type Pos = (Int,Int)

data Tile = Wall | Space deriving (Show)

instance NFData Tile

data Room = Room
    { roomX, roomY, roomW, roomH :: Int
    } deriving (Show)

instance NFData Room where
    rnf (Room rx ry rw rh) = rx `seq` ry `seq` rw `seq` rh `seq` ()

data Lev = Lev
    { lRooms :: V.Vector Room
    , lTiles :: [Tile]
    }

instance NFData Lev where
    rnf (Lev rooms tiles) = rooms `deepseq` tiles `deepseq` ()

levDim, minWid, maxWid :: Int
levDim = 50
minWid = 2
maxWid = 8

numLevs, numTries :: Int
numLevs = 10
numTries = 50000

getRandomPos :: Rand Xorshift Int
getRandomPos = do
  r <- getRandom
  let rPos = abs r
  rPos `seq` return rPos

genRoom :: Rand Xorshift Room
genRoom = do
    r1 <- getRandomPos
    r2 <- getRandomPos
    r3 <- getRandomPos
    r4 <- getRandomPos
    let x = rem r1 levDim
    let y = rem r2 levDim
    let w = rem r3 maxWid + minWid
    let h = rem r4 maxWid + minWid
    return Room {roomX = x, roomY = y, roomW = w, roomH = h}

genGoodRooms :: Int -> Int -> Rand Xorshift (V.Vector Room)
genGoodRooms = aux V.empty
    where aux accum 0 _ = return accum
          aux accum _ 0 = return accum
          aux accum count t = do
            room <- genRoom
            if goodRoom accum room
                then aux (V.cons room accum) (count-1) (t-1)
                else aux accum count (t-1)

goodRoom :: V.Vector Room -> Room -> Bool
goodRoom rooms room =
    not (checkBound room || checkColl room rooms)

checkBound :: Room -> Bool
checkBound (Room x y w h) =
    x<=0 || y<=0 || x+w >= levDim || y+h >= levDim

checkColl :: Room -> V.Vector Room -> Bool
checkColl room = V.any (roomHitRoom room)

roomHitRoom :: Room -> Room -> Bool
roomHitRoom (Room x y w h) (Room x2 y2 w2 h2)
    = not ((x2+w2+1) < x || x2 > (x+w+1)
        || (y2+h2+1) < y || y2 > (y+h+1))

inRoom :: Pos -> Room -> Bool
inRoom (x, y) (Room rx ry rw rh) =
        (rx <= x) && (x < rx + rw)
    &&  (ry <= y) && (y < ry + rh)

showTiles :: [Tile] -> String
showTiles = unlines . chunksOf levDim . map toChar
  where toChar Wall = '0'
        toChar Space = '1'

genLevel :: Rand Xorshift Lev
genLevel = do
    rooms <- genGoodRooms 100 numTries
    let tiles = map (toTile rooms) [1 .. levDim*levDim]
    return $ Lev{lRooms = rooms, lTiles = tiles}
  where
    toTile rooms n = if (V.any (toPos n `inRoom`) rooms) then Space else Wall
    toPos n = let (y, x) = quotRem n levDim in (x, y)

genLevelMVar :: Int -> IO (MVar Lev)
genLevelMVar seed =
    let gen = makeXorshift seed in
    do levelVar <- newEmptyMVar
       _ <- forkIO (let level = evalRand genLevel gen in level `deepseq` putMVar levelVar level)
       return levelVar

genLevels :: [Int] -> IO [MVar Lev]
genLevels = mapM genLevelMVar

biggestLev :: [Lev] -> Lev
biggestLev = L.maximumBy (comparing (V.length . lRooms))

main :: IO ()
main = do
    (v:_) <- fmap (++ ["18"]) $ getArgs
    putStr "The random seed is: "
    putStrLn v
    let levelCount = numLevs
    let gen = makeXorshift (read v :: Integer)
    let (rand,_) = next gen
    levels <- mapM readMVar =<< genLevels [rand .. rand+levelCount]
    putStr $ showTiles $ lTiles $ biggestLev levels
