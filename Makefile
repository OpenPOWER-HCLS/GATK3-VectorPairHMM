#Copyright (c) 2012 The Broad Institute

#Permission is hereby granted, free of charge, to any person
#obtaining a copy of this software and associated documentation
#files (the "Software"), to deal in the Software without
#restriction, including without limitation the rights to use,
#copy, modify, merge, publish, distribute, sublicense, and/or sell
#copies of the Software, and to permit persons to whom the
#Software is furnished to do so, subject to the following
#conditions:

#The above copyright notice and this permission notice shall be
#included in all copies or substantial portions of the Software.

#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
#EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
#OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
#NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
#HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
#WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
#FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR
#THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#

arch=$(shell uname -m)
ifeq ($(arch),ppc64le)
USE_GCC=1
DISABLE_FTZ=1
endif

#OMPCFLAGS=-fopenmp
#OMPLFLAGS=-fopenmp #-openmp-link static

#CFLAGS=-O2 -std=c++11 -W -Wall -march=corei7-avx -Wa,-q            -pedantic $(OMPCFLAGS) -Wno-unknown-pragmas
#CFLAGS=-O2             -W -Wall -march=corei7 -mfpmath=sse -msse4.2 -pedantic $(OMPCFLAGS) -Wno-unknown-pragmas

JRE_HOME?=/usr/lib/jvm/default-java/jre
JNI_COMPILATION_FLAGS=-D_REENTRANT -fPIC -I${JRE_HOME}/../include -I${JRE_HOME}/../include/linux

#COMMON_COMPILATION_FLAGS=$(JNI_COMPILATION_FLAGS) -O3 -W -Wall -pedantic $(OMPCFLAGS) -Wno-unknown-pragmas
COMMON_COMPILATION_FLAGS=$(JNI_COMPILATION_FLAGS) -g -O3 -Wall $(OMPCFLAGS) -Wno-unknown-pragmas -Wno-write-strings -Wno-unused-variable -Wno-unused-but-set-variable
ifdef DISABLE_FTZ
  COMMON_COMPILATION_FLAGS+=-DDISABLE_FTZ
endif

ifdef USE_GCC
  C_COMPILER?=gcc
  CPP_COMPILER?=g++
ifeq ($(arch),ppc64le)
ifeq ($(wildcard /opt/at10.0),)
ifeq ($(wildcard /opt/at9.0),)
else
  C_COMPILER=/opt/at9.0/bin/gcc
  CPP_COMPILER=/opt/at9.0/bin/g++
endif
else
  C_COMPILER=/opt/at10.0/bin/gcc
  CPP_COMPILER=/opt/at10.0/bin/g++
endif
  COMMON_COMPILATION_FLAGS+=-mcpu=power8 -mtune=power8 -fopenmp
  OMPLDFLAGS=-lgomp
  AVX_FLAGS=
  SSE41_FLAGS=
else
  AVX_FLAGS=-mavx
  SSE41_FLAGS=-msse4.1
endif
  COMMON_COMPILATION_FLAGS+=-Wno-char-subscripts
else
  C_COMPILER?=icc
  CPP_COMPILER?=icc
  AVX_FLAGS=-xAVX
  SSE41_FLAGS=-xSSE4.1
  LIBFLAGS=-static-intel
  ifdef DISABLE_FTZ
    COMMON_COMPILATION_FLAGS+=-no-ftz
  endif
endif

LDFLAGS=-lm -lrt -lgcc_s -lgcc $(OMPLDFLAGS)

PAPI_DIR=/home/karthikg/softwares/papi-5.3.0
ifdef USE_PAPI
  ifeq ($(USE_PAPI),1)
    COMMON_COMPILATION_FLAGS+=-I$(PAPI_DIR)/include -DUSE_PAPI
    LDFLAGS+=-L$(PAPI_DIR)/lib -lpapi
  endif
endif

BIN=libVectorLoglessPairHMM.so
#BIN=libVectorLoglessPairHMM.so pairhmm-template-main checker

DEPDIR=.deps
DF=$(DEPDIR)/$(*).d

