=head1 NAME

Urlader - installer-less single-file independent executables

=head1 SYNOPSIS

 use Urlader;

=head1 DESCRIPTION

Urlader (that's german for "bootloader" btw.) was created out of
frustration over PAR always being horribly slow, again not working, again
not being flexible enough for simple things such as software upgrades, and
again causing mysterious missing file issues on various platforms.

That doesn't mean this module replaces PAR, in fact, you should stay with
PAR for many reasons right now, user-friendlyness is one of them.

However, if you want to make single-file distributions out of your perl
programs (or python, or C or whatever), and you are prepared to fiddle
a LOT, this module might provide a faster and more versatile deployment
technique then PAR. Well, if it ever gets finished.

Also, I<nothing in this module is considered very stable yet>, and it's
far from feature-complete.

Having said all that, Urlader basically provides three services:

=over 4

=item A simple archiver that packs a directory tree into a single file.

=item A small C program that works on windows and unix, which unpacks an attached
archive and runs a program (perl, python, whatever...).

=item A perl module support module (I<this one>), that can be used to query
the runtime environment, find out where to install updates and so on.

=back

=head1 EXAMPLE

How can it be used to provide single-file executables?

So simple, create a directory with everything that's needed, e.g.:

   # find bintree
   bintree/perl
   bintree/libperl.so.5.10
   bintree/run
   bintree/pm/Guard.pm
   bintree/pm/auto/Guard/Guard.so
   bintree/pm/XSLoader.pm
   bintree/pm/DynaLoader.pm
   bintree/pm/Config.pm
   bintree/pm/strict.pm
   bintree/pm/vars.pm
   bintree/pm/warnings.pm

   # cat bintree/run
   @INC = ("pm", "."); # "." works around buggy AutoLoader
   use Guard;
   guard { warn "hello, world!\n" }; # just to show off
   exit 0; # tell the urlader that everything was fine

Then pack it:

   # wget http://urlader.schmorp.de/prebuilt/1.0/linux-x86
   # urlader-util --urlader linux-x86 --pack myprog ver1_000 bintree \
                  LD_LIBRARY_PATH=. ./perl run \
                  >myprog
   # chmod 755 myprog

The packing step takes a binary loader and appends all the files in the
directory tree, plus some meta information.

The resulting file is an executable that, when run, will unpack all the
files and run the embedded program.

=head1 CONCEPTS

=over 4

=item urlader

A small (hopefully) and relatively portable (hopefully) binary that is
prepended to a pack file to make it executable.

You can build it yourself from sources (see F<prebuilt/Makefile> in the
distribution) or use one of the precompiled ones at:

   http://urlader.schmorp.de/prebuilt/1.0/

The F<README> there has further information on the binaries provided.

=item exe_id

A string that uniquely identifies your program - all branches of it. It
must consist of the characters C<A-Za-z0-9_-> only and should be a valid
directory name on all systems you want to deploy on.

=item exe_ver

A string the uniquely identifies the contents of the archive, i.e. the
version.  It has the same restrictions as the C<exe_id>, and should be
fixed-length, as Urlader assumes lexicographically higher versions are
newer, and thus preferable.

=item pack file (archive)

This contains the C<exe_id>, the C<exe_ver>, a number of environment
variable assignments, the program name to execute, the initial arguments
it receives, and finally, a list of files (with contents :) and
directories.

=item override

When the urlader starts, it first finds out what C<exe_id> is
embedded in it. It then looks for an override file for this id
(F<$URLADER_EXE_DIR/override>) and verifies that it is for the same
C<exe_id>, and the version is newer. If this is the case, then it will
unpack and run the override file instead of unpacking the files attched to
itself.

This way one can implement software upgrades - download a new executable,
write it safely to disk and move it to the override path.

=back

=head1 ENVIRONMENT VARIABLES

The urlader sets and maintains the following environment variables, in
addition to any variables specified on the commandline. The values in
parentheses are typical (but not gauranteed) values for unix - on windows,
F<~/.urlader> is replaced by F<%AppData%/urlader>.

=over 4

=item URLADER_VERSION (C<1.0>)

Set to the version of the urlader binary itself. All versions with the
same major number should be compatible to older versions with the same
major number.

=item URLADER_DATADIR (F<~/.urlader>)

The data directory used to store whatever urlader needs to store.

=item URLADER_CURRDIR

This is set to the full path of the current working directory where
the urlader was started. Atfer unpacking, the urlader changes to the
C<URLADER_EXECDIR>, so any relative paths should be resolved via this
path.

=item URLADER_EXEPATH

This is set to the path of the urlader executable itself, usually relative
to F<$URLADER_CURRDIR>.

=item URLADER_EXE_ID

This stores the executable id of the pack file attached to the urlader.

=item URLADER_EXE_VER

This is the executable version of the pack file attached to the urlader,
or the override, whichever was newer. Or in other words, this is the
version of the application running at the moment.

=item URLADER_EXE_DIR (F<~/.urlader/$URLADER_EXE_ID>>

The directory where urlader stores files related to the executable with
the given id.

=item URLADER_EXECDIR (F<~/.urlader/$URLADER_EXE_ID/i-$URLADER_EXE_VER>)

The directory where the files from the pack file are unpacked and the
program is being run. Also the working directory of the program when it is
run.

=item URLADER_OVERRIDE (empty or F<override>)

The override file used, if any, relative to F<$URLADER_EXECDIR>. This is
either missing, when no override was used, or the string F<override>, as
thta is currently the only override file urlader is looking for.

=back

=head1 FUNCTIONS AND VARIABLES IN THIS MODULE

=over 4

=cut

package Urlader;

use common::sense;

BEGIN {
   our $VERSION = '1.01';

   use XSLoader;
   XSLoader::load __PACKAGE__, $VERSION;
}

=item $Urlader::URLADER_VERSION

Set to the urlader version (C<URLADER_VERSION>) when the program is
running form within urlader, undef otherwise.

=item $Urlader::DATADIR, $Urlader::EXE_ID, $Urlader::EXE_VER, $Urlader::EXE_DIR, $Urlader::EXECDIR

Contain the same value as the environment variable of the (almost) same
name. You should prefer these, though, as these might even be set to
correct values when not running form within an urlader environment.

=cut

our $URLADER_VERSION; # only set when running under urlader
our $DATADIR;
our $EXE_ID;
our $EXE_VER;
our $EXE_DIR; # %AppData%/urlader/EXE_ID
our $EXECDIR; # %AppData%/urlader/EXE_ID/i-EXE_VER

sub _get_env {
   $URLADER_VERSION = getenv "URLADER_VERSION";
   $DATADIR         = getenv "URLADER_DATADIR";
   $EXE_ID          = getenv "URLADER_EXE_ID";
   $EXE_VER         = getenv "URLADER_EXE_VER";
   $EXE_DIR         = getenv "URLADER_EXE_DIR"; # %AppData%/urlader/EXE_ID
   $EXECDIR         = getenv "URLADER_EXECDIR"; # %AppData%/urlader/EXE_ID/i-EXE_VER
}

_get_env;

=item Urlader::set_exe_info $exe_id, $exe_ver

Sets up the paths and variables as if running the given executable and
version from within urlader.

=cut

sub set_exe_info($$) {
   _set_datadir unless defined getenv "URLADER_DATADIR";
   &_set_exe_info;
   _get_env;
}

=item $lock = Urlader::lock $path, $exclusive, $wait

Tries to acquire a lock on the given path (which must specify a file which
will be created if necessary). If C<$exclusive> is true, then it tries to
acquire an exclusive lock, otherwise the lock will be shared. If C<$wait>
is true, then it will wait until the lock can be acquired, otherwise it
only attempts to acquire it and returns immediately if it can't.

If successful it returns a lock object - the lock will be given up when
the lock object is destroyed or when the process exits (even on a crash)
and has a good chance of working on network drives as well.

If the lock could not be acquired, C<undef> is returned.

This function is provided to assist applications that want to clean up old
versions, see "TIPS AND TRICKS", below.

=cut

1;

=back

=head1 TIPS AND TRICKS

=over 4

=item Gathering files

Gathering all the files needed for distribution can be a big
problem. Right now, Urlader does not assist you in this task in any way,
however, just like perl source stripping, it is planned to unbundle the
relevant technology from B<staticperl> (L<http://staticperl.plan9.de>) for
use with this module.

You could always use par to find all library files, unpack the bundle and
add F<perl>, F<libperl> and other support libraries (e.g. F<libgcc_s>).

=item Software update

Updating the software can be done by downloading a new packfile (with the
same C<exe_id> but a higher C<exe_ver> - this can simply be the executable
you create when making a release) and replacing the F<override> file in
the F<$URLADER_EXE_DIR>.

When looking for updates, you should include C<$URLADER_VERSION>,
C<$URLADER_EXE_ID> and C<$URLADER_EXE_VER> - the first two must be
identical for update and currently running program, while the last one
should be lexicographically higher.

Replacing the override file can be done like this:

   rename "new-override.tmp", "$Urlader::EXE_DIR/override"
      or die "could not replace override";

This can fail on windows when another urlader currently reads it, but
should work on all platforms even when other urlader programs execute
concurrently.

=item Cleaning up old directories

Urlader only packs executables once and then caches them in the
F<$URLADER_EXECDIR>. After upgrades there will be old versions in there
that are not being used anymore. Or are they?

Each instance directory (F<i-*>) in the F<$URLADER_EXE_DIR>) has an
associated lock file (F<i-*.lck>) - while urlader executes an app it keeps
a shared lock on this file.

To detect whether a version is in use or not, you must try to acquire an
exclusive lock, i.e.:

  my $lock = Urlader::lock "~/.urlader/myexe/i-ver01.lck", 1, 0;
  if (!$lock) {
     # instance dir is not in use and can be safely deleted
  }

If an older urlader wants to use an instance that was deleted or is
currently being deleted it will wait until it's gone and simply recreate
it, so while less efficient, deleting instance directories should always
be safe.

The lockfile itself can be deleted as long as you have an exclusive lock
on it (if your platform allows this).

=item A real world project

The only real world project using this that I know of at the moment is the
deliantra client (http://www.deliantra.net for more info).

It uses some scary scripts to build the client and some dependnet modules
(F<build.*>), to gather perl source files into a distribution tree, shared
objects and system shared libraries (some of which have to be patched or,
due to the horrible dll hell on OS X, even renamed), called C<gatherer>,
and a script called C<gendist> to build executable distributions.

These can be found at
L<http://cvs.schmorp.de/deliantra/Deliantra-Client/util/>, but looking at
them can lead to premature blindless.

=item Shared Libraries

It is often desirable to package shared libraries - for example the
Deliantra client packages SD>, Berkely DB, Pango and amny other libraries
that are unlikely to be available on the target system.

This usually requires some fiddling (see below), and additionally some
environment variables to be set.

For example, on ELF systems you usually want F<LD_LIBRARY_PATH=.> and on
OS X, you want F<DYLD_LIBRARY_PATH=.> (these are effectively the default
on windows).

These can most easily be specified when building the packfile:

   urlader-util ... LD_LIBRARY_PATH=. ./perl run

=item Portability: RPATH

Often F<perl> is linked against a shared F<libperl.so> - and might be so
using an rpath. Perl extensikns likewise might use an rpath, which means
the binary will mostly ignore LD_LIBRARY_PATH, which leads to trouble.

There is an utility called F<chrpath>, whose F<-d> option can remove the
rpath from binaries, shared library and shared objects.

=item Portability: OS X DLL HELL

OS X has the most severe form of DLL hell I have seen - if you link
against system libraries, which is practically unavoidable, you get
libraries of well-known names (e.g. libjpeg) that have nothing to do with
what you normally expect libjpeg to be, and there is no way to get your
version of libjpeg into your program.

Moreover, even if apple ships well-known libraries (e.g. libiconv), they
often ship patched versions which have a different ABI or even API then
the real releases.

The only way aorund this I found was to change all library names
in my releases (libjpeg.dylib becomes libdeliantra-jpeg.dylin and
so on), by patching the paths in the share dlibraries and shared
objects. F<install-name-tool> (with F<-id> and F<-change>) works in many
cases, but often paths are embedded indirectly, so you might have to use a
I<dirty> string replacement.

=back

=head1 SECURITY CONSIDERATIONS

The urlader executable itself does not support setuig/setgid operation, or
running with elevated privileges - it does no input sanitisation, and is
trivially exploitable.

=head1 AUTHOR

 Marc Lehmann <schmorp@schmorp.de>
 http://home.schmorp.de/

=cut

