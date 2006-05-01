BEGIN {
  $ENV{REQUEST_METHOD}='GET';
  $ENV{HTTP_USER_AGENT} = 'shell';
  $ENV{REMOTE_ADDR} = '127.0.0.1';
}

use Test::More qw(no_plan);

use strict;

use_ok("CGI::Persist::DBI");

SKIP: {
  eval "use DBD::SQLite";

  skip "DBD::SQLite not (propperly) installed", 2 if $@;
  
  my $createDB = 0;
  if ( !-f "./database" ) {
    $createDB = 1;
  }
  my $dbh = DBI->connect( 'DBI:SQLite:dbname=./database', '', '' );

  if ( $createDB ) {
    $dbh->do("create table sessions (ID varchar(10), session_info text, timestamp int)");
  }
  
  $@ = "";
  eval "use DBD::Log";

  if ( !$@ ) {
    use IO::File;
    my $fh = new IO::File "> dbd.log";

    $dbh = DBD::Log->new( dbi => $dbh,
                          logFH => $fh,
  			  dbiLogging => 0,
                        );
    
  }			

  my $cgi = CreateCGI( $dbh );
  ok( ref($cgi) =~ /cgi::persist::dbi/i );

  my $id = $cgi->ID;
  isnt( $id, undef );

  FakeRequest( id => $id, hoi => "Hallo", hallo => "Hoi" );

  $cgi = undef;
  $cgi = CreateCGI( $dbh );

  is($cgi->param("hoi"), "Hallo");

  $cgi = undef;
  $cgi = CreateCGI( $dbh );

  is($cgi->param("hoi"), "Hallo");

  FakeRequest( id => $id, hoi => "" );

  $cgi = undef;
  $cgi = CreateCGI( $dbh );

  is($cgi->param("hallo"), "Hoi");
}

sub FakeRequest{
  my @all = @_;
  my ($key, $val);
  my $str;

  while (($key, $val, @all ) =  @all) {
    $str .= ( $str ? "&" : "" ) . "$key=$val";
  }

  $ENV{QUERY_STRING}="$str";
  return 1;
}

sub CreateCGI {
  my $dbh = shift;
  my $stime = shift || 3;
  
  no CGI::Persist::DBI;
  $INC{'CGI/Persist/DBI.pm'} = '';

  use CGI::Persist::DBI;

  my $p = CGI::Persist::DBI->new( dbh          => $dbh,
				  sessionTime  => $stime,
				  logFile      => "./tmp/test.log",
				  errorLogFile => "./tmp/error.log",
				);

  return($p);
}