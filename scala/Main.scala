object Main {
  val timesToRunBench = 20
  val warmupTime = 4000l


  def main(args: Array[String]) {
    val v = args(0).toInt
    println(s"The random seed is: $v")

    val startTime = System.currentTimeMillis()

    val rnd = Xorshift32(v)

    var i = 0; var times = 0l; var maxTime = (0l, 0)
    while((System.currentTimeMillis() - startTime) < warmupTime) {
      val res = Bench.bench(rnd.nextInt, false)
      if(res > maxTime._1) {
        maxTime = (res,i+1)
      }
      times += res
      i += 1
    }

    def prettyRanking(num: Int) = num.toString.last match {
      case '1' => num.toString + "st"
      case '2' => num.toString + "nd"
      case '3' => num.toString + "rd"
      case _ => num.toString + "th"
    }

    println(s"Average time from warm run: ${((0 until timesToRunBench) map (_ => Bench.bench(rnd.nextInt,false)) reduceLeft (_+_)) / timesToRunBench.toDouble} ms")
    println(s"Average time from cold run: ${times/i.toDouble} ms")
    println(s"Worst-case bench time: ${maxTime._1} ms. Recorded from the ${prettyRanking(maxTime._2)} run of the bench.")

  }
}
