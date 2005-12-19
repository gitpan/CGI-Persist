use Test::More tests => 5;

# first make a tmp dir.
mkdir("tmp", 0775);

# dependencies
use_ok("Storable");
use Class::AccessorMaker { bla => '' }, 'no_new';

ok(UNIVERSAL::can("main", "bla"), "Class::AccessorMaker works - OK");

# can we use CGI::Persist?
use_ok("CGI::Persist");
use_ok("CGI::Persist::File");
use_ok("CGI::Persist::DBI");