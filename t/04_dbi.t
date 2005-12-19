use Test::More qw(no_plan);

use strict;

use_ok("CGI::Persist::DBI");

SKIP: {
  eval "use DBD::Mock";

  skip "DBD::Mock not (propperly) installed", 2 if $@;

  my $dbh = DBI->connect( 'DBI:Mock:', '', '' );

  my $cgi = CGI::Persist::DBI->new( dbh => $dbh );
  ok( ref($cgi) =~ /cgi::persist::dbi/i );

  my $id = $cgi->ID;
  is( $id, $dbh->{mock_all_history}->[1]->{bound_params}->[0] );
}
  

  