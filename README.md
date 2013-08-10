Levgen-Parallel-Benchmarks
==========================

Simple parallel Roguelike level generation benchmark of Rust, C, D, Go and more. 

Rust is compiled with --opt-level=3

C is compiled with -O3 -lpthread

D is compiled with -O -release -inline -noboundscheck

They must be run with the seed as a command line parameter, like ./PC 123. PGo uses the seed in the form "PGo -v=seed", rather than just "PGo seed".
