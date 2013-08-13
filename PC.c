#include <stdlib.h> 
#include <stdio.h> 
#include <string.h> 
#include <time.h>
#include <stdint.h>
#include <pthread.h>

const int TileDim=50;
const int Miw=2;
const int MaxWid=8;

#define NUM_LEVS 800
#define NUM_THREADS 4
const int NumThreads=NUM_THREADS;
const int NumLevs=NUM_LEVS;



struct Tile {
  int X;
	int Y;
	int T;
};

struct Room {
	int X;
	int Y;
	int W;
	int H;
	int N;
};

struct Lev{
	struct Tile ts[2500];
	struct Room rs[100];
	int lenrs;
};

int GenRand(uint32_t *gen) { 
	*gen += *gen;
        *gen ^= 1;
	int32_t tgen=*gen;
        if ( tgen < 0) {
              *gen ^= 0x88888eef;
         }
	int a = *gen;
	return a;
}



int CheckColl(int x,int y,int w,int h, struct Room rs[100], int lenrs){
	int i=0;
	for(i=0;i<lenrs;i++){
		int rx = rs[i].X;
		int ry = rs[i].Y;
		int rw = rs[i].W;
		int rh = rs[i].H;
		int RoomOkay;
		if ( (rx + rw +1 ) < x || rx > (x+w +1) )  { RoomOkay=1;} 
		else if ( (ry + rh +1 ) < y || ry > (y+h +1) )   {RoomOkay=1;}
		else {RoomOkay=0;}
		if(RoomOkay==0) return 1;
		}
	return 0;
}

void MakeRoom(struct Room rs[100], int *lenrs,uint32_t *gen){
	int x = GenRand(gen) % TileDim;
	int y = GenRand(gen) % TileDim;
	int w = GenRand(gen) % MaxWid+Miw;
	int h = GenRand(gen) % MaxWid+Miw;

	if(x+w>=TileDim || y+h>=TileDim || x==0 || y==0) return;
	int nocrash = CheckColl(x,y,w,h,rs,*lenrs);
	if (nocrash==0){
		struct Room r;
		r.X = x;
		r.Y = y;
		r.W = w;
		r.H = h;
		r.N = *lenrs;
		rs[*lenrs]=r;
		*lenrs = *lenrs+1;
	}
} 

void Room2Tiles(struct Room *r, struct Tile ts[2500]){			
	int x=r->X;
	int y=r->Y;
	int w=r->W;
	int h=r->H;
	int xi;
	int yi;
	for(xi=x;xi<=x+w;xi++){
		for(yi=y;yi<=y+h;yi++){
			int num = yi*TileDim+xi;
			ts[num].T=1;	
		}
	}
} 

void PrintLev(struct Lev *l){
	int i =0;
	for(i=0;i<2500;i++){
		printf("%d", l->ts[i].T);
		if(i%(TileDim)==49 && i!=0)printf("\n");	
	}
}

struct Lev ls[NUM_LEVS];
uint32_t gens[NUM_THREADS];

void *MakeLevs(void *ThreadNum){
	int *NumPointer = (int *)ThreadNum;
	int LoopStart = *NumPointer * (NumLevs/NumThreads);
	int i = 0;
	uint32_t *Pgen= &gens[*NumPointer];
	//printf("The seed of thread %d is:%d \n",*NumPointer,*Pgen);
	for (i=LoopStart; i<LoopStart+NumLevs/NumThreads; i++) {
		struct Room rs[100];
		int lenrs=0;
		int *Plenrs = &lenrs;
		int ii;
		for (ii=0;ii<50000;ii++){
			MakeRoom(rs,Plenrs,Pgen);
			if(lenrs==99){ 
				break;
			}
		}
		struct Tile ts[2500];
		for (ii=0;ii<2500;ii++){
			ts[ii].X=ii%TileDim;
			ts[ii].Y=ii/TileDim;
			ts[ii].T=0;
		}
		for (ii=0;ii<lenrs;ii++){
			Room2Tiles(&(rs[ii]),ts);
		}
		struct Lev l;
		memcpy(l.rs,rs,sizeof(rs));
		memcpy(l.ts,ts,sizeof(ts));
		l.lenrs=lenrs;
		ls[i]=l;
		//lenLS++;				
	}
}

int main(int argc, char* argv[]) {
	clock_t start, stop;
	start = clock();
	int v = atoi(argv[1]);
	printf("The random seed is: %d \n", v);
	srand(v);
	uint32_t gen = v;
	pthread_t threads[NumThreads];
	int i;
	for (i=0;i<NumThreads;i++){
		pthread_t thread;
		threads[i] = thread;
		gens[i] = gen * (i+1)*(i+1);
		printf("The seed of thread %d is:%d \n",i+1,gens[i]);
	}
	int constints[NumThreads];
	for (i=0;i<NumThreads;i++){
		constints[i]=i;
	}
	for (i=0;i<NumThreads;i++){
		if(pthread_create(&threads[i], NULL, MakeLevs, &constints[i])) {
			fprintf(stderr, "Error creating thread\n");
			return 1;
		}
	}
	for (i=0;i<NumThreads;i++){
		if(pthread_join(threads[i], NULL)) {
			fprintf(stderr, "Error joining thread\n");
			return 2;
		}
	}
	struct Lev templ;
	templ.lenrs=0;
	for(i=0;i<NumLevs;i++){
		if(ls[i].lenrs>templ.lenrs) templ=ls[i];
	}
	PrintLev(&templ);
	stop = clock();
	long clocks_per_ms = (CLOCKS_PER_SEC/1000.0);
        printf("%ld\n", (stop - start)/clocks_per_ms/NUM_THREADS);

    return 0;
}
