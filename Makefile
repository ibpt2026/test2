CC ?= cc
CFLAGS ?= -O2 -Wall
all: app
util.o: src/util.c src/util.h
	$(CC) $(CFLAGS) -c src/util.c -o util.o
main.o: src/main.c src/util.h
	$(CC) $(CFLAGS) -c src/main.c -o main.o
app: util.o main.o
	$(CC) $(CFLAGS) util.o main.o -o app
clean:
	rm -f *.o app
