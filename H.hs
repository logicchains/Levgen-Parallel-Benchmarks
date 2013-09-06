import Data.List.Split (chunksOf)
import Data.Ord (comparing)
import System.Environment
import qualified Data.Vector as V
import qualified Data.List as L
import Random.Xorshift
import Control.Monad
import Control.Monad.Random
import Control.Concurrent
import Control.Concurrent.MVar
import Control.DeepSeq

type Pos = (Int,Int)

data Tile = Wall | Space deriving (Show)

instance NFData Tile

data Room = Room
    { rx, ry, rw, rh :: Int
    } deriving (Show)

instance NFData Room where
    rnf (Room rx ry rw rh) = rx `seq` ry `seq` rw `seq` rh `seq` ()

data Lev = Lev
    { lRooms :: V.Vector Room
    , lTiles :: [Tile]
    }

instance NFData Lev where
    rnf (Lev lRooms lTiles) = lRooms `deepseq` lTiles `deepseq` ()

levDim, minWid, maxWid :: Int
levDim = 50
minWid = 2
maxWid = 8

numLevs = 1000

genRoom :: Rand Xorshift Room
genRoom = do
    r1 <- getRandom
    r2 <- getRandom
    r3 <- getRandom
    r4 <- getRandom
    let x = rem r1 levDim
    let y = rem r2 levDim
    let w = rem r3 maxWid + minWid
    let h = rem r4 maxWid + minWid
    return Room {rx = x, ry = y, rw = w, rh = h}

genGoodRooms :: Int -> Rand Xorshift (V.Vector Room)
genGoodRooms n = aux n V.empty
    where aux 0 accum = return accum
          aux count accum = do
            room <- genRoom
            if goodRoom accum room
                then aux (count-1) (V.cons room accum)
                else aux count accum

goodRoom :: V.Vector Room -> Room -> Bool
goodRoom rooms room =
    let good = not (checkBound room || checkColl room rooms) in
    good

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
    rooms <- genGoodRooms 100
    let tiles = map (toTile rooms) [1 .. levDim ^ 2]
    return $ Lev{lRooms = rooms, lTiles = tiles}
  where
    toTile rooms n = if (V.any (toPos n `inRoom`) rooms) then Space else Wall
    toPos n = let (y, x) = quotRem n levDim in (x, y)

genLevelMVar :: Int -> IO (MVar Lev)
genLevelMVar seed =
    let gen = makeXorshift seed in
    do levelVar <- newEmptyMVar
       forkIO (let level = evalRand genLevel gen in level `deepseq` putMVar levelVar level)
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
    let gen = makeXorshift (read v)
    let (rand,_) = next gen
    levels <- genLevels [rand .. rand+levelCount]
    levels <- mapM readMVar levels
    putStr $ showTiles $ lTiles $ biggestLev levels
