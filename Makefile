KEA_MSG_COMPILER ?= kea-msg-compiler
KEA_INCLUDE ?= /usr/local/include/kea
KEA_LIB ?= /usr/local/lib

OBJECTS = src/messages.o src/log.o src/callouts.o src/version.o src/multi_threading_compatible.o
DEPS = $(OBJECTS:.o=.d)
CXXFLAGS = -I $(KEA_INCLUDE) -fPIC -Wall -Wno-deprecated -std=c++17
LDFLAGS = -L $(KEA_LIB) -shared
LDLIBS = -lkea-dhcpsrv -lkea-dhcp -lkea-hooks -lkea-log -lkea-util -lkea-exceptions

kea-hook-grape.so: $(OBJECTS)
	$(CXX) -o $@ $(CXXFLAGS) $(LDFLAGS) $(OBJECTS) $(LDLIBS)

%.o: %.cc
	$(CXX) -MMD -MP -c $(CXXFLAGS) -o $@ $<

%.o: %.cpp
	$(CXX) -MMD -MP -c $(CXXFLAGS) -o $@ $<

# src/messages.h and src/messages.cc are committed, so the build doesn't need
# kea-msg-compiler. Regenerate them after editing src/messages.mes.
messages: src/messages.mes
	$(KEA_MSG_COMPILER) -d src/ $<

clean:
	rm -f kea-hook-grape.so src/*.o src/*.d

.PHONY: messages clean

-include $(DEPS)