#Common across libJNI and sandbox
ifeq ($(arch),ppc64le)
COMMON_SOURCES=utils.cc baseline.cc sse_function_instantiations.cc LoadTimeInitializer.cc
else
COMMON_SOURCES=utils.cc avx_function_instantiations.cc baseline.cc sse_function_instantiations.cc LoadTimeInitializer.cc
endif
#Part of libJNI
LIBSOURCES=org_broadinstitute_gatk_utils_pairhmm_VectorLoglessPairHMM.cc org_broadinstitute_gatk_utils_pairhmm_DebugJNILoglessPairHMM.cc $(COMMON_SOURCES)
#LIBSOURCES=org_broadinstitute_gatk_utils_pairhmm_VectorLoglessPairHMM.cc org_broadinstitute_gatk_utils_pairhmm_DebugJNILoglessPairHMM.cc Sandbox.cc $(COMMON_SOURCES)
SOURCES=$(LIBSOURCES) pairhmm-template-main.cc pairhmm-1-base.cc
LIBOBJECTS=$(LIBSOURCES:.cc=.o)
COMMON_OBJECTS=$(COMMON_SOURCES:.cc=.o)


#No vectorization for these files
NO_VECTOR_SOURCES=org_broadinstitute_gatk_utils_pairhmm_VectorLoglessPairHMM.cc org_broadinstitute_gatk_utils_pairhmm_DebugJNILoglessPairHMM.cc pairhmm-template-main.cc pairhmm-1-base.cc utils.cc baseline.cc LoadTimeInitializer.cc Sandbox.cc
#Use -xAVX for these files
AVX_SOURCES=avx_function_instantiations.cc
#Use -xSSE4.2 for these files
SSE_SOURCES=sse_function_instantiations.cc

NO_VECTOR_OBJECTS=$(NO_VECTOR_SOURCES:.cc=.o)
AVX_OBJECTS=$(AVX_SOURCES:.cc=.o)
SSE_OBJECTS=$(SSE_SOURCES:.cc=.o)
$(NO_VECTOR_OBJECTS): CXXFLAGS=$(COMMON_COMPILATION_FLAGS)
$(AVX_OBJECTS): CXXFLAGS=$(COMMON_COMPILATION_FLAGS) $(AVX_FLAGS)
$(SSE_OBJECTS): CXXFLAGS=$(COMMON_COMPILATION_FLAGS) $(SSE41_FLAGS)
ifeq ($(arch),ppc64le)
OBJECTS=$(NO_VECTOR_OBJECTS) $(SSE_OBJECTS)
else
OBJECTS=$(NO_VECTOR_OBJECTS) $(AVX_OBJECTS) $(SSE_OBJECTS)
endif

all: $(BIN)
#all: $(BIN) Sandbox.class copied_lib

-include $(addprefix $(DEPDIR)/,$(SOURCES:.cc=.d))

checker: pairhmm-1-base.o $(COMMON_OBJECTS)
	$(CPP_COMPILER) $(OMPLFLAGS) -o $@ $^ $(LDFLAGS)

pairhmm-template-main:	pairhmm-template-main.o $(COMMON_OBJECTS)
	$(CPP_COMPILER) $(OMPLFLAGS) -o $@ $^ $(LDFLAGS)

libVectorLoglessPairHMM.so: $(LIBOBJECTS) 
	$(CPP_COMPILER) $(OMPLFLAGS) -shared $(LIBFLAGS) -o $@ $(LIBOBJECTS) ${LDFLAGS}


$(OBJECTS): %.o: %.cc
	@mkdir -p $(DEPDIR)
	$(CPP_COMPILER) -c -MMD -MF $(DF) $(CXXFLAGS) $(OUTPUT_OPTION) $<

Sandbox.class: Sandbox.java
	javac Sandbox.java

copied_lib: libVectorLoglessPairHMM.so
ifdef OUTPUT_DIR
	mkdir -p $(OUTPUT_DIR)
ifeq ($(arch),ppc64le)
	rsync -a libVectorLoglessPairHMM.so $(OUTPUT_DIR)/libVectorLoglessPairHMM_ppc64le.so
else
	rsync -a libVectorLoglessPairHMM.so $(OUTPUT_DIR)/
endif
endif

clean:
	rm -rf $(BIN) *.o $(DEPDIR) *.class
