W32CROSS=i686-w64-mingw32-
CFLAGS=-Os
STRIP=strip

#CFLAGS=-g
#STRIP=size

SRC = ..

SOURCES = urlader.c urlib.h urlib.c liblzf/lzfP.h liblzf/lzf_d.c
SRCSOURCES = $(addprefix $(SRC)/,$(SOURCES))
BINARIES = windows-x86 linux-x86 linux-amd64 darwin-x86

all: $(BINARIES)

clean:
	rm -f $(BINARIES)

windows-x86: $(SRCSOURCES) $(SRC)/urlader.ico
	echo 'MAINICON ICON "$(SRC)/urlader.ico"' >icon.rc
	$(W32CROSS)windres icon.rc icon.o
	rm icon.rc
	$(W32CROSS)gcc $(CFLAGS) -mwin32 -mwindows -o $@ $< icon.o -lshell32 -lshlwapi
	rm icon.o
	$(W32CROSS)$(STRIP) $@

linux-x86: $(SRCSOURCES)
	broot gcc $(CFLAGS) -o $@ $< -static
	broot $(STRIP) $@

linux-amd64: linux-x86
	ln -f $< $@

darwin-x86: $(SRCSOURCES)
	tar cC $(SRC) $(SOURCES) | ssh osx105 "\
           cd /tmp || exit;\
           tar x || exit;\
           gcc $(CFLAGS) -o $@ urlader.c || exit;\
           $(STRIP) $@ >/dev/null || exit;\
           tar c $@ || exit;\
        " | tar xv

dist: all
	rsync -avP --chmod u=rwX,go=rX $(BINARIES) rijk:/var/www/urlader.schmorp.de/prebuilt/1.0/.
