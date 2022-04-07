# Acknowledgement: Functionality for creating make rules of dependencies is
# based on code presented here <http://codereview.stackexchange.com/q/11109>
CC = /usr/local/cuda-10.2/bin/nvcc  # To specify compiler use: '$ CC=clang make clean all'
ARCH=-gencode arch=compute_75,code=sm_75 \
          -gencode arch=compute_75,code=compute_75

CFLAGS = -O0 -g $(ARCH)
CUFLAGS= -G $(ARCH) -rdc=true
LDFLAGS = $(ARCH)

# Use the compiler to generate make rules. See gcc manual for details.
#MFLAGS = -MMD -MP -MF

SOURCES = $(wildcard *.c)
SOURCES_cuda = $(wildcard *.cu)
OBJECTS = $(SOURCES:.c=.o)
OBJECTS_cuda = $(SOURCES_cuda:.cu=.o)
DEPENDENCIES = $(addprefix .,$(SOURCES:.c=.d))  # Add dot prefix to hide files.

.PHONY: clean  all

all: c63enc c63dec c63pred
%.o: %.cu
	$(CC) $(CFLAGS) $(CUFLAGS) -c $< 

c63enc: c63enc.o dsp.o tables.o io.o c63_write.o common.o me.o
	$(CC) $^ $(CFLAGS) $(LDFLAGS) -o $@
#c63dec: c63dec.c dsp.o tables.o io.o common.o me.o
#	$(CC) $^ $(CFLAGS) $(LDFLAGS) -o $@
#c63pred: c63dec.c dsp.o tables.o io.o common.o me.o
#	$(CC) $^ -DC63_PRED $(CFLAGS) $(LDFLAGS) -o $@


clean:
	$(RM) c63enc c63dec c63pred $(OBJECTS) $(OBJECTS_cuda) $(DEPENDENCIES)

-include $(DEPENDENCIES)

profile-cuda-10:
	/usr/local/cuda-10.2/bin/nvprof ./c63enc -h 288 -w 352 -o /tmp/test.c63 -f 10 foreman.yuv
profile-cuda:
	/usr/local/cuda-10.2/bin/nvprof ./c63enc -h 288 -w 352 -o /tmp/test.c63 foreman.yuv
profile-gprof:
	gcc -O2 -g -pg ./c63enc -h 288 -w 352 -o /tmp/test.c63 foreman.yuv
foreman:
	./c63enc -h 288 -w 352 -o /tmp/test.c63 foreman.yuv
