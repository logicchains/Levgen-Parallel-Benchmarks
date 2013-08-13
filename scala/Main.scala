import scala.concurrent._
import ExecutionContext.Implicits.global
import scala.concurrent.duration.Duration

case class Room(X: Int, Y: Int, W: Int, H: Int)

case class Lev(rs: Array[Room], ts: Array[Boolean], ln: Int)

case class Xorshift32(var seed: Int) {
  final def nextInt = {
    seed ^= seed << 13
    seed ^= seed >>> 17
    seed ^= seed << 5
    seed
  }
}

object Main {
  val TileDim = 50
  val MinWid = 2
  val MaxWid = 8
  val NumLevels = 800
  val NumTries = 50000
  val Threadiness = 6.5 //how many threads to spawn per processor. Can be a double or float.


  def main(args: Array[String]) {
    println(time {

      val numThreads = (Runtime.getRuntime.availableProcessors()*Threadiness).toInt

      val v = args(0).toInt
      println(s"The random seed is: $v")
      val rand = Xorshift32(v)

      val normNumLevels = NumLevels / numThreads
      val remNumLevels = normNumLevels + (NumLevels % numThreads)

      val levelsPerThread = (remNumLevels -> (numThreads - 1)) +: ((0 until numThreads - 1) map (threadNum => normNumLevels -> threadNum)) map {
        case (numLvls, threadNum) => {val rnd = new Xorshift32(rand.nextInt); println(s"Thread number $threadNum has seed " +  rnd.seed); numLvls -> rnd}
      }

      val futureLevels = levelsPerThread map { case (levs, r) => future{
        implicit val rnd = r
        (0 until levs) map {_ =>
          val (rs, ln) = roomsRedux(new Array[Room](75), NumTries, 0)
          val ts = new Array[Boolean](2500)
          for(i <- 0 until ln) room2Tiles(rs(i), ts)
          Lev(rs,ts,ln)
      }}}

      def max(l1: Lev, l2: Lev) = if(l1.ln > l2.ln) l1 else l2

      def reducer(f1: Future[Lev], f2: Future[Lev]) = for(l1 <- f1; l2 <- f2) yield max(l1,l2)

      val futureLevel: Future[Lev] = futureLevels map (j => j map (i => i reduceLeft max)) reduceLeft reducer

      val level = Await.result(futureLevel, Duration.Inf)
      printLev(level)
    })
  }

  final def roomsRedux(start: Array[Room], tries: Int, ln: Int)(implicit rnd: Xorshift32): (Array[Room], Int) = {
    if(tries > 0) {
      val x = makeRoom(start, ln)
      start(ln) = x
      if(x != null)
        roomsRedux(start, tries - 1, ln + 1)
      else {
        roomsRedux(start, tries - 1, ln)
      }
    } else (start, ln)
  }

  def time(fn: => Unit) = {
    val start = System.currentTimeMillis()
    fn
    System.currentTimeMillis() - start
  }

  final def myAbs(n: Int) = {
    val mask = n >> 31
    (mask ^ n) - mask
  }

  final def makeRoom(rooms: Array[Room], ln: Int)(implicit rnd: Xorshift32) = {
    val w = (myAbs(rnd.nextInt)%MaxWid)+MinWid
    val h = (myAbs(rnd.nextInt)%MaxWid)+MinWid
    val x = myAbs(rnd.nextInt)%TileDim
    val y = myAbs(rnd.nextInt)%TileDim
    if(!(x+w>=TileDim || y+h>=TileDim || (x & y) == 0) && !checkColl(x,y,w,h,rooms,ln)) {
      Room(x,y,w,h)
    }
    else
      null
  }

  final def checkColl(x: Int,y: Int,w: Int,h: Int, rs: Array[Room], ln: Int): Boolean = {
    var i = 0
    while(i < ln)
    {
      val oRoom = rs(i)
      if(!(oRoom.X + oRoom.W + 1 < x || oRoom.X > x+w+1) && !(oRoom.Y + oRoom.H + 1 < y || oRoom.Y > y+h+1)) return true
      i += 1
    }
    return false
  }

  def room2Tiles(r: Room, ts: Array[Boolean]) = {
    for (xi <- r.X until r.X+r.W+1; yi <- r.Y until r.Y+r.H+1) {
      val num = yi*TileDim+xi
      ts(num)=true
    }
  }

  def printLev(lev: Lev){
    val x = new StringBuffer
    for (i <- 0 until 2500) {
      x.append(if(lev.ts(i)) '1' else '0')
      if(i % TileDim == 49 && i != 0) x.append('\n')
    }
    print(x.toString)
  }
}
