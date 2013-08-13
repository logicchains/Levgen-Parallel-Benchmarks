Levgen-Parallel-Benchmarks
==========================

Simple parallel Roguelike level generation benchmark of Rust, C, D, Go and more. Speed will be measured and compared both between implementations and between them and their non-parallel equivalents, as will standard lines of code (sloc as defined by Github).

Rust is compiled with --opt-level=3

C is compiled with -O3 -lpthread

D is compiled with -O -release -inline -noboundscheck

Nimrod is compiled with -d:release

Scala is run with sbt "run seed"

They must be run with the seed as a command line parameter, like ./PC 123. PGo uses the seed in the form "PGo -v=seed", rather than just "PGo seed".
